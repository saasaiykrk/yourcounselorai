"""CR-001 Case Snapshot: every snapshot field is collected (a value or a status) before the report,
nothing is asked twice, and the report's snapshot table is the app's own. Fake models only."""
import json
import unittest

from app import snapshot as snap
from app.consultation import (COMPLETED, INFORMATION_SUFFICIENT, QUESTIONING, SAFETY_STOP, SNAPSHOT,
                              ConsultationError, public_view)
from app.pipeline import DeidRejected
from tests.test_consultation import REPORT_R, Base, out

PANIC = "34F, panic attacks with sweating and palpitations, 4 weeks, sudden, no incident"


PANIC_RELEVANT = ["prior_therapy", "past_psychiatric_history", "medications", "medical_history",
                  "medical_review_since_onset", "substance_use", "functioning", "sleep_appetite"]


def extraction(fields, case_type="Adult panic attacks", summary="34-year-old woman with panic attacks for 4 weeks.",
               relevant=()):
    return {"fields": [{"key": k, "value": v} for k, v in fields], "relevant": list(relevant),
            "case_type": case_type, "case_summary": summary}


PANIC_EXTRACTED = extraction([("age", "34"), ("gender", "Female"),
                              ("presenting_concern", "panic attacks with sweating and palpitations"),
                              ("duration", "2–4 weeks"), ("onset", "Sudden"), ("precipitant", "None reported")],
                             relevant=PANIC_RELEVANT)
# Not needed for this case (optional): education, occupation, living_situation, family_structure, family_history.
NEEDED_REST = ["help_requested", "risk_screening", *PANIC_RELEVANT]

REST = {  # the clinician's answers for every field the case text did not give
    "education": {"chips": ["Graduate"]},
    "occupation": {"chips": ["Salaried"], "text": "IT professional"},
    "living_situation": {"chips": ["Spouse/partner", "Married"]},
    "help_requested": {"chips": ["Full case plan"]},
    "prior_therapy": {"chips": ["None"]},
    "past_psychiatric_history": {"chips": ["None"]},
    "medications": {"chips": ["None"]},
    "medical_history": {"chips": ["None known"]},
    "medical_review_since_onset": {"chips": ["No"]},
    "substance_use": {"chips": ["Caffeine (high)"]},
    "family_structure": {"chips": ["Supportive"]},
    "family_history": {"status": "not_known"},
    "risk_screening": {"chips": ["Asked and absent"]},
    "functioning": {"chips": ["Moderate"]},
    "sleep_appetite": {"chips": ["Reduced sleep"]},
}


def snapshot_section(text: str) -> str:
    return text.split("### Case Snapshot", 1)[1].split("### 1.", 1)[0]


