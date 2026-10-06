"""Admin API and web admin page (FastAPI TestClient, DEV_MODE sample data).

Needs the app's dependencies (fastapi, httpx); skipped where they aren't
installed so the stdlib-only safety suite still runs anywhere.
"""
import importlib.util
import os
import unittest

HAVE_DEPS = all(importlib.util.find_spec(m) for m in ("fastapi", "httpx", "psycopg"))

if HAVE_DEPS:
    os.environ["DEV_MODE"] = "1"
    from fastapi.testclient import TestClient

    from app import main

ADMIN = {"Authorization": "Bearer dev-L3"}
PENDING_PSYCH = "22222222-2222-4222-8222-222222222222"
PENDING_TRAINEE = "11111111-1111-4111-8111-111111111111"
BLOCKED_INCIDENT = "33333333-3333-4333-8333-333333333333"


@unittest.skipUnless(HAVE_DEPS, "fastapi/httpx/psycopg not installed")
class AdminApiTests(unittest.TestCase):
    def setUp(self):
        main._dev_admin = main.DevAdminStore()   # fresh sample data per test
        self.client = TestClient(main.app)

    def tearDown(self):
        main.app.dependency_overrides.clear()

    def test_approve_moves_registration_from_pending_to_verified(self):
        pending = self.client.get("/v1/admin/clinicians", headers=ADMIN).json()["clinicians"]
        self.assertEqual({c["id"] for c in pending}, {PENDING_PSYCH, PENDING_TRAINEE})
        r = self.client.patch(f"/v1/admin/clinicians/{PENDING_PSYCH}", headers=ADMIN,
                              json={"verification_status": "verified", "level": "L2",
                                    "evidence_note": "RCI register, 2026-10-03"})
        self.assertEqual(r.status_code, 200)
        verified = self.client.get("/v1/admin/clinicians?status=verified", headers=ADMIN).json()["clinicians"]
        self.assertEqual([(c["id"], c["level"]) for c in verified], [(PENDING_PSYCH, "L2")])

    def test_verifying_needs_a_level_and_a_note(self):
        r = self.client.patch(f"/v1/admin/clinicians/{PENDING_PSYCH}", headers=ADMIN,
                              json={"verification_status": "verified", "evidence_note": "RCI register"})
        self.assertEqual(r.status_code, 422)
        r = self.client.patch(f"/v1/admin/clinicians/{PENDING_PSYCH}", headers=ADMIN,
                              json={"verification_status": "verified", "level": "L2", "evidence_note": ""})
        self.assertEqual(r.status_code, 422)

    def test_reject_needs_no_level_and_clears_it(self):
        r = self.client.patch(f"/v1/admin/clinicians/{PENDING_TRAINEE}", headers=ADMIN,
                              json={"verification_status": "rejected", "evidence_note": "Not on the register"})
        self.assertEqual(r.status_code, 200)
        rejected = self.client.get("/v1/admin/clinicians?status=rejected", headers=ADMIN).json()["clinicians"]
        self.assertEqual(rejected[0]["level"], None)

    def test_unknown_clinician_is_404_and_admins_cannot_verify_themselves(self):
        r = self.client.patch("/v1/admin/clinicians/99999999-9999-4999-8999-999999999999", headers=ADMIN,
                              json={"verification_status": "rejected", "evidence_note": "n/a"})
        self.assertEqual(r.status_code, 404)
        main.app.dependency_overrides[main.admin] = lambda: {"id": PENDING_PSYCH, "is_admin": True}
        r = self.client.patch(f"/v1/admin/clinicians/{PENDING_PSYCH}", headers=ADMIN,
                              json={"verification_status": "verified", "level": "L3", "evidence_note": "self"})
        self.assertEqual(r.status_code, 409)

    def test_incident_list_hides_case_text_detail_shows_it_and_triage_saves(self):
        rows = self.client.get("/v1/admin/incidents?status=open", headers=ADMIN).json()["incidents"]
        self.assertEqual(len(rows), 2)
        self.assertNotIn("input_deid", rows[0])
        detail = self.client.get(f"/v1/admin/incidents/{BLOCKED_INCIDENT}", headers=ADMIN).json()
        self.assertIn("input_deid", detail)
        self.assertIn("inspector_reports", detail)
        r = self.client.patch(f"/v1/admin/incidents/{BLOCKED_INCIDENT}", headers=ADMIN,
                              json={"status": "triaged", "reviewer_note": "Disclaimer regression, see evals"})
        self.assertEqual(r.status_code, 200)
        open_now = self.client.get("/v1/admin/incidents?status=open", headers=ADMIN).json()["incidents"]
        self.assertEqual(len(open_now), 1)
        bad = self.client.patch(f"/v1/admin/incidents/{BLOCKED_INCIDENT}", headers=ADMIN, json={"status": "deleted"})
        self.assertEqual(bad.status_code, 422)

    def test_held_back_text_is_a_separate_request(self):
        # The incident detail never carries the held-back text; it comes only from its own (audited) request.
        detail = self.client.get(f"/v1/admin/incidents/{BLOCKED_INCIDENT}", headers=ADMIN).json()
        self.assertNotIn("held_back", detail)
        r = self.client.get(f"/v1/admin/incidents/{BLOCKED_INCIDENT}/held-back", headers=ADMIN)
        self.assertEqual(r.status_code, 200)
        attempts = r.json()["attempts"]
        self.assertEqual([a["attempt"] for a in attempts], [1, 2])
        self.assertTrue(all(a["text"].startswith("<!--yc") for a in attempts))

    def test_held_back_text_is_empty_for_a_delivered_reply(self):
        r = self.client.get("/v1/admin/incidents/55555555-5555-4555-8555-555555555555/held-back", headers=ADMIN)
        self.assertEqual(r.json(), {"attempts": []})
        r = self.client.get("/v1/admin/incidents/99999999-9999-4999-8999-999999999999/held-back", headers=ADMIN)
        self.assertEqual(r.status_code, 404)

    def test_non_admin_is_refused_everywhere(self):
        main.app.dependency_overrides[main.current_user] = lambda: {"id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}
        original = main.db.get_clinician
        main.db.get_clinician = lambda cid: {"id": cid, "is_admin": False, "level": "L2",
                                             "verification_status": "verified"}
        try:
            for method, path, body in [
                ("get", "/v1/admin/clinicians", None),
                ("patch", f"/v1/admin/clinicians/{PENDING_PSYCH}",
                 {"verification_status": "verified", "level": "L3", "evidence_note": "x" * 5}),
                ("get", "/v1/admin/incidents", None),
                ("get", f"/v1/admin/incidents/{BLOCKED_INCIDENT}", None),
                ("patch", f"/v1/admin/incidents/{BLOCKED_INCIDENT}", {"status": "fixed"}),
                ("get", f"/v1/admin/incidents/{BLOCKED_INCIDENT}/held-back", None),
            ]:
                kwargs = {"json": body} if body is not None else {}
                r = getattr(self.client, method)(path, headers={"Authorization": "Bearer x"}, **kwargs)
                self.assertEqual(r.status_code, 403, path)
        finally:
            main.db.get_clinician = original

    def test_admin_requires_sign_in(self):
        self.assertEqual(self.client.get("/v1/admin/clinicians").status_code, 422)  # no Authorization header

    def test_web_admin_page_is_locked_down(self):
        for path, media in [("/admin", "text/html"), ("/admin/admin.js", "text/javascript"),
                            ("/admin/admin.css", "text/css")]:
            r = self.client.get(path)
            self.assertEqual(r.status_code, 200, path)
            self.assertTrue(r.headers["content-type"].startswith(media), path)
            csp = r.headers["content-security-policy"]
            self.assertIn("script-src 'self'", csp)
            self.assertNotIn("unsafe-inline", csp)
            self.assertIn("frame-ancestors 'none'", csp)
            self.assertEqual(r.headers["cache-control"], "no-store")
        self.assertEqual(self.client.get("/admin/secrets.py").status_code, 404)
        self.assertEqual(self.client.get("/admin/..%2Fmain.py").status_code, 404)
        html = self.client.get("/admin").text
        self.assertNotIn("<script>", html, "no inline scripts")
        self.assertNotIn("http", html.replace("http-equiv", ""), "no external resources")

    def test_admin_page_uses_text_not_html_for_data(self):
        js = self.client.get("/admin/admin.js").text
        self.assertNotIn("innerHTML", js)
        self.assertNotIn("eval(", js)
        self.assertIn("create_user: false", js)

    def test_admin_config_exposes_only_public_values(self):
        cfg = self.client.get("/admin/config.json").json()
        self.assertEqual(set(cfg), {"supabase_url", "supabase_publishable_key", "dev_mode"})


if __name__ == "__main__":
    unittest.main()
