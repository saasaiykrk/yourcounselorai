import json
import pathlib
import re
import unittest

from app.inspector import InspectionContext, inspect, strip_meta

ROOT = pathlib.Path(__file__).parent.parent
GOLD = ROOT / "fixtures" / "golden"
EVALS = {e["id"]: e["prompt"] for e in json.loads((ROOT / "evals" / "evals.json").read_text())["evals"]}

MODE_A = (GOLD / "mode_a_panic.md").read_text()
GATE1 = (GOLD / "gate1_minor.md").read_text()
MODE_B = (GOLD / "mode_b_ocd.md").read_text()


def ctx(level="L2", user_input=EVALS[1], **kw):
    return InspectionContext(level=level, user_input=user_input, **kw)


def codes(rep):
    return {f.code for f in rep.blocks}


class TestGoldenOutputsPass(unittest.TestCase):
    def test_mode_a_example_passes(self):
        rep = inspect(MODE_A, ctx())
        self.assertTrue(rep.passed, rep.as_dict())

    def test_gate1_minor_passes(self):
        rep = inspect(GATE1, ctx(user_input=EVALS[2]))
        self.assertTrue(rep.passed, rep.as_dict())

    def test_mode_b_passes(self):
        rep = inspect(MODE_B, ctx(user_input=EVALS[4]))
        self.assertTrue(rep.passed, rep.as_dict())

    def test_strip_meta(self):
        self.assertFalse(strip_meta(MODE_A).lstrip().startswith("<!--"))


class TestBlocks(unittest.TestCase):
    def test_missing_meta(self):
        self.assertIn("META", codes(inspect(strip_meta(MODE_A), ctx())))

    def test_missing_disclaimer(self):
        out = MODE_A.replace("It does not diagnose or replace therapy.", "")
        self.assertIn("DISCLAIMER", codes(inspect(out, ctx())))

    def test_disclaimer_not_last(self):
        out = MODE_A + "\n\n## Extra section\n" + ("More text. " * 40)
        self.assertIn("DISCLAIMER", codes(inspect(out, ctx())))

    def test_missing_safety_section(self):
        out = MODE_A.replace("### 2. Safety & Risk Screen", "### 2. Notes")
        self.assertIn("SAFETY", codes(inspect(out, ctx())))

    def test_missing_section(self):
        out = MODE_A.replace("### 15. PROVISIONAL", "### Fifteen PROVISIONAL")
        self.assertIn("STRUCTURE", codes(inspect(out, ctx())))

    def test_provisional_missing(self):
        out = MODE_A.replace("### 5. PROVISIONAL — Low confidence · Severity", "### 5. Severity")
        self.assertIn("PROVISIONAL", codes(inspect(out, ctx())))

    def test_ceiling_inconsistent_with_rating(self):
        out = MODE_A.replace("ceiling=Low", "ceiling=Moderate")
        self.assertIn("CEILING", codes(inspect(out, ctx())))

    def test_level_mismatch(self):
        self.assertIn("LEVEL", codes(inspect(MODE_A, ctx(level="L1"))))

    def test_l1_rules(self):
        out = MODE_A.replace("level=L2", "level=L1")
        c = codes(inspect(out, ctx(level="L1")))
        self.assertIn("L1", c)

    def test_medication_recommendation(self):
        out = MODE_A.replace("**Secondary:** brief grounding", "**Secondary:** consider starting an SSRI; brief grounding")
        self.assertIn("MEDICATION", codes(inspect(out, ctx())))

    def test_prescriber_line_allowed(self):
        self.assertIn("appropriately qualified prescriber", MODE_A)
        self.assertNotIn("MEDICATION", codes(inspect(MODE_A, ctx())))

    def test_retired_crisis_line(self):
        out = MODE_A.replace("emergency care (112)", "emergency care (112) or KIRAN 1800-599-0019")
        self.assertIn("CRISIS_NUMBERS", codes(inspect(out, ctx())))

    def test_unknown_helpline_number(self):
        out = MODE_A.replace("emergency care (112)", "emergency care (112) or call helpline 9152987821")
        self.assertIn("CRISIS_NUMBERS", codes(inspect(out, ctx())))

    def test_unverified_icd_code(self):
        out = MODE_A.replace("ICD-11 panic disorder, code to confirm", "ICD-11 panic disorder 6B01")
        self.assertIn("ICD_CODE", codes(inspect(out, ctx())))

    def test_verified_icd_code_ok(self):
        out = MODE_A.replace("ICD-11 panic disorder, code to confirm", "ICD-11 panic disorder 6B01")
        self.assertNotIn("ICD_CODE", codes(inspect(out, ctx(verified_icd_codes={"6B01"}))))

    def test_interoceptive_needs_clearance(self):
        out = (MODE_A.replace("after medical clearance", "")
                     .replace("Only after medical clearance", "")
                     .replace("after medical clearance only", "")
                     .replace("medical clearance", "")
                     .replace("after clearance", "")
                     .replace("if cleared", ""))
        self.assertIn("UNSAFE_HOMEWORK", codes(inspect(out, ctx())))

    def test_session_table_columns(self):
        out = MODE_A.replace("| Wk | Focus | Clinical objective |", "| Wk | Clinical objective |")
        self.assertIn("SESSION_TABLE", codes(inspect(out, ctx())))

    def test_decision_tree_branch_missing(self):
        out = MODE_A.replace("**Worsening:**", "**Getting worse:**")
        self.assertIn("DECISION_TREE", codes(inspect(out, ctx())))

    def test_no_harm_contract(self):
        out = MODE_A.replace("**Between sessions:**", "Ask the client to sign a no-harm contract. **Between sessions:**")
        self.assertIn("NO_HARM_CONTRACT", codes(inspect(out, ctx())))

    def test_identifier_echo(self):
        out = MODE_A.replace("### 2. Safety & Risk Screen", "### 2. Safety & Risk Screen\nClient phone 9876543210.")
        self.assertIn("IDENTIFIER", codes(inspect(out, ctx())))


