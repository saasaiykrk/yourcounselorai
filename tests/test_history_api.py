"""Consult history (clinician's own, read-only) and the admin consult views.

FastAPI TestClient against DEV_MODE's in-memory history. Skipped where the
app's dependencies aren't installed (the stdlib-only safety suite still runs).
"""
import importlib.util
import os
import unittest

HAVE_DEPS = all(importlib.util.find_spec(m) for m in ("fastapi", "httpx", "psycopg"))

if HAVE_DEPS:
    os.environ["DEV_MODE"] = "1"
    from fastapi.testclient import TestClient

    from app import main

ME = {"Authorization": "Bearer dev-L2"}
MINE_A = "aaaaaaaa-0000-4000-8000-000000000001"     # "Sleep and low mood", mode A
MINE_B = "aaaaaaaa-0000-4000-8000-000000000002"     # panic, mode B, 2 turns
OTHERS = "aaaaaaaa-0000-4000-8000-000000000003"     # belongs to another clinician
OTHER_CLINICIAN = "22222222-2222-4222-8222-222222222222"


@unittest.skipUnless(HAVE_DEPS, "fastapi/httpx/psycopg not installed")
class HistoryApiTests(unittest.TestCase):
    def setUp(self):
        main._dev_history = main.DevHistoryStore()
        self.client = TestClient(main.app)

    def tearDown(self):
        main.app.dependency_overrides.clear()

    def ids(self, **params):
        r = self.client.get("/v1/history", headers=ME, params=params)
        self.assertEqual(r.status_code, 200)
        return [c["id"] for c in r.json()["consults"]]

    def test_lists_only_my_consults_newest_first(self):
        self.assertEqual(self.ids(), [MINE_B, MINE_A])
        row = self.client.get("/v1/history", headers=ME).json()["consults"][0]
        self.assertEqual(row["turns"], 2)
        self.assertNotIn("hidden_at", row)

    def test_search_and_mode_filter(self):
        self.assertEqual(self.ids(q="PANIC"), [MINE_B])
        self.assertEqual(self.ids(q="sleep and"), [MINE_A], "matches the label too")
        self.assertEqual(self.ids(mode="A"), [MINE_A])
        self.assertEqual(self.ids(q="nothing like this"), [])
        self.assertEqual(self.client.get("/v1/history?mode=Z", headers=ME).status_code, 422)

    def test_open_a_consult_read_only(self):
        r = self.client.get(f"/v1/history/{MINE_B}", headers=ME).json()
        self.assertEqual(len(r["turns"]), 2)
        self.assertIn("input_deid", r["turns"][0])
        self.assertNotIn("clinician_id", r)

    def test_other_clinicians_consults_are_invisible(self):
        self.assertEqual(self.client.get(f"/v1/history/{OTHERS}", headers=ME).status_code, 404)
        self.assertEqual(self.client.patch(f"/v1/history/{OTHERS}", headers=ME, json={"title": "x"}).status_code, 404)
        self.assertEqual(self.client.delete(f"/v1/history/{OTHERS}", headers=ME).status_code, 404)

    def test_label_set_and_clear(self):
        r = self.client.patch(f"/v1/history/{MINE_B}", headers=ME, json={"title": "  exam panic review "})
        self.assertEqual(r.json()["title"], "exam panic review")
        self.assertEqual(self.ids(q="exam panic"), [MINE_B])
        r = self.client.patch(f"/v1/history/{MINE_B}", headers=ME, json={"title": ""})
        self.assertIsNone(r.json()["title"])

    def test_labels_with_identifiers_or_names_are_refused(self):
        for title, expected in [("call back 9876543210", "PHONE"), ("review for Mrs Sharma", "NAME"),
                                ("follow up with Asha", "POSSIBLE_NAME")]:
            r = self.client.patch(f"/v1/history/{MINE_A}", headers=ME, json={"title": title})
            self.assertEqual(r.status_code, 422, title)
            self.assertEqual(r.json()["detail"]["error"], "identifiers_detected")
            self.assertIn(expected, r.json()["detail"]["types"], title)
            self.assertNotIn(title, r.text, "the label itself is never echoed back")
        self.assertEqual(self.client.patch(f"/v1/history/{MINE_A}", headers=ME, json={"title": "x" * 61}).status_code, 422)

    def test_delete_hides_from_me_but_admin_still_sees_it(self):
        self.assertEqual(self.client.delete(f"/v1/history/{MINE_A}", headers=ME).status_code, 200)
        self.assertEqual(self.ids(), [MINE_B])
        self.assertEqual(self.client.get(f"/v1/history/{MINE_A}", headers=ME).status_code, 404)
        self.assertEqual(self.client.delete(f"/v1/history/{MINE_A}", headers=ME).status_code, 404)
        admin = self.client.get("/v1/admin/clinicians/dev-clinician/consults", headers=ME)
        self.assertEqual(admin.status_code, 422, "clinician id must be a UUID")
        main._dev_history._convs[MINE_A]["clinician_id"] = OTHER_CLINICIAN  # view it as another clinician's
        rows = self.client.get(f"/v1/admin/clinicians/{OTHER_CLINICIAN}/consults", headers=ME).json()["consults"]
        hidden = [r for r in rows if r["id"] == MINE_A]
        self.assertTrue(hidden and hidden[0]["hidden_at"], "admins see hidden consults, marked as hidden")
        self.assertEqual(self.client.get(f"/v1/admin/consults/{MINE_A}", headers=ME).status_code, 200)

    def test_a_new_dev_consult_appears_in_history(self):
        r = self.client.post("/v1/consult", headers=ME, json={
            "text": "45F, grief after loss of spouse, sleep poor. Quick review.", "mode": "B", "deid_attested": True})
        self.assertEqual(r.status_code, 200)
        conv = r.json()["conversation_id"]
        self.assertEqual(self.ids()[0], conv)
        self.assertEqual(self.ids(q="grief"), [conv])

    def test_admin_consult_views_refuse_non_admins(self):
        main.app.dependency_overrides[main.current_user] = lambda: {"id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"}
        original = main.db.get_clinician
        main.db.get_clinician = lambda cid: {"id": cid, "is_admin": False, "level": "L2",
                                             "verification_status": "verified", "consent_version": "x"}
        try:
            for path in (f"/v1/admin/clinicians/{OTHER_CLINICIAN}/consults", f"/v1/admin/consults/{OTHERS}"):
                self.assertEqual(self.client.get(path, headers={"Authorization": "Bearer x"}).status_code, 403, path)
        finally:
            main.db.get_clinician = original

    def test_unverified_clinicians_have_no_history(self):
        main.app.dependency_overrides[main.current_user] = lambda: {"id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"}
        original = main.db.get_clinician
        main.db.get_clinician = lambda cid: {"id": cid, "is_admin": False, "level": None,
                                             "verification_status": "pending", "consent_version": "x"}
        try:
            self.assertEqual(self.client.get("/v1/history", headers={"Authorization": "Bearer x"}).status_code, 403)
        finally:
            main.db.get_clinician = original


if __name__ == "__main__":
    unittest.main()
