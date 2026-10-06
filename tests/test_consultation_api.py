"""Guided consultation over HTTP, end to end in DEV_MODE (fake keyless model, in-memory store):
case → mandatory questions → answers → report → History. Skipped where the app's dependencies
aren't installed (the stdlib-only safety suite still runs)."""
import dataclasses
import importlib.util
import os
import unittest

HAVE_DEPS = all(importlib.util.find_spec(m) for m in ("fastapi", "httpx", "psycopg"))

if HAVE_DEPS:
    os.environ["DEV_MODE"] = "1"
    from fastapi.testclient import TestClient

    from app import main

ME = {"Authorization": "Bearer dev-L2"}
CASE = ("9-year-old boy, Class 4. Holds saliva then spits, rewinds reels, makes parents repeat words, "
        "avoids black objects, picks hair, fear of darkness, heavy YouTube and Roblox use.")


@unittest.skipUnless(HAVE_DEPS, "fastapi/httpx/psycopg not installed")
class ConsultationApiTests(unittest.TestCase):
    def setUp(self):
        main._dev_consults = main.DevConsultationStore()
        main._dev_history = main.DevHistoryStore()
        self.client = TestClient(main.app)

    def start(self, text=CASE):
        r = self.client.post("/v1/consultations", headers=ME, json={"text": text, "deid_attested": True})
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()

    def reply(self, cid, action="answer", text="", msg_id=None, status=200):
        r = self.client.post(f"/v1/consultations/{cid}/reply", headers=ME,
                             json={"action": action, "text": text, "deid_attested": True, "client_msg_id": msg_id})
        self.assertEqual(r.status_code, status, r.text)
        return r.json()

    def test_full_flow_case_questions_report_history(self):
        v = self.start()
        self.assertEqual(v["stage"], "QUESTIONING")
        self.assertEqual(v["question"]["field"], "age_gender")
        v = self.reply(v["id"], text="9 years, male")
        self.assertEqual(v["question"]["field"], "risk_screening")
        self.assertEqual(v["question"]["options"], ["Asked and absent", "Risk present", "Not yet asked"])
        v = self.reply(v["id"], text="Asked and absent")
        self.assertEqual(v["question"]["field"], "duration_onset")
        v = self.reply(v["id"], text="About 10 months, gradual")
        self.assertEqual(v["stage"], "INFORMATION_SUFFICIENT")
        self.assertEqual(v["facts"]["age_gender"], "9 years, male")
        self.assertEqual(len(v["transcript"]), 3)

        r = self.client.post(f"/v1/consultations/{v['id']}/report", headers=ME, json={})
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertEqual(body["reply"]["status"], "delivered", body["reply"].get("report"))
        self.assertTrue(body["reply"]["text"].startswith("## Consultation Report"))
        self.assertEqual(body["consultation"]["stage"], "COMPLETED")

        again = self.client.post(f"/v1/consultations/{v['id']}/report", headers=ME, json={}).json()
        self.assertEqual(again["reply"]["turn_id"], body["reply"]["turn_id"])     # not written twice
        got = self.client.get(f"/v1/consultations/{v['id']}", headers=ME).json()
        self.assertEqual(got["reply"]["text"], body["reply"]["text"])
        hist = self.client.get("/v1/history", headers=ME, params={"mode": "R"}).json()["consults"]
        self.assertEqual([h["id"] for h in hist], [v["id"]])
        self.assertEqual(self.client.get("/v1/consultations", headers=ME).json()["consultations"], [])

    def test_case_type_plan_and_clarifying_question_reach_the_app(self):
        v = self.start()
        self.assertEqual(v["case_type"], "Sample case (dev mode)")
        self.assertIn("age_gender", v["info_needed"])
        self.assertNotIn("presenting_concern", v["info_needed"])          # already given in the case
        self.assertFalse(v["question"]["clarify"])
        v = self.reply(v["id"], text="young")                               # too short: one clarifying question
        self.assertEqual(v["question"]["field"], "age_gender")
        self.assertTrue(v["question"]["clarify"])
        v = self.reply(v["id"], text="9 years, male")
        self.assertEqual(v["question"]["field"], "risk_screening")
        self.assertNotIn("age_gender", v["info_needed"])

    def test_unfinished_consultation_can_be_continued(self):
        v = self.start()
        listed = self.client.get("/v1/consultations", headers=ME).json()["consultations"]
        self.assertEqual([x["id"] for x in listed], [v["id"]])
        got = self.client.get(f"/v1/consultations/{v['id']}", headers=ME).json()
        self.assertEqual(got["question"]["field"], "age_gender")
        self.assertIsNone(got["reply"])

    def test_identifiers_refused_at_start_and_in_answers(self):
        r = self.client.post("/v1/consultations", headers=ME, json={"text": CASE + " Call 9876543210.",
                                                                     "deid_attested": True})
        self.assertEqual(r.status_code, 422)
        self.assertEqual(r.json()["detail"], {"error": "identifiers_detected", "types": ["PHONE"]})
        v = self.start()
        err = self.reply(v["id"], text="mother's number is 9876543210", status=422)
        self.assertEqual(err["detail"]["error"], "identifiers_detected")
        # the consultation is not left locked after a refused answer
        self.reply(v["id"], text="9 years, male")

    def test_attestation_required(self):
        r = self.client.post("/v1/consultations", headers=ME, json={"text": CASE, "deid_attested": False})
        self.assertEqual(r.status_code, 422)

    def test_repeated_message_id_is_not_processed_twice(self):
        v = self.start()
        a = self.reply(v["id"], text="9 years, male", msg_id="m-1")
        b = self.reply(v["id"], text="9 years, male", msg_id="m-1")
        self.assertEqual(a, b)
        self.assertEqual(b["questions_asked"], 2)

    def test_busy_consultation_is_refused(self):
        v = self.start()
        main._dev_consults.claim(v["id"], "dev-clinician")
        r = self.client.post(f"/v1/consultations/{v['id']}/reply", headers=ME,
                             json={"action": "answer", "text": "9", "deid_attested": True})
        self.assertEqual(r.status_code, 409)

    def test_report_needs_information_unless_forced(self):
        v = self.start()
        r = self.client.post(f"/v1/consultations/{v['id']}/report", headers=ME, json={})
        self.assertEqual(r.status_code, 409)
        r = self.client.post(f"/v1/consultations/{v['id']}/report", headers=ME, json={"force": True})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["consultation"]["stage"], "COMPLETED")

    def test_risk_answer_stops_until_safety_is_confirmed(self):
        v = self.start()
        v = self.reply(v["id"], text="He said he wants to die and has kept pills at home")
        self.assertEqual(v["stage"], "SAFETY_STOP")
        self.assertIsNone(v["question"])
        self.reply(v["id"], text="more", status=409)
        v = self.reply(v["id"], action="safety_managed")
        self.assertEqual(v["facts"]["risk_screening"],
                         "risk present — clinician confirmed immediate safety is managed")
        self.assertNotEqual(v["stage"], "SAFETY_STOP")

    def test_facts_can_be_corrected_without_a_model_call(self):
        v = self.start()
        r = self.client.patch(f"/v1/consultations/{v['id']}/facts", headers=ME,
                              json={"facts": {"presenting_concern": "rituals and screen overuse"}})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["facts"]["presenting_concern"], "rituals and screen overuse")
        r = self.client.patch(f"/v1/consultations/{v['id']}/facts", headers=ME,
                              json={"facts": {"family": "mother at 9876543210"}})
        self.assertEqual(r.status_code, 422)

    def test_other_clinicians_cannot_see_it(self):
        # All dev tokens share one dev clinician id, so ownership is checked on the store.
        v = self.start()
        self.assertIsNone(main._dev_consults.get(v["id"], "someone-else"))
        self.assertIsNone(main._dev_consults.claim(v["id"], "someone-else"))

    def test_feature_flag_hides_the_endpoints(self):
        original = main.CFG
        main.CFG = dataclasses.replace(original, consultation_enabled=False)
        try:
            r = self.client.post("/v1/consultations", headers=ME, json={"text": CASE, "deid_attested": True})
            self.assertEqual(r.status_code, 404)
            self.assertFalse(self.client.get("/v1/me", headers=ME).json()["features"]["consultation"])
        finally:
            main.CFG = original
        self.assertTrue(self.client.get("/v1/me", headers=ME).json()["features"]["consultation"])

    def test_level_comes_from_the_clinician_not_the_request(self):
        v = self.start()
        r = self.client.post(f"/v1/consultations/{v['id']}/report", headers={"Authorization": "Bearer dev-L3"},
                             json={"force": True, "level": "L1"})
        self.assertEqual(r.status_code, 200, r.text)
        turn = main._dev_history.get(v["id"], "dev-clinician")["turns"][-1]
        self.assertEqual(turn["level"], "L3")