class TestGates(unittest.TestCase):
    def test_risk_input_without_gate1_blocks(self):
        rep = inspect(MODE_B.replace("mode=B", "mode=B"), ctx(user_input=EVALS[2]))
        self.assertIn("GATE1", codes(rep))

    def test_risk_input_with_safety_managed_ok(self):
        msg = EVALS[2] + " Safety plan in place, admitted overnight, parents informed."
        self.assertNotIn("GATE1", codes(inspect(MODE_B, ctx(user_input=msg))))

    def test_negated_risk_phrase_does_not_force_gate1(self):
        # A screened, negative risk finding is not a risk indicator.
        for neg in ("Denies suicidal ideation.", "No suicidal ideation, no self-harm.", "Not suicidal.",
                    "Nil suicidal ideation.", "Negative for suicidal ideation.", "Denies any current suicidal thoughts.",
                    "No history of overdose.", "Denied wanting to die when asked directly."):
            with self.subTest(neg):
                self.assertNotIn("GATE1", codes(inspect(MODE_B, ctx(user_input=EVALS[1] + " " + neg))))

    def test_negation_never_hides_another_risk_phrase(self):
        # Only the phrase right after the negation is cleared; anything else still forces Gate 1.
        for msg in ("Denies suicidal ideation but has kept pills at home.",
                    "Denies suicidal ideation; told her sister she wants to die.",
                    "No one knows she wants to die.",
                    "Not only suicidal thoughts, he bought pesticide.",
                    "No improvement. Wants to die.",
                    "She never denies that she wants to die.",
                    "Denies suicidal ideation, overdose last month."):
            with self.subTest(msg):
                self.assertIn("GATE1", codes(inspect(MODE_B, ctx(user_input=EVALS[1] + " " + msg))))

    def test_gate1_with_planning_blocks(self):
        out = GATE1.replace("Routine planning will follow", "### 13. Session plan\n| Week | Focus |\nRoutine planning will follow")
        self.assertIn("GATE1", codes(inspect(out, ctx(user_input=EVALS[2]))))

    def test_gate1_minor_needs_1098(self):
        out = GATE1.replace("· Child Helpline 1098 ", "")
        self.assertIn("SAFEGUARD", codes(inspect(out, ctx(user_input=EVALS[2]))))

    def test_scores_need_screening_line(self):
        out = MODE_B.replace("mode=B", "mode=B")
        self.assertIn("SCREENING", codes(inspect(out, ctx(user_input=EVALS[3]))))


if __name__ == "__main__":
    unittest.main()


# --- Guided consultation: the fixed Consultation Report (Mode R) ---------------
from app.inspector import inspect_intake  # noqa: E402

REPORT_R = (GOLD / "consult_report_ocd.md").read_text()
CASE_R = ("Case summary: 9-year-old boy, Class 4. Holds saliva then spits, rewinds reels, makes parents repeat "
          "words, avoids black objects ('black omen'), picks hair, fear of darkness, heavy YouTube and Roblox use. "
          "About 10 months, gradual. No prior therapy, no medications. Lives with parents and older sibling. "
          "Risk screening: not yet asked. Help requested: full plan with parent coaching.")
R_CODES = {"6B20", "6B20.0", "6B20.1", "6B25", "6B25.0", "6B03", "6C51", "6A02", "8A05"}


def rctx(level="L2", **kw):
    return InspectionContext(level=level, user_input=CASE_R, verified_icd_codes=set(R_CODES),
                             requested_mode="R", **kw)


def _l1(report):
    return report.replace("level=L2", "level=L1")


