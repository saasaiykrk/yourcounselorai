import json
import pathlib
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
