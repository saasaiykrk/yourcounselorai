"""Turns remember the app's request id (migration 009), so a reply that finished while the phone was
disconnected can be fetched again by its owner only. Real Postgres; skipped without TEST_DATABASE_URL."""
import importlib.util
import os
import unittest
import uuid
from types import SimpleNamespace

URL = os.environ.get("TEST_DATABASE_URL", "")
HAVE = bool(URL) and importlib.util.find_spec("psycopg") is not None
if HAVE:
    import psycopg

    from app import db
    db._DSN = URL


def result(text="MODE: B | reply"):
    return SimpleNamespace(raw_text=text, display_text=text, status="delivered", attempts=1,
                           reports=[{"passed": True, "blocks": []}], model="m", skill_version="2.1.1",
                           prompt_hash="h", tool_calls=[], verified_icd_codes=[], usage=[], latency_ms=10,
                           held_back=None)


@unittest.skipUnless(HAVE, "TEST_DATABASE_URL not set")
class TurnRequestIdTests(unittest.TestCase):
    def setUp(self):
        self.me, self.other = str(uuid.uuid4()), str(uuid.uuid4())
        with psycopg.connect(URL, autocommit=True) as c:
            for i, who in enumerate((self.me, self.other)):
                c.execute("insert into auth.users (id, email) values (%s,%s)", (who, f"t{i}-{who[:6]}@test"))
                c.execute("""insert into clinicians (id, role, registration_body, level, verification_status,
                               consent_version) values (%s,'psychologist','RCI','L2','verified','v1')""", (who,))
        self.conv = db.new_conversation(self.me)

    def body(self, request_id):
        return SimpleNamespace(mode="B", text="34F, panic attacks.", client_redaction_counts={}, request_id=request_id)

    def test_the_owner_gets_the_saved_reply_back_by_request_id(self):
        rid = "req-" + uuid.uuid4().hex[:12]
        turn = db.log_turn(self.conv, self.me, "L2", self.body(rid), result("MODE: B | the reply"))
        t = db.turn_by_request(self.me, rid)
        self.assertEqual((t["id"], t["output_shown"], t["status"]), (turn, "MODE: B | the reply", "delivered"))
        self.assertEqual(str(t["conversation_id"]), str(self.conv))
        self.assertIsNone(db.turn_by_request(self.other, rid), "never another clinician's reply")
        self.assertIsNone(db.turn_by_request(self.me, "never-sent-123"))

    def test_turns_without_a_request_id_still_save(self):
        db.log_turn(self.conv, self.me, "L2", self.body(None), result())
        db.log_turn(self.conv, self.me, "L2", self.body(None), result())


if __name__ == "__main__":
    unittest.main()
