import json
import pathlib
import unittest

from app.deid import clean

VECTORS = json.loads((pathlib.Path(__file__).parent.parent / "fixtures" / "deid_vectors.json").read_text())


class TestDeidVectors(unittest.TestCase):
    def test_must_redact(self):
        for v in VECTORS["must_redact"]:
            with self.subTest(v["id"]):
                r = clean(v["text"])
                for t in v["types"]:
                    self.assertIn(f"[{t}]", r.text, f"{v['id']}: expected [{t}] in {r.text!r}")
                for g in v["gone"]:
                    self.assertNotIn(g, r.text, f"{v['id']}: {g!r} survived")
                self.assertFalse(r.is_clean)

    def test_must_keep(self):
        for v in VECTORS["must_keep"]:
            with self.subTest(v["id"]):
                r = clean(v["text"])
                self.assertEqual(r.text, v["text"], f"{v['id']}: over-redacted -> {r.text!r}")
                self.assertTrue(r.is_clean)
                if v.get("no_name_warnings"):
                    self.assertEqual(r.warnings, [], f"{v['id']}: everyday words asked about as names")

    def test_possible_name_warning_is_not_a_redaction(self):
        r = clean("Client came with Priya, her cousin, to the session.")
        self.assertIn("Priya", r.warnings)
        self.assertTrue(r.is_clean)

    def test_real_names_are_still_asked_about_next_to_everyday_words(self):
        r = clean("28F, Married to Rohan for 2 years, Video calls with Sneha daily, Engaged to Arjun before.")
        self.assertEqual(r.warnings, ["Rohan", "Sneha", "Arjun"])
        # words that are also given names stay flagged
        self.assertEqual(clean("Came with Asha, then Hope and Joy, and Kiran.").warnings, ["Asha", "Hope", "Joy", "Kiran"])

    def test_counts_only_types(self):
        r = clean("Call 9876543210 or mail a.b@c.com")
        self.assertEqual(r.counts, {"PHONE": 1, "EMAIL": 1})


if __name__ == "__main__":
    unittest.main()
