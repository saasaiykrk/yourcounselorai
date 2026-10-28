"""Sign-up details given before the email code, against a real Postgres. They are kept as a "started" sign-up
(shown in /admin), become the clinician's profile once a code sent to that email is verified, never overwrite an
existing account, and are deleted after 90 days if never finished. Set TEST_DATABASE_URL to run (skipped
otherwise)."""
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


DETAILS = {"full_name": "Dr Lead Sample", "gender": "female", "age": 34, "role": "psychologist",
           "registration_body": "RCI", "registration_number": "A12345", "consent_version": "2026-10-v3",
           "mobile": "+919876543210"}


@unittest.skipUnless(HAVE, "TEST_DATABASE_URL not set")
class SignupLeadTests(unittest.TestCase):
    def setUp(self):
        self.email = f"lead-{uuid.uuid4().hex[:10]}@clinic.test"
        q("insert into registration_settings (id) values (1) on conflict (id) do update set auto_approve=false")

    def lead(self, email=None):
        rows = q("select * from signup_leads where email=%s", (email or self.email).lower())
        return rows[0] if rows else None

    def account(self, email=None, profile=True):
        cid = str(uuid.uuid4())
        q("insert into auth.users (id, email) values (%s,%s)", cid, email or self.email)
        if profile:
            q("""insert into clinicians (id, role, registration_body, level, verification_status, consent_version)
                 values (%s,'psychologist','RCI','L2','verified','v1')""", cid)
        return cid

    def test_details_are_kept_as_a_started_sign_up_and_updated_if_sent_again(self):
        db.save_lead(self.email.upper(), DETAILS)
        self.assertEqual((self.lead()["status"], self.lead()["full_name"], self.lead()["mobile"]),
                         ("started", "Dr Lead Sample", "+919876543210"))
        db.save_lead(self.email, {**DETAILS, "full_name": "Dr Lead Fixed"})
        self.assertEqual(self.lead()["full_name"], "Dr Lead Fixed")
        self.assertEqual(len(q("select 1 from signup_leads where email=%s", self.email)), 1)
        started = [r["email"] for r in db.signup_leads("started")]
        self.assertIn(self.email, started, "shown in /admin")

    def test_an_existing_account_is_never_touched(self):
        self.account()
        db.save_lead(self.email, DETAILS)
        self.assertIsNone(self.lead(), "already registered: they just sign in")

    def test_the_verified_code_turns_the_details_into_the_profile(self):
        db.save_lead(self.email, DETAILS)
        cid = self.account(profile=False)
        self.assertTrue(db.complete_lead(cid, self.email))
        c = db.get_clinician(cid)
        self.assertEqual((c["full_name"], c["role"], c["mobile"], c["consent_version"], c["verification_status"]),
                         ("Dr Lead Sample", "psychologist", "+919876543210", "2026-10-v3", "pending"))
        self.assertEqual((self.lead()["status"], str(self.lead()["clinician_id"])), ("completed", cid))
        self.assertFalse(db.complete_lead(cid, self.email), "only once")
        db.save_lead(self.email, {**DETAILS, "full_name": "Someone Else"})
        self.assertEqual(db.get_clinician(cid)["full_name"], "Dr Lead Sample", "a finished sign-up is not overwritten")

    def test_completion_follows_the_skip_verification_switch(self):
        q("update registration_settings set auto_approve=true where id=1")
        try:
            db.save_lead(self.email, {**DETAILS, "role": "psychiatrist", "registration_body": "NMC"})
            cid = self.account(profile=False)
            db.complete_lead(cid, self.email)
            c = db.get_clinician(cid)
            self.assertEqual((c["verification_status"], c["level"]), ("verified", "L3"))
        finally:
            q("update registration_settings set auto_approve=false where id=1")

    def test_no_details_for_that_email_means_nothing_happens(self):
        cid = self.account(profile=False)
        self.assertFalse(db.complete_lead(cid, self.email))
        self.assertIsNone(db.get_clinician(cid))

    def test_unfinished_sign_ups_go_after_90_days(self):
        db.save_lead(self.email, DETAILS)
        q("update signup_leads set created_at=now() - interval '91 days', updated_at=now() - interval '91 days' "
          "where email=%s", self.email)
        db.signup_leads("started")
        self.assertIsNone(self.lead())

    def test_deleting_the_account_deletes_its_sign_up_details(self):
        db.save_lead(self.email, DETAILS)
        cid = self.account(profile=False)
        db.complete_lead(cid, self.email)
        db.delete_account(cid)
        self.assertIsNone(self.lead())