def _l1_areas(report):
    """The gold report rewritten for an L1 clinician as the template asks."""
    areas = ("#### Areas for the supervisor or a psychologist to assess\n\n"
             "- Repetitive rituals and avoidance that may be obsessive-compulsive in nature\n"
             "- Hair picking: habit or tension relief\n"
             "- Fear of darkness beyond what is usual for his age\n\n")
    return re.sub(r"#### ICD-11 \(WHO\) categories to consider.*?(?=#### Behaviour)", areas, _l1(report),
                  flags=re.S)


class TestConsultationReport(unittest.TestCase):
    def test_gold_standard_report_passes(self):
        rep = inspect(REPORT_R, rctx())
        self.assertTrue(rep.passed, rep.as_dict())

    def test_every_section_is_required(self):
        out = REPORT_R.replace("### 10. Suggested Worksheets & Tools", "### Worksheets")
        self.assertIn("STRUCTURE", codes(inspect(out, rctx())))

    def test_case_snapshot_is_required(self):
        out = REPORT_R.replace("### Case Snapshot", "### Overview")
        self.assertIn("STRUCTURE", codes(inspect(out, rctx())))

    def test_section_titles_are_fixed(self):
        out = REPORT_R.replace("### 4. Therapy Modalities to Consider", "### 4. Treatment options")
        self.assertIn("STRUCTURE", codes(inspect(out, rctx())))

    def test_section_order_is_fixed(self):
        a = REPORT_R.index("### 6. Therapist's Role & Actions")
        b = REPORT_R.index("### 7. Client's Actions and Lifestyle Adjustments")
        c = REPORT_R.index("### 8. Guardian/Parent Guidance")
        out = REPORT_R[:a] + REPORT_R[b:c] + REPORT_R[a:b] + REPORT_R[c:]
        self.assertIn("STRUCTURE", codes(inspect(out, rctx())))

    def test_risk_screening_line_is_required(self):
        out = REPORT_R.replace("**Risk screening:**", "**Notes:**")
        self.assertIn("SAFETY", codes(inspect(out, rctx())))

    def test_confidence_labels_in_sections_1_and_2(self):
        out = REPORT_R.replace("**Confidence:** Moderate — estimate", "Estimate", 1)
        self.assertIn("CONFIDENCE", codes(inspect(out, rctx())))

    def test_week_table_in_section_13(self):
        s13 = REPORT_R.index("### 13. Weekly Therapy Summary")
        s14 = REPORT_R.index("### 14. Helpful Resource Links")
        out = REPORT_R[:s13] + "### 13. Weekly Therapy Summary\nSee Section 9.\n\n" + REPORT_R[s14:]
        self.assertIn("STRUCTURE", codes(inspect(out, rctx())))

    def test_disclaimer_still_required_and_last(self):
        out = REPORT_R.replace("It does not diagnose or replace therapy.", "")
        self.assertIn("DISCLAIMER", codes(inspect(out, rctx())))

    def test_unapproved_link_is_blocked(self):
        out = REPORT_R.replace("https://www.bfrb.org", "https://made-up-ocd-help.example.com")
        self.assertIn("LINK", codes(inspect(out, rctx())))

    def test_requested_report_must_be_mode_r(self):
        out = REPORT_R.replace("mode=R", "mode=A", 1)
        self.assertIn("MODE", codes(inspect(out, rctx())))

    def test_unverified_codes_still_blocked(self):
        rep = inspect(REPORT_R, InspectionContext(level="L2", user_input=CASE_R, requested_mode="R"))
        self.assertIn("ICD_CODE", codes(rep))

    def test_l1_gets_no_codes_in_section_1(self):
        rep = inspect(_l1(REPORT_R), rctx(level="L1"))
        self.assertIn("L1", codes(rep))

    def test_l1_report_following_the_template_passes(self):
        # The L1 shape from the template: the ICD-11 sub-section is replaced by "Areas for the supervisor…".
        rep = inspect(_l1_areas(REPORT_R), rctx(level="L1"))
        self.assertTrue(rep.passed, rep.as_dict())

    def test_l1_keeping_the_icd_subheading_is_blocked(self):
        # Seen in beta (guided report, L1): the ICD-11 sub-heading was kept over a list of areas.
        kept = _l1_areas(REPORT_R).replace("#### Areas for the supervisor or a psychologist to assess",
                                           "#### ICD-11 (WHO) categories to consider")
        self.assertIn("L1", codes(inspect(kept, rctx(level="L1"))))

    def test_l1_section_4_rule_does_not_misfire_on_modalities(self):
        # Mode R's Section 4 is "Therapy Modalities"; the Mode A differential-title rule must not apply.
        rep = inspect(_l1(REPORT_R), rctx(level="L1"))
        self.assertFalse(any("Section 4 must be titled" in f.message for f in rep.blocks), rep.as_dict())

    def test_gate1_still_applies_to_the_case_summary(self):
        risky = CASE_R + " He said he wants to die and has kept pills at home."
        rep = inspect(REPORT_R, InspectionContext(level="L2", user_input=risky, requested_mode="R",
                                                  verified_icd_codes=set(R_CODES)))
        self.assertIn("GATE1", codes(rep))


