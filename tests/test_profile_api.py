"""Registration (POST /v1/profile): the clinician's own name, gender and age are required and checked.
Skipped where the app's dependencies aren't installed."""
import importlib.util
import os
import unittest
from unittest import mock

HAVE_DEPS = all(importlib.util.find_spec(m) for m in ("fastapi", "httpx", "psycopg"))

if HAVE_DEPS:
    os.environ["DEV_MODE"] = "1"
    from fastapi.testclient import TestClient

    from app import main

ME = {"Authorization": "Bearer dev-L2"}
GOOD = {"full_name": "  Dr Sample Clinician ", "gender": "female", "age": 34, "role": "psychologist",
        "registration_body": "RCI", "registration_number": "A12345", "consent_version": "beta-draft-1"}


@unittest.skipUnless(HAVE_DEPS, "fastapi/httpx/psycopg not installed")
class ProfileApiTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(main.app)

    def post(self, body):
        with mock.patch.object(main.db, "upsert_clinician_profile") as save:
            r = self.client.post("/v1/profile", headers=ME, json=body)
        return r, save

    def test_saves_name_gender_and_age(self):
        r, save = self.post(GOOD)
        self.assertEqual(r.status_code, 200, r.text)
        saved = save.call_args.args[1]
        self.assertEqual(saved["full_name"], "Dr Sample Clinician")      # trimmed
        self.assertEqual((saved["gender"], saved["age"]), ("female", 34))

    def test_name_gender_and_age_are_required(self):
        for field in ("full_name", "gender", "age"):
            body = {k: v for k, v in GOOD.items() if k != field}
            r, save = self.post(body)
            self.assertEqual(r.status_code, 422, field)
            save.assert_not_called()

    def test_values_are_checked(self):
        for bad in ({"full_name": " A "}, {"gender": "unknown"}, {"age": 15}, {"age": 120}):
            r, save = self.post({**GOOD, **bad})
            self.assertEqual(r.status_code, 422, bad)
            save.assert_not_called()

    def test_admin_list_shows_them(self):
        main._dev_admin = main.DevAdminStore()
        rows = self.client.get("/v1/admin/clinicians", headers=ME, params={"status": "pending"}).json()["clinicians"]
        self.assertTrue(all({"full_name", "gender", "age_at_registration"} <= set(r) for r in rows))
