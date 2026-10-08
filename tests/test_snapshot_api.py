"""CR-001 Case Snapshot over HTTP in DEV_MODE (keyless fake model, in-memory store): case → pre-filled
form → every field resolved → one case-specific question → report with the app's snapshot table.
Skipped where the app's dependencies aren't installed."""
import importlib.util
import os
import unittest

HAVE_DEPS = all(importlib.util.find_spec(m) for m in ("fastapi", "httpx", "psycopg"))

if HAVE_DEPS:
    os.environ["DEV_MODE"] = "1"
    from fastapi.testclient import TestClient

    from app import main

ME = {"Authorization": "Bearer dev-L2"}
PANIC = "34F, panic attacks with sweating and palpitations, 4 weeks, sudden, no incident"
REST = {
    "education": {"chips": ["Graduate"]}, "occupation": {"chips": ["Salaried"], "text": "IT professional"},
    "living_situation": {"chips": ["Married"]}, "help_requested": {"chips": ["Full case plan"]},
    "prior_therapy": {"chips": ["None"]}, "past_psychiatric_history": {"chips": ["None"]},
    "medications": {"chips": ["None"]}, "medical_history": {"chips": ["None known"]},
    "medical_review_since_onset": {"chips": ["No"]}, "substance_use": {"chips": ["Caffeine (high)"]},
    "family_structure": {"chips": ["Supportive"]}, "family_history": {"status": "not_known"},
    "risk_screening": {"chips": ["Asked and absent"]}, "functioning": {"chips": ["Moderate"]},
    "sleep_appetite": {"chips": ["Reduced sleep"]},
}


@unittest.skipUnless(HAVE_DEPS, "fastapi/httpx/psycopg not installed")
class SnapshotApiTests(unittest.TestCase):
    def setUp(self):
        main._dev_consults = main.DevConsultationStore()
        main._dev_history = main.DevHistoryStore()
        self.client = TestClient(main.app)

    def start(self, text=PANIC):
        r = self.client.post("/v1/consultations", headers=ME,
                             json={"text": text, "deid_attested": True, "snapshot": True})
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()

    def patch(self, cid, fields, status=200, **flags):
        r = self.client.patch(f"/v1/consultations/{cid}/snapshot", headers=ME,
                              json={"fields": fields, "deid_attested": True, **flags})
        self.assertEqual(r.status_code, status, r.text)
        return r.json()

    def test_full_flow(self):
        v = self.start()
        self.assertEqual(v["stage"], "INITIAL_CASE")
        self.assertIsNone(v["question"])
        fields = {f["key"]: f for f in v["snapshot"]["fields"]}
        self.assertEqual({k for k, f in fields.items() if f["prefilled"]},
                         {"age", "gender", "presenting_concern", "duration", "onset", "precipitant"})
        self.assertEqual(fields["duration"]["chips_selected"], ["2–4 weeks"])
        self.assertIn("Do not name the", fields["occupation"]["helper"])
        self.assertTrue(fields["occupation"]["optional"], "the case check decides what is asked")
        self.assertFalse(fields["medications"]["optional"])

        self.patch(v["id"], {"education": {"chips": ["Graduate"]}}, done=True, status=409)
        v = self.patch(v["id"], REST, done=True)
        self.assertEqual(v["stage"], "QUESTIONING")
        self.assertEqual(v["question"]["field"], "episode_frequency")
        self.assertEqual(v["max_questions"], 4)
        r = self.client.post(f"/v1/consultations/{v['id']}/reply", headers=ME,
                             json={"action": "answer", "text": "Three a week", "deid_attested": True})
        v = r.json()
        self.assertEqual(v["stage"], "INFORMATION_SUFFICIENT")

        body = self.client.post(f"/v1/consultations/{v['id']}/report", headers=ME, json={}).json()
        self.assertEqual(body["reply"]["status"], "delivered", body["reply"].get("report"))
        snapshot = body["reply"]["text"].split("### Case Snapshot", 1)[1].split("### 1.", 1)[0]
        self.assertIn("| Age | 34 years |", snapshot)
        self.assertNotIn("Family history", snapshot, "not known: left out")
        self.assertNotIn("not provided", snapshot.lower())

        # CR1-09: edit after the report, then update it.
        v = self.patch(v["id"], {"medications": {"chips": ["Yes (list)"], "text": "sertraline 50 mg"}})
        self.assertEqual(v["stage"], "INFORMATION_SUFFICIENT")
        again = self.client.post(f"/v1/consultations/{v['id']}/report", headers=ME, json={}).json()
        self.assertNotEqual(again["reply"]["turn_id"], body["reply"]["turn_id"])
        self.assertIn("sertraline 50 mg", again["reply"]["text"])

    def test_skip_remaining_and_risk_gate(self):
        v = self.start()
        v = self.patch(v["id"], {"risk_screening": {"chips": ["Risk present"]}})
        self.assertEqual(v["stage"], "SAFETY_STOP")
        v = self.client.post(f"/v1/consultations/{v['id']}/reply", headers=ME,
                             json={"action": "safety_managed"}).json()
        self.assertEqual(v["stage"], "INITIAL_CASE")
        v = self.patch(v["id"], {}, skip_remaining=True)
        self.assertEqual(v["stage"], "INFORMATION_SUFFICIENT")
        self.assertIn("Prior therapy", v["snapshot"]["ask_next"])
        self.assertNotIn("Education", v["snapshot"]["ask_next"], "not needed for this case: not a gap")
        body = self.client.post(f"/v1/consultations/{v['id']}/report", headers=ME, json={}).json()
        self.assertIn("Ask in the next session:** Help requested, Prior therapy", body["reply"]["text"])
        self.assertNotIn("| Prior therapy |", body["reply"]["text"])
        self.assertNotIn("| Education |", body["reply"]["text"])

    def test_input_is_checked(self):
        v = self.start()
        self.patch(v["id"], {"occupation": {"text": "call 9876543210"}}, status=422)
        self.patch(v["id"], {"education": {"chips": ["PhD"]}}, status=422)
        self.patch(v["id"], {"education": {"status": "skipped"}}, status=422)   # skipped only via skip remaining
        self.patch(v["id"], {"education": {"chips": ["Graduate"], "level": "L3"}}, status=422)
        r = self.client.patch(f"/v1/consultations/{v['id']}/snapshot", headers=ME,
                              json={"fields": {"occupation": {"text": "IT professional"}}})
        self.assertEqual(r.status_code, 422, "free text needs the de-identification attestation")

    def test_older_apps_keep_the_chat_flow(self):
        r = self.client.post("/v1/consultations", headers=ME, json={"text": PANIC, "deid_attested": True})
        v = r.json()
        self.assertIsNone(v["snapshot"])
        self.assertEqual(v["stage"], "QUESTIONING")
        self.patch(v["id"], {"education": {"chips": ["Graduate"]}}, status=409)

    def test_other_clinicians_cannot_touch_it(self):
        v = self.start()
        main.app.dependency_overrides[main.verified_clinician] = lambda: {
            "id": "99999999-9999-4999-8999-999999999999", "level": "L2", "verification_status": "verified"}
        try:
            r = self.client.patch(f"/v1/consultations/{v['id']}/snapshot", headers=ME, json={"fields": {}})
        finally:
            main.app.dependency_overrides.clear()
        self.assertEqual(r.status_code, 404)


if __name__ == "__main__":
    unittest.main()