class TestSnapshotForm(Base):
    def test_cr1_01_case_text_prefills_only_what_it_states_and_the_form_asks_for_the_rest(self):
        e = self.engine([PANIC_EXTRACTED])
        s = e.start(PANIC, snapshot=True)
        self.assertEqual(s["stage"], SNAPSHOT)
        self.assertIsNone(s["pending"], "no chat question before the form")
        prefilled = {k for k, v in s["snapshot"].items() if v["prefilled"]}
        self.assertEqual(prefilled, {"age", "gender", "presenting_concern", "duration", "onset", "precipitant"})
        self.assertEqual(sorted(snap.unresolved(s["snapshot"])), sorted(NEEDED_REST),
                         "only what this case needs is required")
        view = public_view(s, "x")["snapshot"]
        self.assertEqual(len(view["fields"]), 21)
        self.assertTrue(all(f["resolved"] == (f["key"] in prefilled) for f in view["fields"]))
        self.assertEqual({f["key"] for f in view["fields"] if f["optional"]},
                         {"education", "occupation", "living_situation", "family_structure", "family_history"})
        self.assertIn("status_labels", view["copy"])
        # The extraction call is its own small prompt: no skill, no report template.
        self.assertIn("Case Snapshot extraction", self.intake.systems[0])
        self.assertLess(len(self.intake.systems[0]), 8000)

    def test_continue_is_refused_until_every_field_has_a_value_or_status(self):
        e = self.engine([PANIC_EXTRACTED])
        s = e.start(PANIC, snapshot=True)
        with self.assertRaises(ConsultationError) as cm:
            e.update_snapshot(s, {"education": {"chips": ["Graduate"]}}, done=True)
        self.assertEqual(cm.exception.status, 409)
        self.assertIn("medications", cm.exception.detail)
        self.assertEqual(s["stage"], SNAPSHOT)

    def test_extraction_never_guesses_risk_and_drops_values_that_do_not_fit(self):
        e = self.engine([extraction([("risk_screening", "Risk present"), ("gender", "woman"), ("age", "thirty-ish"),
                                     ("duration", "about a month")])])
        s = e.start("Woman in her thirties, worried a lot for about a month.", snapshot=True)
        self.assertFalse(s["snapshot"]["risk_screening"]["chips"])
        self.assertFalse(s["snapshot"]["gender"]["chips"])
        self.assertEqual(s["snapshot"]["age"]["text"], "")
        self.assertEqual(s["snapshot"]["duration"]["chips"], [], "free text is not a duration option")

    def test_unusable_extraction_is_retried_then_leaves_the_form_empty(self):
        dropped = extraction([("presenting_concern", "call 9876543210")])   # identifier value: dropped
        bad = extraction([("age", "41")], summary="Reach the client on 9876543210.")  # fails inspect_intake
        e = self.engine([bad, bad])
        s = e.start("Adult with low mood for two months.", snapshot=True)
        self.assertEqual(len(self.intake.payloads), 2)
        self.assertEqual(s["stage"], SNAPSHOT)
        self.assertEqual(len(snap.unresolved(s["snapshot"])), 21, "no case check: every field is asked")
        self.assertNotIn("9876543210", json.dumps(s))
        e2 = self.engine([dropped])
        s2 = e2.start("Adult with low mood for two months.", snapshot=True)
        self.assertFalse(s2["snapshot"]["presenting_concern"]["prefilled"])

    def test_the_case_decides_which_fields_are_asked(self):
        child = extraction([("age", "8"), ("gender", "Male"), ("presenting_concern", "does not sit still in class")],
                           case_type="Child attention difficulties",
                           relevant=["education", "family_structure", "functioning", "sleep_appetite"])
        e = self.engine([child, out("ready")], [REPORT_R])
        s = e.start("8 year old boy, class 3, does not sit still, disturbs others", snapshot=True)
        needed = set(snap.unresolved(s["snapshot"]))
        self.assertEqual(needed, {"duration", "help_requested", "risk_screening", "education", "family_structure",
                                  "functioning", "sleep_appetite"})
        self.assertNotIn("occupation", needed)
        self.assertNotIn("living_situation", needed)
        e.update_snapshot(s, {"duration": {"chips": ["6–12 months"]}, "help_requested": {"chips": ["Full case plan"]},
                              "risk_screening": {"chips": ["Asked and absent"]}, "education": {"chips": ["Currently studying"]}, "family_structure": {"chips": ["Some conflict"]},
                              "functioning": {"chips": ["Moderate"]}, "sleep_appetite": {"chips": ["Normal"]},
                              "medications": {"chips": ["None"]}},          # an optional field the clinician knew
                          done=True)
        self.assertEqual(s["stage"], INFORMATION_SUFFICIENT)
        sent = snap.as_json(s["snapshot"])
        self.assertNotIn("occupation", sent, "an unasked optional field is not sent as a gap")
        self.assertEqual(sent["medications"], "None")
        r = e.report(s, "L2", today="2026-10-08")
        section = snapshot_section(r.display_text)
        self.assertNotIn("| Occupation |", section)
        self.assertNotIn("Skipped", section)
        self.assertIn("| Medications | None |", section)
        self.assertNotIn("Ask in the next session", section)

    def test_skip_remaining_never_marks_optional_fields(self):
        e = self.engine([PANIC_EXTRACTED])
        s = e.start(PANIC, snapshot=True)
        e.update_snapshot(s, {}, skip_remaining=True)
        self.assertIsNone(s["snapshot"]["occupation"]["status"])
        self.assertEqual(s["snapshot"]["medications"]["status"], "skipped")
        self.assertNotIn("Occupation", snap.ask_next(s["snapshot"]))

    def test_values_are_checked(self):
        e = self.engine([PANIC_EXTRACTED])
        s = e.start(PANIC, snapshot=True)
        for patch in ({"education": {"chips": ["PhD"]}},                     # not an option
                      {"gender": {"chips": ["Female", "Male"]}},             # one only
                      {"gender": {"text": "woman"}},                        # options only
                      {"age": {"text": "young"}},                           # a number
                      {"risk_screening": {"status": "not_applicable"}},     # not offered for risk
                      {"nonsense": {"chips": []}}):
            with self.assertRaises(ConsultationError, msg=patch) as cm:
                e.update_snapshot(s, patch)
            self.assertEqual(cm.exception.status, 422)

    def test_cr1_07_identifiers_in_a_text_field_are_refused(self):
        e = self.engine([PANIC_EXTRACTED])
        s = e.start(PANIC, snapshot=True)
        with self.assertRaises(DeidRejected):
            e.update_snapshot(s, {"occupation": {"chips": ["Salaried"], "text": "call her on 9876543210"}})

    def test_cr1_06_risk_present_shows_the_emergency_guidance_straight_away(self):
        e = self.engine([PANIC_EXTRACTED])
        s = e.start(PANIC, snapshot=True)
        calls = len(self.intake.payloads)
        e.update_snapshot(s, {"risk_screening": {"chips": ["Risk present"]}})
        self.assertEqual(s["stage"], SAFETY_STOP)
        self.assertEqual(len(self.intake.payloads), calls, "no model call before the safety pathway")
        e.reply(s, "safety_managed")
        self.assertEqual(s["stage"], SNAPSHOT, "back to the form afterwards")
        self.assertEqual(s["snapshot"]["risk_screening"]["chips"], ["Risk present"])
        self.assertIn("managed", s["snapshot"]["risk_screening"]["text"])
        e.update_snapshot(s, {"education": {"chips": ["Graduate"]}})      # saving again does not re-trigger
        self.assertEqual(s["stage"], SNAPSHOT)

    def test_the_form_can_send_back_the_confirmed_risk_field(self):
        # After the safety step the app re-sends every field, the server's own risk note included.
        e = self.engine([PANIC_EXTRACTED])
        s = e.start(PANIC, snapshot=True)
        e.update_snapshot(s, {"risk_screening": {"chips": ["Risk present"]}})
        e.reply(s, "safety_managed")
        risk = s["snapshot"]["risk_screening"]
        e.update_snapshot(s, {"risk_screening": {"chips": risk["chips"], "text": risk["text"]}}, skip_remaining=True)
        self.assertEqual(s["stage"], INFORMATION_SUFFICIENT)
        self.assertIn("managed", s["snapshot"]["risk_screening"]["text"])
        with self.assertRaises(ConsultationError):
            e.update_snapshot(s, {"risk_screening": {"chips": ["Asked and absent"], "text": "anything else"}})

    def test_risk_in_the_case_text_stops_first_then_the_form_is_prefilled(self):
        e = self.engine([PANIC_EXTRACTED])
        s = e.start("34F, panic attacks, said she wants to die last week", snapshot=True)
        self.assertEqual(s["stage"], SAFETY_STOP)
        self.assertEqual(self.intake.payloads, [])
        e.reply(s, "safety_managed")
        self.assertEqual(s["stage"], SNAPSHOT)
        self.assertEqual(s["snapshot"]["age"]["text"], "34")
        self.assertEqual(s["snapshot"]["risk_screening"]["chips"], ["Risk present"])


