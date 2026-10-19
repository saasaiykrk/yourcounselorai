"""/health: scripts keep the JSON (the deploy smoke test reads it); a browser gets a readable status page."""
import importlib.util
import os
import unittest
from datetime import datetime, timezone

from app import status_page

HAVE = all(importlib.util.find_spec(m) for m in ("fastapi", "httpx"))
if HAVE:
    os.environ["DEV_MODE"] = "1"
    from fastapi.testclient import TestClient

    from app import main

LIVE = {"ok": True, "skill_version": "2.3.0", "prompt_hash": "abc", "model": "gemini-3.8-flash",
        "model_provider": "gemini", "icd_enabled": True, "icd_release": "2025-01", "dev_mode": False,
        "payments_configured": True, "email_configured": True, "database": "db.example:5432/postgres"}


class PageTests(unittest.TestCase):
    def test_who_gets_the_page(self):
        browser = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        self.assertTrue(status_page.wants_html(browser, None))
        for accept in ("*/*", "application/json", ""):
            self.assertFalse(status_page.wants_html(accept, None), accept)
        self.assertFalse(status_page.wants_html(browser, "json"))
        self.assertTrue(status_page.wants_html("*/*", "html"))

    def test_a_healthy_live_server(self):
        page = status_page.render(LIVE, True, datetime(2026, 10, 19, 6, 0, tzinfo=timezone.utc))
        self.assertIn("All systems working", page)
        self.assertIn("19 Oct 2026, 11:30 AM IST", page)
        for text in ("Answering", "gemini-3.8-flash (Google Gemini)", "Version 2.3.0", "release 2025-01", "Live"):
            self.assertIn(text, page)
        self.assertNotIn("db.example", page, "no hosts on the page")
        self.assertNotIn("abc", page, "no prompt hash on the page")

    def test_problems_and_warnings_say_so(self):
        self.assertIn("Something is not working", status_page.render(LIVE, False))
        self.assertIn("Not answering", status_page.render(LIVE, False))
        warn = status_page.render({**LIVE, "icd_enabled": False}, True)
        self.assertIn("Working, with warnings", warn)
        dev = status_page.render({**LIVE, "dev_mode": True}, None)
        self.assertIn("Development (DEV_MODE is on", dev)
        self.assertIn("Not used in development mode", dev)

    def test_values_are_escaped(self):
        page = status_page.render({**LIVE, "model": "<script>x</script>"}, True)
        self.assertNotIn("<script>x</script>", page)


@unittest.skipUnless(HAVE, "fastapi not installed")
class EndpointTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(main.app)

    def test_scripts_keep_the_json(self):
        for path in ("/health", "/healthz"):
            r = self.client.get(path)                  # TestClient, like curl, sends */*
            self.assertEqual(r.headers["content-type"], "application/json", path)
            self.assertTrue(r.json()["ok"])
            self.assertIn("dev_mode", r.json(), "the deploy smoke test reads this")

    def test_a_browser_gets_the_page(self):
        r = self.client.get("/health", headers={"Accept": "text/html,application/xhtml+xml,*/*;q=0.8"})
        self.assertTrue(r.headers["content-type"].startswith("text/html"))
        self.assertIn("Service status", r.text)
        self.assertEqual(r.headers["cache-control"], "no-store")
        r = self.client.get("/health?format=json", headers={"Accept": "text/html"})
        self.assertEqual(r.headers["content-type"], "application/json")
        self.assertEqual(self.client.get("/health?format=xml").status_code, 422)


if __name__ == "__main__":
    unittest.main()
