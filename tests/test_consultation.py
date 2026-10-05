"""Guided consultation engine with a fake model: stages, compact state, the edge cases, and the report."""
import json
import pathlib
import unittest

from app.consultation import (COMPLETED, INFORMATION_SUFFICIENT, MAX_QUESTIONS, QUESTIONING, SAFETY_STOP,
                              ConsultationEngine, ConsultationError, public_view)
from app.pipeline import DeidRejected, ModelResult, Pipeline
from app.prompt import load_consult_prompts, load_skill

ROOT = pathlib.Path(__file__).parent.parent
SKILL_DIR = str(ROOT / "skill" / "clinical-assist")
REPORT_R = (ROOT / "fixtures" / "golden" / "consult_report_ocd.md").read_text()
R_CODES = ["6B20", "6B20.0", "6B20.1", "6B25", "6B25.0", "6B03", "6C51", "6A02", "8A05"]

ALL_MANDATORY = [{"field": "presenting_concern", "value": "rituals, hair picking, fear of dark, screen overuse"},
                 {"field": "age_gender", "value": "9 years, male"},
                 {"field": "risk_screening", "value": "asked and absent"},
                 {"field": "duration_onset", "value": "about 10 months, gradual"}]


def out(status="ask", facts=(), question="", field="", why="", options=(), unknown=(), summary="", brief=""):
    return {"status": status, "facts_patch": list(facts), "unknown_fields": list(unknown), "case_summary": summary,
            "question": question, "why": why, "field": field, "options": list(options), "brief_answer": brief}


class FakeIntake:
    """Scripted intake responses; records every payload it was sent."""
    def __init__(self, replies):
        self.replies, self.payloads, self.systems = list(replies), [], []

    def run_structured(self, system, user, schema):
        self.systems.append(system)
        self.payloads.append(user)
        return self.replies.pop(0), {"input_tokens": 100, "output_tokens": 20}


class FakeReportModel:
    def __init__(self, replies):
        self.replies, self.seen = list(replies), []

    def run(self, system, messages, tools, tool_handler):
        self.seen.append((system, messages))
        tool_handler("icd11_lookup", {"query": "obsessive-compulsive"})
        return ModelResult(text=self.replies.pop(0), model="fake")


class FakeICD:
    release = "test"

    def search(self, q, limit=8):
        return [{"code": c, "title": "t", "release": "test"} for c in R_CODES]