class TestCaseQuestions(Base):
    def completed(self, intake_after, report_replies=()):
        e = self.engine([PANIC_EXTRACTED, *intake_after], report_replies)
        s = e.start(PANIC, snapshot=True)
        e.update_snapshot(s, REST, done=True)
        return e, s

    def test_cr1_03_a_question_about_a_snapshot_field_is_dropped_and_asked_differently(self):
        e, s = self.completed([
            out("ask", question="How long have the attacks been happening?", field="duration"),
            out("ask", question="How often do the attacks come, and are they unexpected?", field="attack_frequency",
                options=["Daily", "Weekly"]),
        ])
        self.assertEqual(s["stage"], QUESTIONING)
        self.assertEqual(s["pending"]["field"], "attack_frequency")
        self.assertEqual(s["questions_asked"], 1, "the duplicate never reached the clinician")
        self.assertIn("[DUPLICATE]", self.intake.payloads[-1])
        self.assertIn('"case_snapshot"', self.intake.payloads[1], "the completed snapshot goes with the request")

    def test_aliases_are_duplicates_too_and_two_duplicates_end_the_questions(self):
        e, s = self.completed([
            out("ask", question="How long, and did it start suddenly?", field="duration_onset"),
            out("ask", question="Any medicines?", field="current_medication"),
        ])
        self.assertEqual(s["stage"], INFORMATION_SUFFICIENT)
        self.assertEqual(s["questions_asked"], 0)

    def test_an_already_answered_question_is_not_asked_again(self):
        e, s = self.completed([
            out("ask", question="How often do the attacks come?", field="attack_frequency"),
            out("ask", question="How often do they come?", field="attack_frequency"),
            out("ready"),
        ])
        e.reply(s, "answer", "Three times a week, mostly unexpected")
        self.assertEqual(s["stage"], INFORMATION_SUFFICIENT)
        self.assertEqual(s["questions_asked"], 1)

    def test_at_most_four_case_questions(self):
        asks = [out("ask", question=f"Case question {i}?", field=f"case_detail_{i}") for i in range(4)]
        e, s = self.completed([*asks, out("ready")])
        for i in range(3):
            e.reply(s, "answer", f"answer {i}")
        self.assertEqual(s["questions_asked"], 4)
        e.reply(s, "answer", "answer 3")
        self.assertIn("question limit is reached", self.intake.payloads[-1])
        self.assertEqual(s["stage"], INFORMATION_SUFFICIENT)
        self.assertEqual(public_view(s, "x")["max_questions"], 4)

    def test_the_model_cannot_overwrite_a_snapshot_field(self):
        e, s = self.completed([out("ready", facts=[{"field": "medications", "value": "unknown"},
                                                   {"field": "attack_frequency", "value": "3 a week"}],
                                   unknown=["duration"])])
        self.assertEqual(s["snapshot"]["medications"]["chips"], ["None"])
        self.assertNotIn("medications", s["facts"])
        self.assertNotIn("duration", s["unknown"])
        self.assertEqual(s["facts"]["attack_frequency"], "3 a week")


