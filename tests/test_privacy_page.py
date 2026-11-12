"""The public privacy policy at /privacy (stdlib only, except the route check): it is complete (no
[placeholders] left), it explains Google user data with the Limited Use statement Google's OAuth verification
asks for, and the Markdown becomes safe HTML."""
import importlib.util
import re
import unittest

from app import privacy_page


class PrivacyPageTests(unittest.TestCase):
    def setUp(self):
        self.md = privacy_page.POLICY.read_text(encoding="utf-8")
        self.page = privacy_page.render()

    def test_no_blanks_are_left_to_fill(self):
        left = re.findall(r"\[[^\]]+\](?!\()", self.md)        # [x] that is not a [label](link)
        self.assertEqual(left, [], "fill these in app/privacy_policy.md before publishing")

    def test_google_user_data_is_explained_with_limited_use(self):
        self.assertIn("<h2>4. Google user data (Google Calendar and Google Meet)</h2>", self.page)
        self.assertIn("<code>calendar.events</code>", self.page)
        self.assertIn("including the Limited Use requirements", self.page)
        self.assertIn('href="https://developers.google.com/terms/api-services-user-data-policy"', self.page)
        self.assertIn("do not use it for advertising", self.page)
        self.assertIn("revokes our access", self.page)

    def test_google_user_data_is_kept_out_of_other_uses(self):
        # Google's OAuth review: the policy must not read as using Google data beyond the feature itself.
        self.assertIn("Google user data (from connecting Google Calendar) is not used for any purpose in this "
                      "section", self.md)
        self.assertIn("We never use the email address or any other data of a Google account you connect", self.md)
        self.assertIn("We do not use it for marketing", self.md)
        self.assertIn("never any Google user data", self.md)

    def test_markdown_becomes_safe_html(self):
        html = privacy_page.to_html("## A & B\n- **bold** <script>x</script>\n\n| a | b |\n|---|---|\n| 1 | 2 |")
        self.assertIn("<h2>A &amp; B</h2>", html)
        self.assertIn("<li><b>bold</b> &lt;script&gt;x&lt;/script&gt;</li>", html)
        self.assertIn("<th>a</th>", html)
        self.assertIn("<td>2</td>", html)
        self.assertNotIn("|---|", html)
        self.assertNotIn("**", self.page)
        self.assertNotIn("DRAFT", self.page)


@unittest.skipUnless(all(importlib.util.find_spec(m) for m in ("fastapi", "httpx", "psycopg")), "app deps missing")
class PrivacyRouteTests(unittest.TestCase):
    def test_served_publicly(self):
        import os
        os.environ.setdefault("DEV_MODE", "1")
        from fastapi.testclient import TestClient

        from app import main
        r = TestClient(main.app).get("/privacy")
        self.assertEqual(r.status_code, 200)
        self.assertIn("Privacy Policy", r.text)
        self.assertIn("Limited Use", r.text)
