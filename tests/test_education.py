"""Education module: the supplied pages are listed and served unchanged apart from the print add-on,
behind links that only a signed-in user gets and that expire."""
import importlib.util
import os
import re
import unittest
from datetime import datetime, timezone
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

    def test_every_page_has_a_known_section(self):
        self.assertTrue(all(p.section in education.SECTIONS for p in CATALOG))
        self.assertEqual(set(education.SECTION_OF) - {p.slug for p in CATALOG}, set(), "no stale slugs")
        self.assertEqual(BY_FILE["YourCounselor_Cognitive_Behavioural_Therapy_CBT.html"].section, "therapies")
        [pdf] = [p for p in CATALOG if p.kind == "handout"]
        self.assertEqual(pdf.section, "handouts")
        unknown = education.Page("new-page", "x.html", "X", "", "reference", False)
        self.assertEqual(unknown.section, "others", "a new page lands in Others until it is placed")

    def test_the_handout_pdf_is_listed_too(self):
        [pdf] = [p for p in CATALOG if p.kind == "handout"]
        self.assertTrue(pdf.file.endswith(".pdf"))


class RenderTests(unittest.TestCase):
    def rendered(self, file, config=None, can_print=True):
        p = BY_FILE[file]
        src = (education.WEB / p.file).read_text(encoding="utf-8")
        cfg = config if config is not None else ({"viewer": {"name": "A", "email": "a@b.c"}, "links": {}} if p.reader else None)
        return src, render(p, src, {"x.html": "/learn/x?t=1"}, cfg, can_print)

    def test_the_original_page_is_kept_whole_and_only_added_to(self):
        for p, can_print in [(p, c) for p in CATALOG if p.kind != "handout" for c in (True, False)]:
            src, out = self.rendered(p.file, can_print=can_print)
            self.assertGreaterEqual(out.count("yc-edu-addon") - src.count("yc-edu-addon"), 1, p.file)
            # removing what was added gives back the supplied page exactly
            back = re.sub(r"\n<style id=\"yc-edu-addon\">.*?</style>\n", "", out, flags=re.S)
            back = re.sub(r"\n<script id=\"yc-edu-addon-js\">.*?</script>\n", "", back, flags=re.S)
            back = re.sub(r"<script>window.__YC_APP__ = .*?;</script>\n?", "", back, flags=re.S)
            back = back.replace("Object.assign(window.YC_CONFIG, window.__YC_APP__, { onNavigate: function (slug) {"
                                " var u = (window.__YC_APP__.links || {})[slug]; if (u) location.href = u; } });\n", "")
            self.assertEqual(back, src, p.file)

    def test_the_button_shows_for_everyone_and_prints_only_when_unlocked(self):
        for p in CATALOG:
            if p.kind == "handout":
                continue
            src, paid = self.rendered(p.file, can_print=True)
            _, free = self.rendered(p.file, can_print=False)
            for out in (paid, free):
                self.assertGreater(out.count("Print / Save as PDF"), src.count("Print / Save as PDF"), p.file)
            self.assertIn("var CAN_PRINT = true;", paid)
            self.assertIn("app.postMessage(snapshot())", paid, "inside the app, the app prints")
            self.assertNotIn("body *{display:none!important}", paid, "unlocked: printing is not blocked")
            # locked: the button asks the app to offer a single print; printing itself stays blocked
            self.assertIn("var CAN_PRINT = false;", free)
            self.assertIn('app.postMessage("yc:buy")', free)
            self.assertNotIn("function snapshot", free, "nothing to print with is sent")
            self.assertIn(education.LOCKED_NOTE, free)
            self.assertIn("body *{display:none!important}", free)

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


