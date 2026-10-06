import pathlib
import unittest

from app.icd import OfflineICD11
from app.pipeline import FALLBACK, DeidRejected, ModelResult, Pipeline
from app.prompt import load_skill

ROOT = pathlib.Path(__file__).parent.parent
GOOD = (ROOT / "fixtures" / "golden" / "mode_a_panic.md").read_text()
BAD = GOOD.replace("It does not diagnose or replace therapy.", "")
PROMPT = "have one pateint with anxiety episodes, palpatation increase even on turning side. feels like dieng. age 44. full case plan please"


class FakeModel:
    """Returns scripted replies; optionally calls a tool first."""
    def __init__(self, replies, tool_calls=()):
        self.replies, self.tool_calls, self.seen = list(replies), list(tool_calls), []

    def run(self, system, messages, tools, tool_handler):
        self.seen.append(messages)
        for name, args in self.tool_calls:
            tool_handler(name, args)
        return ModelResult(text=self.replies.pop(0), model="fake")


class FakeICD:
    release = "test"
    def search(self, q, limit=8):
        return [{"code": "6B01", "title": "Panic disorder", "release": "test"}]


class TestPipeline(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.skill = load_skill(str(ROOT / "skill" / "clinical-assist"))

    def test_delivers_good_reply_first_time(self):
        r = Pipeline(self.skill, FakeModel([GOOD]), OfflineICD11()).run(PROMPT, "L2")
        self.assertEqual((r.status, r.attempts), ("delivered", 1))
        self.assertFalse(r.display_text.startswith("<!--"))
        self.assertEqual(r.skill_version, "2.2.1")

    def test_regenerates_once_then_delivers(self):
        m = FakeModel([BAD, GOOD])
        r = Pipeline(self.skill, m, OfflineICD11()).run(PROMPT, "L2")
        self.assertEqual((r.status, r.attempts), ("delivered", 2))
        self.assertIn("DISCLAIMER", m.seen[1][-1]["content"])  # failure list sent back

    def test_blocks_after_two_failures(self):
        r = Pipeline(self.skill, FakeModel([BAD, BAD]), OfflineICD11()).run(PROMPT, "L2")
        self.assertEqual(r.status, "blocked")
        self.assertEqual(r.display_text, FALLBACK)
        self.assertIn("14416", r.display_text)

    def test_empty_reply_is_retried_without_an_empty_assistant_turn(self):
        # A declined (refusal) reply comes back empty; the API rejects empty assistant turns.
        m = FakeModel(["", GOOD])
        r = Pipeline(self.skill, m, OfflineICD11()).run(PROMPT, "L2")
        self.assertEqual((r.status, r.attempts), ("delivered", 2))
        self.assertNotIn({"role": "assistant", "content": ""}, m.seen[1])

    def test_rejects_identifiers_server_side(self):
        with self.assertRaises(DeidRejected) as cm:
            Pipeline(self.skill, FakeModel([GOOD]), OfflineICD11()).run(PROMPT + " ph 9876543210", "L2")
        self.assertEqual(cm.exception.counts, {"PHONE": 1})

    def test_icd_codes_from_tool_are_verified(self):
        out = GOOD.replace("ICD-11 panic disorder, code to confirm", "ICD-11 panic disorder 6B01")
        m = FakeModel([out], tool_calls=[("icd11_lookup", {"query": "panic disorder"})])
        r = Pipeline(self.skill, m, FakeICD()).run(PROMPT, "L2")
        self.assertEqual(r.status, "delivered", r.reports)
        self.assertEqual(r.verified_icd_codes, ["6B01"])

    def test_header_carries_verified_level(self):
        m = FakeModel([GOOD])
        Pipeline(self.skill, m, OfflineICD11()).run(PROMPT, "L2", requested_mode="A")
        self.assertIn("Clinician level: L2 (verified)", m.seen[0][-1]["content"])


if __name__ == "__main__":
    unittest.main()
