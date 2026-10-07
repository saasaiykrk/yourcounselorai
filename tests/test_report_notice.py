"""The safety notice printed on every downloaded report (web admin PDF).

Its crisis numbers must be exactly the register's, and its wording must match
the app's own PDF (mobile/lib/core/content/safety_content.dart), so the two
downloads never disagree."""
import pathlib
import re
import unittest

from app.inspector import ALLOWED_CRISIS_NUMBERS, DISCLAIMER
from app.report_notice import CRISIS_LINES, PRECAUTIONS, VERIFIED_NOTE, report_notice

ROOT = pathlib.Path(__file__).parent.parent
DART = (ROOT / "mobile" / "lib" / "core" / "content" / "safety_content.dart").read_text()


def _dart_list(block: str) -> list[str]:
    """Items of a Dart list of strings; adjacent literals in one item are joined."""
    items, current = [], []
    for m in re.finditer(r"'((?:[^'\\]|\\.)*)'|(,)", block):
        if m.group(2):
            items.append("".join(current))
            current = []
        else:
            current.append(m.group(1).replace("\\'", "'"))
    if current:
        items.append("".join(current))
    return [i for i in items if i]


class TestReportNotice(unittest.TestCase):
    def test_crisis_numbers_are_exactly_the_register(self):
        register = (ROOT / "skill/clinical-assist/references/crisis-resources.md").read_text()
        current = register.split("## Current entries")[1].split("## Output rule")[0]
        listed = set(re.findall(r"\*\*([\d-]+)\*\*", current))
        self.assertEqual({n for _, n in CRISIS_LINES}, listed)
        self.assertTrue({n.replace("-", "") for _, n in CRISIS_LINES} <= ALLOWED_CRISIS_NUMBERS)

    def test_matches_the_app_pdf_wording(self):
        block = re.search(r"const kPdfPrecautions = <String>\[(.*?)\n\];", DART, re.S).group(1)
        self.assertEqual(list(PRECAUTIONS), _dart_list(block))
        lines = re.findall(r"CrisisLine\('([^']+)', '([^']+)'\)", DART)
        self.assertEqual(list(CRISIS_LINES), lines)
        self.assertIn(f"'{VERIFIED_NOTE}'", DART)

    def test_payload(self):
        n = report_notice()
        self.assertEqual(n["disclaimer"], DISCLAIMER)
        self.assertEqual(n["precautions"], list(PRECAUTIONS))
        self.assertIn("Tele-MANAS 14416", n["crisis_line"])
        self.assertIn(VERIFIED_NOTE, n["crisis_line"])
        self.assertIn("De-identified", n["footer"])


if __name__ == "__main__":
    unittest.main()