class TestSnapshotReport(Base):
    def run_report(self, rest=REST, skip=False, intake_after=(out("ready"),), replies=(REPORT_R,)):
        e = self.engine([PANIC_EXTRACTED, *intake_after], replies)
        s = e.start(PANIC, snapshot=True)
        if skip:
            e.update_snapshot(s, rest, skip_remaining=True)
        else:
            e.update_snapshot(s, rest, done=True)
        r = e.report(s, "L2", today="2026-10-08")
        return e, s, r

    def test_cr1_02_the_report_snapshot_is_the_apps_table_with_no_not_provided(self):
        e, s, r = self.run_report()
        self.assertEqual(r.status, "delivered", r.reports)
        section = snapshot_section(r.display_text)
        self.assertNotIn("not provided", section.lower())
        self.assertIn("| Age | 34 years |", section)
        self.assertIn("| Occupation | Salaried — IT professional |", section)
        self.assertNotIn("Family history", section, "not known: left out of the report")
        self.assertNotIn("Class 4", section, "the model's own table is gone")
        self.assertIn("**Risk screening:**", section, "the model's risk line is kept")
        sent = self.report_model.seen[0][1][-1]["content"]
        self.assertIn("<case_snapshot>", sent)
        self.assertIn(PANIC, sent)
        self.assertIn("not_known", sent)

    def test_cr1_04_not_yet_asked_is_shown_and_listed_for_the_next_session(self):
        rest = {**REST, "education": {"status": "not_yet_asked"}}
        e, s, r = self.run_report(rest)
        section = snapshot_section(r.display_text)
        self.assertNotIn("| Education |", section, "only answered fields are rows")
        self.assertIn("**Ask in the next session:** Education.", section)

    def test_cr1_05_skip_remaining_marks_the_rest_skipped_and_still_reports(self):
        e = self.engine([PANIC_EXTRACTED], [REPORT_R])
        s = e.start(PANIC, snapshot=True)
        e.update_snapshot(s, {"medications": {"chips": ["None"]}}, skip_remaining=True)
        self.assertEqual(s["stage"], INFORMATION_SUFFICIENT, "straight to the report")
        self.assertEqual(s["snapshot"]["prior_therapy"]["status"], "skipped")
        r = e.report(s, "L2", today="2026-10-08")
        self.assertEqual(r.status, "delivered", r.reports)
        section = snapshot_section(r.display_text)
        self.assertNotIn("| Prior therapy |", section)
        self.assertIn("| Medications | None |", section)
        self.assertIn("Ask in the next session:** Help requested, Prior therapy", section)

    def test_cr1_08_medications_none_is_never_shown_as_unknown(self):
        e, s, r = self.run_report()
        self.assertEqual(snap.as_json(s["snapshot"])["medications"], "None")
        self.assertIn("| Medications | None |", snapshot_section(r.display_text))

    def test_cr1_09_editing_after_the_report_lets_it_be_updated(self):
        e, s, r = self.run_report(replies=(REPORT_R, REPORT_R))
        self.assertEqual(s["stage"], COMPLETED)
        e.update_snapshot(s, {"medications": {"chips": ["Yes (list)"], "text": "sertraline 50 mg"}})
        self.assertEqual(s["stage"], INFORMATION_SUFFICIENT)
        r2 = e.report(s, "L2", today="2026-10-08")
        self.assertIn("| Medications | Yes (list) — sertraline 50 mg |", snapshot_section(r2.display_text))

    def test_report_is_refused_while_the_form_is_open(self):
        e = self.engine([PANIC_EXTRACTED])
        s = e.start(PANIC, snapshot=True)
        with self.assertRaises(ConsultationError):
            e.report(s, "L2", force=True)

    def test_the_inspector_sees_the_final_table(self):
        # The swap happens before inspection: what is inspected is exactly what is shown.
        e, s, r = self.run_report()
        self.assertIn("| Medications | None |", r.raw_text)