class ServiceTests(unittest.TestCase):
    def test_access_is_per_page_and_fails_closed(self):
        A = education.PrintAccess
        svc = lambda f: education.EducationService(Signer(b"k"), lambda u: None, CATALOG, access=f)  # noqa: E731
        everything = svc(lambda u: A(everything=True)).print_access("sub")
        self.assertTrue(everything.allows("cbt") and everything.allows("dbt"))
        one = svc(lambda u: A(pages={"cbt": "later"})).print_access("pass")
        self.assertTrue(one.allows("cbt"))
        self.assertFalse(one.allows("dbt"), "a single print is for its page only")
        self.assertFalse(education.EducationService(Signer(b"k"), lambda u: None, CATALOG).print_access("x").allows("cbt"))

        def broken(u):
            raise RuntimeError("database down")
        self.assertEqual(svc(broken).print_access("sub"), A(), "an error never unlocks printing")
        self.assertEqual(svc(lambda u: True).print_access("sub"), A(), "only a PrintAccess counts")


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
        self.access = education.PrintAccess(everything=True)
        orig = main.EDUCATION.access
        main.EDUCATION.access = lambda u: self.access
        self.addCleanup(setattr, main.EDUCATION, "access", orig)

    def get(self, url):
        u = urlparse(url)
        return self.client.get(u.path + ("?" + u.query if u.query else ""))

    def test_signed_in_users_get_the_cards_and_working_links(self):
        self.assertEqual(self.client.get("/v1/education").status_code, 422, "no sign-in, no list")
        r = self.client.get("/v1/education", headers={"Authorization": "Bearer dev-L1"})
        pages = r.json()["pages"]
        self.assertTrue(r.json()["can_print"])
        self.assertEqual(len(pages), 14)
        cbt = next(p for p in pages if p["slug"] == "cbt")
        self.assertEqual(cbt["section"], "therapies")
        page = self.get(cbt["url"])
        self.assertEqual(page.status_code, 200)
        self.assertIn("Print / Save as PDF", page.text)
        self.assertIn('"subscriptionActive": true', page.text)
        self.assertIn('"name": "Dev clinician"', page.text, "the viewer's name for the watermark")
        self.assertIn("frame-ancestors 'none'", page.headers["content-security-policy"])
        self.assertEqual(page.headers["cache-control"], "private, no-store")
        pdf = self.get(next(p for p in pages if p["kind"] == "handout")["url"])
        self.assertEqual((pdf.status_code, pdf.headers["content-type"]), (200, "application/pdf"))

    def test_pricing_off_in_dev_means_everyone_prints(self):
        main.EDUCATION.access = main._print_access
        r = self.client.get("/v1/education", headers={"Authorization": "Bearer dev-L1"})
        self.assertTrue(r.json()["can_print"])
        self.assertIsNone(r.json()["print_offer"])

    def test_locked_pages_offer_a_single_print_and_a_pass_unlocks_its_page_only(self):
        offer = {"price": 4900, "currency": "INR", "hours": 24, "name": "Print one page"}
        self.access = education.PrintAccess(pages={"cbt": datetime(2030, 1, 1, tzinfo=timezone.utc)}, offer=offer)
        r = self.client.get("/v1/education", headers={"Authorization": "Bearer dev-L1"}).json()
        self.assertFalse(r["can_print"])
        self.assertEqual(r["print_offer"], offer)
        pages = {p["slug"]: p for p in r["pages"]}
        self.assertEqual((pages["cbt"]["can_print"], pages["cbt"]["print_until"]), (True, "2030-01-01T00:00:00+00:00"))
        self.assertEqual((pages["dbt"]["can_print"], pages["dbt"]["print_until"]), (False, None))
        cbt, dbt = self.get(pages["cbt"]["url"]).text, self.get(pages["dbt"]["url"]).text
        self.assertIn("var CAN_PRINT = true;", cbt)
        self.assertIn('"subscriptionActive": true', cbt)
        self.assertEqual(self.get(pages["dbt"]["url"]).status_code, 200, "the page itself stays free")
        self.assertIn("var CAN_PRINT = false;", dbt)
        self.assertIn("Print / Save as PDF", dbt, "the button shows; locked, it offers the purchase")
        self.assertIn('"subscriptionActive": false', dbt, "the module's own handout print is locked too")

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
