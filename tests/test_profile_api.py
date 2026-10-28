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

    def post(self, body, status="pending"):
        with mock.patch.object(main.db, "upsert_clinician_profile") as save, \
                mock.patch.object(main.db, "get_clinician", return_value={"verification_status": status}):
            r = self.client.post("/v1/profile", headers=ME, json=body)
        return r, save

    def test_registration_answers_with_the_real_status(self):
        self.assertEqual(self.post(GOOD)[0].json(), {"verification_status": "pending"})
        self.assertEqual(self.post(GOOD, status="verified")[0].json(), {"verification_status": "verified"},
                         "skip-verification switch on: approved at once")

    def test_the_skip_verification_switch_is_admin_only_and_starts_off(self):
        self.assertEqual(self.client.get("/v1/admin/registration-settings", headers=ME).json(), {"auto_approve": False})
        r = self.client.put("/v1/admin/registration-settings", headers=ME, json={"auto_approve": True})
        self.assertEqual(r.json()["auto_approve"], True)
        self.client.put("/v1/admin/registration-settings", headers=ME, json={"auto_approve": False})
        saved = main.db.get_clinician
        main.app.dependency_overrides[main.current_user] = lambda: {"id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}
        main.db.get_clinician = lambda cid: {"id": cid, "is_admin": False}
        try:
            for method in ("get", "put"):
                r = getattr(self.client, method)("/v1/admin/registration-settings", headers=ME,
                                                  **({"json": {"auto_approve": True}} if method == "put" else {}))
                self.assertEqual(r.status_code, 403, method)
        finally:
            main.db.get_clinician = saved
            main.app.dependency_overrides.clear()

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

    def test_mobile_number_is_saved_in_one_form(self):
        for raw, want in (("98765 43210", "+919876543210"), ("+91 98765-43210", "+919876543210"),
                          ("09876543210", "+919876543210"), ("919876543210", "+919876543210"),
                          ("+44 7911 123456", "+447911123456"), ("0044 7911 123456", "+447911123456")):
            r, save = self.post({**GOOD, "mobile": raw})
            self.assertEqual(r.status_code, 200, (raw, r.text))
            self.assertEqual(save.call_args.args[1]["mobile"], want, raw)

    def test_a_wrong_mobile_number_is_refused(self):
        for bad in ("12345", "5876543210", "+91 12345 67890", "98765 4321a", "+1", "call me", "+91 98765 432100"):
            r, save = self.post({**GOOD, "mobile": bad})
            self.assertEqual(r.status_code, 422, bad)
            self.assertIn("mobile", r.text, bad)
            save.assert_not_called()

    def test_older_apps_without_a_mobile_number_can_still_register(self):
        r, save = self.post(GOOD)
        self.assertEqual(r.status_code, 200, r.text)
        self.assertIsNone(save.call_args.args[1]["mobile"])

    def test_editing_can_change_the_mobile_number_and_older_apps_leave_it(self):
        saved = dict(main._DEV_CLINICIAN)
        try:
            main._DEV_CLINICIAN.update(full_name="Dr Old", gender="female", age_at_registration=34, mobile="+919876543210",
                                       role="psychologist", registration_body="RCI", registration_number="A12345")
            base = {k: v for k, v in GOOD.items() if k != "consent_version"}
            self.assertEqual(self.edit(base).status_code, 200)
            self.assertEqual(main._DEV_CLINICIAN["mobile"], "+919876543210", "not sent: unchanged")
            r = self.edit({**base, "mobile": "91234 56789"})
            self.assertEqual(r.json(), {"verification_status": "verified", "reverify": False})
            self.assertEqual(self.client.get("/v1/me", headers=ME).json()["mobile"], "+919123456789")
            self.assertEqual(self.edit({**base, "mobile": "123"}).status_code, 422)
        finally:
            main._DEV_CLINICIAN.clear()
            main._DEV_CLINICIAN.update(saved)

    # --- editing (PATCH /v1/profile) ------------------------------------------------
    def edit(self, body):
        return self.client.patch("/v1/profile", headers=ME, json=body)

    def test_editing_name_gender_age_keeps_the_verification(self):
        saved = dict(main._DEV_CLINICIAN)
        try:
            main._DEV_CLINICIAN.update(full_name="Dr Old", gender="female", age_at_registration=34,
                                       role="psychologist", registration_body="RCI", registration_number="A12345")
            r = self.edit({**{k: v for k, v in GOOD.items() if k != "consent_version"},
                           "full_name": "Dr New Name", "age": 35})
            self.assertEqual(r.status_code, 200, r.text)
            self.assertEqual(r.json(), {"verification_status": "verified", "reverify": False})
            me = self.client.get("/v1/me", headers=ME).json()
            self.assertEqual((me["full_name"], me["age_at_registration"], me["level"]), ("Dr New Name", 35, "L2"))
        finally:
            main._DEV_CLINICIAN.clear()
            main._DEV_CLINICIAN.update(saved)

    def test_changing_registration_or_role_sends_it_back_for_verification(self):
        saved = dict(main._DEV_CLINICIAN)
        try:
            for change in ({"registration_number": "B99999"}, {"registration_body": "NMC"}, {"role": "psychiatrist"}):
                main._DEV_CLINICIAN.clear()
                main._DEV_CLINICIAN.update(saved, full_name="Dr Old", gender="female", age_at_registration=34,
                                           role="psychologist", registration_body="RCI", registration_number="A12345")
                body = {**{k: v for k, v in GOOD.items() if k != "consent_version"}, **change}
                r = self.edit(body)
                self.assertEqual(r.json(), {"verification_status": "pending", "reverify": True}, change)
                self.assertIsNone(main._DEV_CLINICIAN["level"], "the level never survives a registration change")
        finally:
            main._DEV_CLINICIAN.clear()
            main._DEV_CLINICIAN.update(saved)

    def test_edit_is_checked_like_registration_and_cannot_set_a_level(self):
        base = {k: v for k, v in GOOD.items() if k != "consent_version"}
        for bad in ({"full_name": " A "}, {"gender": "x"}, {"age": 15}, {"role": "admin"}):
            self.assertEqual(self.edit({**base, **bad}).status_code, 422, bad)
        self.assertEqual(self.edit({**base, "level": "L3"}).status_code, 422)
        self.assertEqual(self.edit({**base, "verification_status": "verified"}).status_code, 422)

    def test_admin_list_shows_them(self):
        main._dev_admin = main.DevAdminStore()
        rows = self.client.get("/v1/admin/clinicians", headers=ME, params={"status": "pending"}).json()["clinicians"]
        self.assertTrue(all({"full_name", "gender", "age_at_registration"} <= set(r) for r in rows))
