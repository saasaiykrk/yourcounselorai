"""Regression tests built from evals/vignettes.json (no model needed).

Every vignette must survive the cleaner untouched, and the inspector's risk
backstop must fire on exactly the Gate 1 vignettes. When beta finds a missed
risk phrasing, add a vignette with expect_gate1=true — this test then fails
until the pattern is added."""
import json
import pathlib
import unittest

from app.deid import clean
from app.inspector import MINOR_RE, RISK_INPUT_RE, SAFETY_MANAGED_RE

V = json.loads((pathlib.Path(__file__).parent.parent / "evals" / "vignettes.json").read_text())["evals"]


class TestVignettes(unittest.TestCase):
    def test_twenty_cases_with_assertions(self):
        self.assertEqual(len(V), 20)
        self.assertEqual(len({v["id"] for v in V}), 20)
        for v in V:
            self.assertGreaterEqual(len(v["assertions"]), 4, v["id"])

    def test_prompts_are_already_deidentified(self):
        for v in V:
            with self.subTest(v["id"]):
                self.assertTrue(clean(v["prompt"]).is_clean)

    def test_risk_backstop_matches_gate1_cases_only(self):
        for v in V:
            with self.subTest(v["id"]):
                forced = bool(RISK_INPUT_RE.search(v["prompt"])) and not SAFETY_MANAGED_RE.search(v["prompt"])
                self.assertEqual(forced, v["expect_gate1"])

    def test_minor_detection(self):
        minors = {v["id"] for v in V if MINOR_RE.search(v["prompt"])}
        self.assertTrue({"V04", "V15", "V16"} <= minors)
        self.assertNotIn("V05", minors)   # "drinker for 15 years" is not an age


if __name__ == "__main__":
    unittest.main()