class TestIntakeOutput(unittest.TestCase):
    GOOD = {"question": "How long has this been going on, and did it start suddenly or gradually?",
            "why": "Duration and onset shape severity and rule-outs.", "options": [],
            "brief_answer": "", "case_summary": "9-year-old boy with rituals and screen overuse.",
            "facts": {"age_gender": "9 years, male"}}

    def test_good_question_passes(self):
        self.assertTrue(inspect_intake(self.GOOD).passed)

    def test_case_type_and_plan_are_checked(self):
        self.assertTrue(inspect_intake(dict(self.GOOD, case_type="Childhood OCD-like rituals",
                                            info_needed=["age_gender", "family_response"])).passed)
        self.assertIn("INTAKE_LENGTH", codes(inspect_intake(dict(self.GOOD, case_type="x" * 120))))
        self.assertIn("INTAKE_LENGTH", codes(inspect_intake(dict(self.GOOD, info_needed=["f"] * 13))))
        self.assertIn("IDENTIFIER", codes(inspect_intake(dict(self.GOOD, case_type="Client on 9876543210"))))
        self.assertIn("ICD_CODE", codes(inspect_intake(dict(self.GOOD, case_type="6B20 OCD"))))

    def test_long_question_blocked(self):
        out = dict(self.GOOD, question="Tell me " + "more about it " * 40 + "?")
        self.assertIn("INTAKE_LENGTH", codes(inspect_intake(out)))

    def test_identifier_in_question_blocked(self):
        out = dict(self.GOOD, question="Can I call the parent on 9876543210 to ask about onset?")
        self.assertIn("IDENTIFIER", codes(inspect_intake(out)))

    def test_identifier_in_a_fact_blocked(self):
        out = dict(self.GOOD, facts={"family": "mother reachable at 9876543210"})
        self.assertIn("IDENTIFIER", codes(inspect_intake(out)))

    def test_no_codes_or_diagnosis_codes_in_brief_answer(self):
        out = dict(self.GOOD, brief_answer="This is 6B20 obsessive-compulsive disorder.")
        self.assertIn("ICD_CODE", codes(inspect_intake(out)))

    def test_no_medication_advice(self):
        out = dict(self.GOOD, brief_answer="You could recommend starting sertraline at a low dose.")
        self.assertIn("MEDICATION", codes(inspect_intake(out)))

    def test_only_register_numbers(self):
        out = dict(self.GOOD, brief_answer="Ask them to call the helpline 1800-123-4567.")
        self.assertIn("CRISIS_NUMBERS", codes(inspect_intake(out)))

    def test_long_brief_answer_blocked(self):
        out = dict(self.GOOD, brief_answer="ERP works. " * 120)
        self.assertIn("INTAKE_LENGTH", codes(inspect_intake(out)))


class TestNiceGuidelineIds(unittest.TestCase):
    def test_nice_guideline_number_is_not_a_diagnosis_code(self):
        # "NICE guideline CG31" looks like an ICD-11 code; it must not need ICD verification.
        out = MODE_A.replace("Panic disorder", "Panic disorder (see NICE guideline CG31)", 1)
        rep = inspect(out, ctx())
        self.assertTrue(rep.passed, rep.as_dict())

    def test_three_digit_nice_guideline_is_not_a_helpline_number(self):
        # Seen live (2026-10-06): "NICE guideline CG113" (GAD and panic) was blocked as an unknown
        # helpline number, because "line" matched inside "guideline" and 113 is three digits.
        out = MODE_A.replace("Panic disorder", "Panic disorder (see NICE guideline CG113)", 1)
        rep = inspect(out, ctx())
        self.assertNotIn("CRISIS_NUMBERS", codes(rep), rep.as_dict())
        self.assertTrue(rep.passed, rep.as_dict())

    def test_short_numbers_after_a_helpline_word_are_still_checked(self):
        # The fix above must not let a made-up short helpline number through.
        for text in ("call helpline 104", "dial 1056", "Tele-MANAS line 104", "helpline no. 155"):
            out = MODE_A.replace("emergency care (112)", f"emergency care (112) or {text}")
            self.assertIn("CRISIS_NUMBERS", codes(inspect(out, ctx())), text)
        out = MODE_A.replace("emergency care (112)", "emergency care (112) or Child Helpline 1098")
        self.assertNotIn("CRISIS_NUMBERS", codes(inspect(out, ctx())))
