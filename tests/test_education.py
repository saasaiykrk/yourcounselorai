"""Education module: the supplied pages are listed and served unchanged apart from the print add-on,
behind links that only a signed-in user gets and that expire."""
import importlib.util
import os
import re
import unittest
from urllib.parse import urlparse

from app import education
from app.education import Signer, load_catalog, render

HAVE = all(importlib.util.find_spec(m) for m in ("fastapi", "httpx"))
if HAVE:
    os.environ["DEV_MODE"] = "1"
    from fastapi.testclient import TestClient

    from app import main

CATALOG = load_catalog()
BY_FILE = {p.file: p for p in CATALOG}


class CatalogTests(unittest.TestCase):
    def test_every_supplied_page_is_a_card_titled_from_its_own_title(self):
        html = sorted(f.name for f in education.WEB.glob("*.html"))
        self.assertEqual(sorted(p.file for p in CATALOG if p.kind != "handout"), html)
        self.assertEqual(len(html), 13)
        for p in CATALOG:
            if p.kind == "handout":
                continue
            src = (education.WEB / p.file).read_text(encoding="utf-8")
            own = re.search(r"<title>(.*?)</title>", src).group(1)
            self.assertIn(p.title, own, p.file)                       # the page's title, brand prefix dropped
            self.assertNotIn("YourCounselor |", p.title)
        self.assertEqual(BY_FILE["YourCounselor_Cognitive_Behavioural_Therapy_CBT.html"].title,
                         "Cognitive Behavioural Therapy (CBT)")
        self.assertEqual(len({p.slug for p in CATALOG}), len(CATALOG), "slugs are unique")
        self.assertEqual(sum(p.reader for p in CATALOG), 10, "ten reader modules")

    def test_the_handout_pdf_is_listed_too(self):
        [pdf] = [p for p in CATALOG if p.kind == "handout"]
        self.assertTrue(pdf.file.endswith(".pdf"))


class RenderTests(unittest.TestCase):
    def rendered(self, file, config=None):
        p = BY_FILE[file]
        src = (education.WEB / p.file).read_text(encoding="utf-8")
        cfg = config if config is not None else ({"viewer": {"name": "A", "email": "a@b.c"}, "links": {}} if p.reader else None)
        return src, render(p, src, {"x.html": "/learn/x?t=1"}, cfg)

    def test_the_original_page_is_kept_whole_and_only_added_to(self):
        for p in CATALOG:
            if p.kind == "handout":
                continue
            src, out = self.rendered(p.file)
            added = [out.count(m) - src.count(m) for m in ("yc-edu-addon", "Print / Save as PDF")]
            self.assertTrue(all(n >= 1 for n in added), p.file)
            # removing what was added gives back the supplied page exactly
            back = re.sub(r"\n<style id=\"yc-edu-addon\">.*?</style>\n", "", out, flags=re.S)
            back = re.sub(r"\n<script id=\"yc-edu-addon-js\">.*?</script>\n", "", back, flags=re.S)
            back = re.sub(r"<script>window.__YC_APP__ = .*?;</script>\n?", "", back, flags=re.S)
            back = back.replace("Object.assign(window.YC_CONFIG, window.__YC_APP__, { onNavigate: function (slug) {"
                                " var u = (window.__YC_APP__.links || {})[slug]; if (u) location.href = u; } });\n", "")
            self.assertEqual(back, src, p.file)

    def test_live_values_never_replace_brand_crisis_or_legal_text(self):
        src, out = self.rendered("YourCounselor_Cognitive_Behavioural_Therapy_CBT.html",
                                 {"viewer": {"name": "Dr </script><b>x", "email": "x@y.z"}, "links": {}})
        self.assertNotIn("</script><b>x", out, "viewer text is escaped inside the script")
        for k in ("crisis", "brand", "disclaimer", "ip_notice"):
            self.assertEqual(out.count(k), src.count(k) + (1 if k == "crisis" else 0) - (1 if k == "crisis" else 0))

    def test_static_pages_get_no_reader_config(self):
        _, out = self.rendered("YourCounselor_Therapy_Comparison_Chart.html")
        self.assertNotIn("__YC_APP__", out)
        self.assertIn("Print / Save as PDF", out)


class SignerTests(unittest.TestCase):
    def test_tokens_name_the_user_expire_and_cannot_be_forged(self):
        now = [1_000_000.0]
        s = Signer(b"secret", hours=2, clock=lambda: now[0])
        t = s.token("user-1")
        self.assertEqual(s.user(t), "user-1")
        self.assertIsNone(Signer(b"other").user(t), "another server key")
        body, sig = t.split(".")
        self.assertIsNone(s.user(body + "." + sig[:-2] + "AA"))
        self.assertIsNone(s.user("garbage"))
        now[0] += 2 * 3600 + 1
        self.assertIsNone(s.user(t), "expired")


@unittest.skipUnless(HAVE, "fastapi not installed")
class ApiTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(main.app)

    def get(self, url):
        u = urlparse(url)
        return self.client.get(u.path + ("?" + u.query if u.query else ""))

    def test_signed_in_users_get_the_cards_and_working_links(self):
        self.assertEqual(self.client.get("/v1/education").status_code, 422, "no sign-in, no list")
        r = self.client.get("/v1/education", headers={"Authorization": "Bearer dev-L1"})
        pages = r.json()["pages"]
        self.assertEqual(len(pages), 14)
        cbt = next(p for p in pages if p["slug"] == "cbt")
        page = self.get(cbt["url"])
        self.assertEqual(page.status_code, 200)
        self.assertIn("Print / Save as PDF", page.text)
        self.assertIn('"name": "Dev clinician"', page.text, "the viewer's name for the watermark")
        self.assertIn("frame-ancestors 'none'", page.headers["content-security-policy"])
        self.assertEqual(page.headers["cache-control"], "private, no-store")
        pdf = self.get(next(p for p in pages if p["kind"] == "handout")["url"])
        self.assertEqual((pdf.status_code, pdf.headers["content-type"]), (200, "application/pdf"))

    def test_pages_need_a_valid_link(self):
        for path in ("/learn/cbt", "/learn/cbt?t=nope", "/learn/file/YourCounselor_Case_History_and_MSE_Practice_Handout.pdf"):
            r = self.client.get(path)
            self.assertEqual(r.status_code, 403, path)
            self.assertIn("This link has expired", r.text)
        self.assertEqual(self.client.get("/learn/no-such-page?t=x").status_code, 404)
        self.assertEqual(self.client.get("/learn/file/../../app/secrets.py?t=x").status_code, 404)

    def test_links_between_pages_keep_the_signature(self):
        r = self.client.get("/v1/education", headers={"Authorization": "Bearer dev-L2"})
        chart = next(p for p in r.json()["pages"] if p["slug"] == "therapy-comparison-chart")
        token = urlparse(chart["url"]).query
        text = self.get(chart["url"]).text
        self.assertIn(f'/learn/cbt?{token}', text, "file-name links are mapped to signed page links")


if __name__ == "__main__":
    unittest.main()
