"""Account deletion against a real Postgres: the sign-in and every personal detail go; what the law or safety
review needs stays, with no name or email attached. Set TEST_DATABASE_URL to run (skipped otherwise)."""
import importlib.util
import os
import unittest
import uuid

URL = os.environ.get("TEST_DATABASE_URL", "")
HAVE = bool(URL) and importlib.util.find_spec("psycopg") is not None

if HAVE:
    import psycopg
    from psycopg.rows import dict_row

    from app import db
    db._DSN = URL


def q(sql, *a):
    with psycopg.connect(URL, autocommit=True, row_factory=dict_row) as c:
        cur = c.execute(sql, a)
        return cur.fetchall() if cur.description else None


@unittest.skipUnless(HAVE, "TEST_DATABASE_URL not set")
class AccountDeletionTests(unittest.TestCase):
    def setUp(self):
        self.cid = str(uuid.uuid4())
        q("insert into auth.users (id, email) values (%s,%s)", self.cid, f"del-{self.cid[:8]}@clinic.test")
        q("""insert into clinicians (id, role, registration_body, registration_number, full_name, gender,
               age_at_registration, level, verification_status, consent_version, consent_at)
             values (%s,'psychologist','RCI','A12345','Dr Asha Rao','female',41,'L2','verified','beta-draft-2',now())""",
          self.cid)
        self.conv = q("insert into conversations (clinician_id) values (%s) returning id", self.cid)[0]["id"]
        q("""insert into byok_credentials (clinician_id, ciphertext, nonce, key_version, last4, status)
             values (%s,'\\x00','\\x00',1,'abcd','valid')""", self.cid)
        q("insert into booking_settings (clinician_id, slug, display_name) values (%s,%s,'Dr Asha Rao')",
          self.cid, "asha-" + self.cid[:8])
        q("insert into availability_windows (clinician_id, weekday, start_time, end_time) values (%s,0,'09:00','17:00')",
          self.cid)
        q("""insert into appointments (clinician_id, starts_at, ends_at, blocked_until, status, source, client_ct,
               client_nonce, client_key_ver)
             values (%s, now() + interval '1 day', now() + interval '1 day 30 min', now() + interval '1 day 30 min',
                     'confirmed', 'public', '\\x01', '\\x02', 1)""", self.cid)
        q("""insert into entitlements (clinician_id, plan, credits_total, expires_at)
             values (%s,'sub_30',30, now() + interval '20 days')""", self.cid)
        q("""insert into billing_orders (clinician_id, plan, amount, currency, config_version, status)
             values (%s,'sub_30',199900,'INR',1,'paid')""", self.cid)

    def test_the_sign_in_and_personal_details_go_records_the_law_needs_stay(self):
        self.assertEqual(db.delete_account(self.cid), "deleted")
        self.assertEqual(q("select 1 from auth.users where id=%s", self.cid), [], "the sign-in and email are gone")
        c = q("select * from clinicians where id=%s", self.cid)[0]
        for k in ("full_name", "gender", "age_at_registration", "registration_number", "level"):
            self.assertIsNone(c[k], k)
        self.assertEqual(c["verification_status"], "deleted")
        self.assertIsNotNone(c["deleted_at"])
        for table in ("byok_credentials", "booking_settings", "availability_windows", "appointments"):
            self.assertEqual(q(f"select 1 from {table} where clinician_id=%s", self.cid), [], table)
        self.assertIsNotNone(q("select hidden_at from conversations where id=%s", self.conv)[0]["hidden_at"],
                             "consults leave the history; the de-identified copy stays for safety review")
        self.assertEqual({r["status"] for r in q("select status from entitlements where clinician_id=%s", self.cid)},
                         {"cancelled"})
        self.assertEqual(len(q("select 1 from billing_orders where clinician_id=%s", self.cid)), 1,
                         "payment records stay (tax law)")
        audit = q("select action, detail from admin_audit where target_id=%s", self.cid)
        self.assertEqual([a["action"] for a in audit], ["account_deleted"])
        self.assertNotIn("Asha", str(audit), "no personal detail in the audit")
        self.assertIsNone(db.get_clinician(self.cid)["full_name"])

    def test_deleting_twice_or_without_a_registration_is_fine(self):
        db.delete_account(self.cid)
        self.assertEqual(db.delete_account(self.cid), "deleted", "a retry after a lost reply does no harm")
        loner = str(uuid.uuid4())
        q("insert into auth.users (id, email) values (%s,%s)", loner, f"new-{loner[:8]}@clinic.test")
        self.assertEqual(db.delete_account(loner), "deleted", "signed up but never registered")
        self.assertEqual(q("select 1 from auth.users where id=%s", loner), [])

    def test_admins_cannot_delete_themselves(self):
        q("update clinicians set is_admin = true where id=%s", self.cid)
        self.assertEqual(db.delete_account(self.cid), "admin")
        self.assertEqual(len(q("select 1 from auth.users where id=%s", self.cid)), 1, "nothing changed")
        self.assertEqual(q("select full_name from clinicians where id=%s", self.cid)[0]["full_name"], "Dr Asha Rao")


if __name__ == "__main__":
    unittest.main()
