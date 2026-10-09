"""WHO ICD-11 client against a fake WHO server (httpx MockTransport; no network, no keys).

Why: in real guided reports the model wrote the parent code (6B23, 6A70) while the WHO search only
returned its sub-codes (6B23.0, 6B23.1 …), so the parent was never verified and the safe report was
rejected and written again. The lookup now also returns each sub-code's parent, with WHO's own title."""
import importlib.util
import json
import unittest

HAVE_HTTPX = importlib.util.find_spec("httpx") is not None

if HAVE_HTTPX:
    import httpx

    from app.icd import ICD11Client

R = "2025-01"
TITLES = {"6B23": "Hypochondriasis", "6B23.0": "Hypochondriasis with fair to good insight",
          "6B23.1": "Hypochondriasis with poor to absent insight", "6A70": "Single episode depressive disorder"}


def fake_who(calls):
    def handler(request):
        url = str(request.url)
        calls.append(url)
        if request.url.host == "icdaccessmanagement.who.int":
            return httpx.Response(200, json={"access_token": "t", "expires_in": 3600})
        assert request.headers["Authorization"] == "Bearer t"
        path = request.url.path
        if path.endswith("/mms/search"):
            q = request.url.params["q"]
            hits = [c for c in ("6B23.0", "6B23.1") if q == "health anxiety"]
            return httpx.Response(200, json={"destinationEntities": [
                {"theCode": c, "title": f"<em class='found'>{TITLES[c]}</em>", "id": f"http://id.who.int/x/{c}"}
                for c in hits]})
        if "/codeinfo/" in path:
            code = path.rsplit("/", 1)[1]
            if code not in TITLES:
                return httpx.Response(404, text="not found")
            return httpx.Response(200, json={"code": code, "stemId": f"http://id.who.int/icd/release/11/{R}/mms/{code}-id"})
        if path.endswith("-id"):
            code = path.rsplit("/", 1)[1][:-3]
            return httpx.Response(200, json={"code": code, "title": {"@language": "en", "@value": TITLES[code]}})
        return httpx.Response(404)
    return handler


@unittest.skipUnless(HAVE_HTTPX, "httpx not installed")
class IcdClientTests(unittest.TestCase):
    def client(self, calls):
        return ICD11Client("id", "secret", R, transport=httpx.MockTransport(fake_who(calls)))

    def test_search_also_returns_the_parent_of_each_sub_code_with_its_who_title(self):
        calls = []
        hits = self.client(calls).search("health anxiety")
        self.assertEqual([h["code"] for h in hits], ["6B23.0", "6B23.1", "6B23"])
        self.assertEqual(hits[2], {"code": "6B23", "title": "Hypochondriasis", "release": R})
        self.assertEqual(sum("/codeinfo/6B23" in c for c in calls), 1, "the parent is fetched once")

    def test_titles_have_no_highlight_markup(self):
        hits = self.client([]).search("health anxiety")
        self.assertEqual(hits[0]["title"], "Hypochondriasis with fair to good insight")

    def test_code_info_confirms_a_real_code_and_returns_none_for_one_who_does_not_have(self):
        c = self.client([])
        self.assertEqual(c.code_info("6A70"), {"code": "6A70", "title": "Single episode depressive disorder", "release": R})
        self.assertIsNone(c.code_info("6Z99"))

    def test_https_is_used_for_who_entity_links(self):
        calls = []
        self.client(calls).code_info("6A70")
        self.assertTrue(all(c.startswith("https://") for c in calls), calls)

    def test_a_parent_who_does_not_know_is_not_added(self):
        calls = []
        c = self.client(calls)
        c.code_info = lambda code: None
        self.assertEqual([h["code"] for h in c.search("health anxiety")], ["6B23.0", "6B23.1"])


if __name__ == "__main__":
    unittest.main()
