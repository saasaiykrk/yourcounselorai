"""POST /v1/account/delete and the public /delete-account page (the web link Google Play asks for)."""
import importlib.util
import os
import unittest
from unittest import mock

from app import account_page

HAVE = all(importlib.util.find_spec(m) for m in ("fastapi", "httpx"))
if HAVE:
    os.environ["DEV_MODE"] = "1"
    from fastapi.testclient import TestClient

    from app import main


class PageTests(unittest.TestCase):
    def test_the_page_says_how_and_what(self):
        page = account_page.render()
        for text in ("Account</b> → <b>Delete account", "DELETE", "saas.ai.yk@gmail.com", "What is deleted",
                     "Payment records", "12-month", "can't be undone"):
            self.assertIn(text, page)

    def test_the_email_is_escaped(self):
        self.assertNotIn("<x>", account_page.render("<x>@example.com"))


@unittest.skipUnless(HAVE, "fastapi not installed")
class EndpointTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(main.app)
        self.dev = {"Authorization": "Bearer dev-L2"}

    def tearDown(self):
        main.app.dependency_overrides.clear()

    def test_typing_delete_is_required(self):
        for body in ({}, {"confirm": "delete"}, {"confirm": "DELETE ME"}):
            self.assertEqual(self.client.post("/v1/account/delete", json=body, headers=self.dev).status_code, 422,
                             body)
        self.assertEqual(self.client.post("/v1/account/delete", json={"confirm": "DELETE"}).status_code, 422,
                         "no sign-in, no deletion")

    def test_dev_mode_deletes_nothing(self):
        with mock.patch.object(main.db, "delete_account") as d:
            r = self.client.post("/v1/account/delete", json={"confirm": "DELETE"}, headers=self.dev)
        self.assertEqual(r.json(), {"deleted": True})
        d.assert_not_called()

    def test_a_signed_in_clinician_deletes_only_their_own_account(self):
        main.app.dependency_overrides[main.current_user] = lambda: {"id": "11111111-1111-1111-1111-111111111111"}
        with mock.patch.object(main.db, "delete_account", return_value="deleted") as d:
            r = self.client.post("/v1/account/delete", json={"confirm": "DELETE", "id": "someone-else"},
                                 headers={"Authorization": "Bearer x"})
        self.assertEqual(r.status_code, 200)
        d.assert_called_once_with("11111111-1111-1111-1111-111111111111")

    def test_an_admin_is_told_why_not(self):
        main.app.dependency_overrides[main.current_user] = lambda: {"id": "admin-id"}
        with mock.patch.object(main.db, "delete_account", return_value="admin"):
            r = self.client.post("/v1/account/delete", json={"confirm": "DELETE"}, headers={"Authorization": "Bearer x"})
        self.assertEqual(r.status_code, 409)
        self.assertEqual(r.json()["detail"]["error"], "admin_account")

    def test_the_public_page(self):
        r = self.client.get("/delete-account")
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.headers["content-type"].startswith("text/html"))
        self.assertIn("Delete your account", r.text)


if __name__ == "__main__":
    unittest.main()