class Base(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.skill = load_skill(SKILL_DIR)
        cls.prompts = load_consult_prompts(SKILL_DIR)

    def engine(self, intake_replies, report_replies=()):
        self.intake = FakeIntake(intake_replies)
        self.report_model = FakeReportModel(report_replies)
        return ConsultationEngine(self.prompts, self.intake, Pipeline(self.skill, self.report_model, FakeICD()))


class TestQuestioning(Base):
    def test_detailed_case_needs_no_questions(self):
        e = self.engine([out("ready", ALL_MANDATORY, summary="9-year-old boy with OCD-like rituals.")])
        s = e.start("9 year old boy, rituals for 10 months, gradual, risk asked and absent. Full plan please.")
        self.assertEqual(s["stage"], INFORMATION_SUFFICIENT)
        self.assertIsNone(s["pending"])
        self.assertEqual(len(self.intake.payloads), 1)
        self.assertEqual(s["facts"]["age_gender"], "9 years, male")

    def test_vague_case_asks_one_question_at_a_time(self):
        e = self.engine([out("ask", [{"field": "presenting_concern", "value": "worried about child"}],
                             question="What does the child do that worries the parents?", field="behaviours",
                             why="Behaviours set the formulation.", summary="Parent worried about child.")])
        s = e.start("Parents are worried about their son.")
        self.assertEqual(s["stage"], QUESTIONING)
        self.assertEqual(s["pending"]["question"], "What does the child do that worries the parents?")
        self.assertEqual(s["questions_asked"], 1)

    def test_only_compact_state_and_latest_reply_are_sent(self):
        e = self.engine([
            out("ask", [{"field": "presenting_concern", "value": "rituals"}], question="How old is he?",
                field="age_gender", summary="Child with rituals."),
            out("ask", [{"field": "age_gender", "value": "9, male"}], question="How long has this gone on?",
                field="duration_onset", summary="9-year-old boy with rituals."),
        ])
        s = e.start("FIRST-MESSAGE-MARKER child with rituals")
        e.reply(s, "answer", "SECOND-ANSWER-MARKER he is 9")
        second = self.intake.payloads[1]
        self.assertNotIn("FIRST-MESSAGE-MARKER", second)            # earlier raw text is never re-sent
        self.assertIn("SECOND-ANSWER-MARKER", second)               # only the latest reply
        self.assertIn('"presenting_concern":"rituals"', second)     # …plus the compact facts
        self.assertIn("How old is he?", second)                     # and the question it answers
        state = json.loads(second.split("\n")[1])
        self.assertEqual(set(state), {"case_summary", "facts", "unknown", "questions_asked", "max_questions"})

    def test_intake_never_receives_the_skill_or_report_template(self):
        e = self.engine([out("ready", ALL_MANDATORY)])
        e.start("case")
        self.assertNotIn("Consultation Report — fixed template", self.intake.systems[0])
        self.assertLess(len(self.intake.systems[0]), 12000)

    def test_several_answers_in_one_reply_are_all_kept_and_not_asked_again(self):
        e = self.engine([
            out("ask", [{"field": "presenting_concern", "value": "rituals"}], question="How old is he?",
                field="age_gender"),
            # the model records two facts, then (wrongly) asks about one it already has
            out("ask", [{"field": "age_gender", "value": "9, male"}, {"field": "duration_onset", "value": "10 months"}],
                question="How long has this been going on?", field="duration_onset"),
        ])
        s = e.start("child with rituals")
        e.reply(s, "answer", "9-year-old boy, about 10 months")
        self.assertEqual(s["facts"]["duration_onset"], "10 months")
        # duration is known, so the server does not ask it again: the missing mandatory (risk) comes next
        self.assertEqual(s["pending"]["field"], "risk_screening")
        self.assertEqual(s["pending"]["options"], ["Asked and absent", "Risk present", "Not yet asked"])

    def test_changed_answer_overwrites_the_fact(self):
        e = self.engine([out("ask", [{"field": "age_gender", "value": "9, male"}], question="Q?", field="duration_onset"),
                         out("ask", [{"field": "age_gender", "value": "11, male"}], question="Q2?", field="triggers")])
        s = e.start("9 year old boy")
        e.reply(s, "answer", "sorry, he is 11 not 9")
        self.assertEqual(s["facts"]["age_gender"], "11, male")

    def test_dont_know_marks_unknown_and_moves_on(self):
        e = self.engine([out("ready", [{"field": "presenting_concern", "value": "low mood"}])])
        s = e.start("client with low mood")
        self.assertEqual(s["pending"]["field"], "age_gender")        # mandatory question from the guide
        calls = len(self.intake.payloads)
        e.reply(s, "dont_know")
        self.assertIn("age_gender", s["unknown"])
        self.assertEqual(s["pending"]["field"], "risk_screening")    # next mandatory: still no model call
        self.assertEqual(len(self.intake.payloads), calls)
        self.assertEqual(s["transcript"][0]["answer"], "(don't know)")

    def test_unknown_field_is_never_asked_again(self):
        e = self.engine([
            out("ask", ALL_MANDATORY[:1], question="Any prior therapy?", field="prior_therapy"),
            out("ask", [], question="Has she had therapy before?", field="prior_therapy"),
        ])
        s = e.start("client with low mood")
        e.reply(s, "skip")
        self.assertNotEqual((s["pending"] or {}).get("field"), "prior_therapy")

    def test_model_says_ready_but_mandatory_missing_asks_the_guide_question(self):
        e = self.engine([out("ready", ALL_MANDATORY[:2])])
        s = e.start("case")
        self.assertEqual(s["stage"], QUESTIONING)
        self.assertEqual(s["pending"]["field"], "risk_screening")
        self.assertEqual(len(self.intake.payloads), 1)

    def test_clinician_question_gets_a_brief_answer_then_the_next_question(self):
        e = self.engine([
            out("ask", ALL_MANDATORY[:1], question="How old is the client?", field="age_gender"),
            out("ask", [], question="How old is the client?", field="age_gender",
                brief="ERP is first-line for OCD in children."),
        ])
        s = e.start("child with rituals")
        e.reply(s, "answer", "Is ERP suitable for children?")
        self.assertEqual(s["brief_answer"], "ERP is first-line for OCD in children.")
        self.assertEqual(s["pending"]["question"], "How old is the client?")

    def test_question_limit(self):
        replies = [out("ask", ALL_MANDATORY if i == 0 else [], question=f"Q{i}?", field=f"f{i}")
                   for i in range(MAX_QUESTIONS + 1)]
        e = self.engine(replies)
        s = e.start("case")
        for _ in range(MAX_QUESTIONS):
            if s["stage"] != QUESTIONING:
                break
            e.reply(s, "answer", "an answer")
        self.assertEqual(s["stage"], INFORMATION_SUFFICIENT)
        self.assertLessEqual(s["questions_asked"], MAX_QUESTIONS)
        self.assertIn("question limit is reached", self.intake.payloads[-1])

    def test_finish_early_then_report_is_allowed(self):
        e = self.engine([out("ask", ALL_MANDATORY[:1], question="How old?", field="age_gender")])
        s = e.start("case")
        e.reply(s, "finish")
        self.assertEqual(s["stage"], INFORMATION_SUFFICIENT)

    def test_finish_needs_some_case_information(self):
        e = self.engine([out("ask", [], question="What is the concern?", field="presenting_concern")])
        s = e.start("hello")
        with self.assertRaises(ConsultationError):
            e.reply(s, "finish")

    def test_edit_facts_is_deterministic_and_checked(self):
        e = self.engine([out("ready", ALL_MANDATORY)])
        s = e.start("case")
        calls = len(self.intake.payloads)
        e.edit_facts(s, {"age_gender": "10 years, male", "medications": None})
        self.assertEqual(s["facts"]["age_gender"], "10 years, male")
        self.assertEqual(len(self.intake.payloads), calls)
        with self.assertRaises(DeidRejected):
            e.edit_facts(s, {"family": "father on 9876543210"})


class TestSafetyAndChecks(Base):
    def test_identifiers_in_the_case_are_refused(self):
        e = self.engine([])
        with self.assertRaises(DeidRejected):
            e.start("Client reachable at 9876543210 has panic attacks")
        self.assertEqual(self.intake.payloads, [])

    def test_risk_in_an_answer_stops_without_a_model_call(self):
        e = self.engine([out("ask", ALL_MANDATORY[:2], question="Any risk?", field="risk_screening"),
                         out("ready", ALL_MANDATORY)])
        s = e.start("teen with low mood")
        e.reply(s, "answer", "She said she wants to die and has kept pills at home")
        self.assertEqual(s["stage"], SAFETY_STOP)
        self.assertEqual(len(self.intake.payloads), 1)
        with self.assertRaises(ConsultationError):
            e.reply(s, "answer", "more details")
        e.reply(s, "safety_managed")
        self.assertEqual(s["facts"]["risk_screening"], "risk present — clinician confirmed immediate safety is managed")
        self.assertIn("do not return risk_stop", self.intake.payloads[-1])
        self.assertEqual(s["stage"], INFORMATION_SUFFICIENT)

    def test_model_risk_stop(self):
        e = self.engine([out("risk_stop", [])])
        s = e.start("adolescent, worried parents, recent change in behaviour")
        self.assertEqual(s["stage"], SAFETY_STOP)

    def test_bad_intake_output_is_retried_with_the_failures(self):
        e = self.engine([
            out("ask", [], question="Can I call the mother on 9876543210?", field="family"),
            out("ask", ALL_MANDATORY[:1], question="Who does the child live with?", field="family"),
        ])
        s = e.start("child with rituals")
        self.assertIn("IDENTIFIER", self.intake.payloads[1])
        self.assertEqual(s["pending"]["question"], "Who does the child live with?")

    def test_two_bad_outputs_fall_back_without_storing_anything(self):
        bad = out("ask", [{"field": "family", "value": "mother 9876543210"}], question="Q?", field="x")
        e = self.engine([bad, bad])
        s = e.start("child with rituals")
        self.assertNotIn("family", s["facts"])
        self.assertEqual(s["pending"]["field"], "presenting_concern")   # guide's own question

    def test_public_view_has_no_usage_or_raw_case(self):
        e = self.engine([out("ask", ALL_MANDATORY[:1], question="How old?", field="age_gender")])
        v = public_view(e.start("child with rituals"), "id-1")
        self.assertNotIn("usage", v)
        self.assertNotIn("case_text", v)
        self.assertEqual(v["question"]["number"], 1)


class TestReport(Base):
    def ready_state(self, e):
        return e.start("9-year-old boy with rituals")

    def test_report_uses_mode_r_template_and_compact_case(self):
        e = self.engine([out("ready", ALL_MANDATORY, summary="9-year-old boy with rituals.")], [REPORT_R])
        s = self.ready_state(e)
        r = e.report(s, "L2")
        self.assertEqual(r.status, "delivered")
        self.assertEqual(s["stage"], COMPLETED)
        system, messages = self.report_model.seen[0]
        self.assertEqual(system[0], self.skill.system_prompt)        # cached skill part unchanged
        self.assertIn("Consultation Report — fixed template", system[1])
        self.assertIn("Requested mode: R", messages[-1]["content"])
        self.assertIn("- age_gender: 9 years, male", messages[-1]["content"])
        self.assertNotIn("Consultation Report — fixed template", self.intake.systems[0])

    def test_report_needs_enough_information_unless_forced(self):
        e = self.engine([out("ask", ALL_MANDATORY[:1], question="How old?", field="age_gender")], [REPORT_R])
        s = e.start("child with rituals")
        with self.assertRaises(ConsultationError):
            e.report(s, "L2")
        r = e.report(s, "L2", force=True)
        self.assertEqual(r.status, "delivered")
        self.assertIn("Not asked (report as not provided): age_gender", self.report_model.seen[0][1][-1]["content"])

    def test_held_back_report_can_be_retried(self):
        broken = REPORT_R.replace("### 4. Therapy Modalities to Consider", "### 4. Options")
        e = self.engine([out("ready", ALL_MANDATORY)], [broken, broken])
        s = self.ready_state(e)
        r = e.report(s, "L2")
        self.assertEqual(r.status, "blocked")
        self.assertEqual(s["stage"], INFORMATION_SUFFICIENT)

    def test_no_second_report_once_completed(self):
        e = self.engine([out("ready", ALL_MANDATORY)], [REPORT_R])
        s = self.ready_state(e)
        e.report(s, "L2")
        with self.assertRaises(ConsultationError):
            e.report(s, "L2")