class TestRendering(unittest.TestCase):
    def test_table_goes_in_place_of_the_models_table_only(self):
        s = snap.empty()
        s["age"] = {"chips": [], "text": "34", "status": None, "prefilled": True}
        text = ("## R\n\n### Case Snapshot\n\n| Field | Details |\n| --- | --- |\n| Age | (not provided) |\n\n"
                "**Risk screening:** asked.\n\n### 1. Pattern\n| a | b |\n")
        out_text = snap.apply_table(text, s)
        self.assertIn("| Age | 34 years |", out_text)
        self.assertNotIn("(not provided)", out_text)
        self.assertIn("### 1. Pattern\n| a | b |", out_text, "later tables untouched")
        self.assertIn("**Risk screening:** asked.", out_text)

    def test_section_without_a_table_gets_one(self):
        s = snap.empty()
        s["age"] = {"chips": [], "text": "34", "status": None, "prefilled": False}
        out_text = snap.apply_table("### Case Snapshot\n**Risk screening:** x\n### 1. A\n", s)
        self.assertIn("| Field | Details |\n| --- | --- |\n| Age | 34 years |", out_text.split("### 1.")[0])

    def test_nothing_answered_means_no_empty_table(self):
        out_text = snap.render_table(snap.empty())
        self.assertNotIn("| Field |", out_text)
        self.assertTrue(out_text.startswith("**Ask in the next session:**"))

    def test_no_snapshot_heading_leaves_the_text_alone(self):
        self.assertEqual(snap.apply_table("no heading here", snap.empty()), "no heading here")

    def test_pipe_in_a_value_cannot_break_the_table(self):
        s = snap.empty()
        s["presenting_concern"] = {"chips": [], "text": "panic | worry", "status": None, "prefilled": False}
        self.assertIn("| Presenting concern | panic / worry |", snap.render_table(s))

    def test_every_field_is_defined_once_with_a_known_status_set(self):
        keys = [f["key"] for f in snap.definitions()]
        self.assertEqual(len(keys), len(set(keys)))
        for f in snap.definitions():
            self.assertTrue(set(f["statuses"]) <= set(snap.CHOSEN_STATUSES), f["key"])
            self.assertTrue(f["question"] and f["label"], f["key"])
        self.assertEqual(set(snap.ui_copy()["report_labels"]), set(snap.STATUSES))
        json.dumps(snap.public(snap.empty()))


if __name__ == "__main__":
    unittest.main()
