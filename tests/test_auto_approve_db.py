"""The admin's "skip verification" switch, against a real Postgres. Off (the default): every registration waits
for an admin. On: a registration is approved at once, with the level of the role the clinician chose (trainee L1,
psychologist L2, psychiatrist L3), set by the server from the clinicians row and never from the request; each
approval is audited. Set TEST_DATABASE_URL to run (skipped otherwise)."""
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


PROFILE = {"full_name": "Dr Sample", "gender": "female", "age": 34, "role": "psychologist",
           "registration_body": "RCI", "registration_number": "A12345", "consent_version": "2026-10-v3",
           "mobile": "+919876543210"}


@unittest.skipUnless(HAVE, "TEST_DATABASE_URL not set")
class AutoApproveTests(unittest.TestCase):
    def setUp(self):
        self.admin = self.user(admin=True)
        db.set_auto_approve(False, self.admin)

    def tearDown(self):
        db.set_auto_approve(False, self.admin)

    def user(self, admin=False):
        cid = str(uuid.uuid4())
        q("insert into auth.users (id, email) values (%s,%s)", cid, f"auto-{cid[:8]}@clinic.test")
        if admin:
            q("""insert into clinicians (id, role, registration_body, level, verification_status, consent_version,
                   is_admin) values (%s,'psychologist','RCI','L2','verified','v1',true)""", cid)
        return cid

    def row(self, cid):
        return db.get_clinician(cid)

    def test_off_by_default_every_registration_waits_for_an_admin(self):
        self.assertFalse(db.auto_approve())
        cid = self.user()
        db.upsert_clinician_profile(cid, PROFILE)
        self.assertEqual((self.row(cid)["verification_status"], self.row(cid)["level"]), ("pending", None))

    def test_on_approves_at_once_with_the_level_of_the_chosen_role(self):
        db.set_auto_approve(True, self.admin)
        self.assertTrue(db.auto_approve())
        for role, body, level in (("counsellor_trainee", "none", "L1"), ("psychologist", "RCI", "L2"),
                                  ("psychiatrist", "NMC", "L3")):
            cid = self.user()
            db.upsert_clinician_profile(cid, {**PROFILE, "role": role, "registration_body": body})
            r = self.row(cid)
            self.assertEqual((r["verification_status"], r["level"]), ("verified", level), role)
            self.assertIn("automatically", r["verification_note"])
            audit = q("select actor_id, action, detail from admin_audit where target_id=%s", cid)
            self.assertEqual([(str(a["actor_id"]), a["action"], a["detail"]["level"]) for a in audit],
                             [(cid, "auto_verify", level)], "every automatic approval is recorded")

    def test_a_level_in_the_request_is_never_used(self):
        db.set_auto_approve(True, self.admin)
        cid = self.user()
        db.upsert_clinician_profile(cid, {**PROFILE, "role": "counsellor_trainee", "registration_body": "none",
                                          "level": "L3"})
        self.assertEqual(self.row(cid)["level"], "L1")

    def test_a_changed_role_is_approved_again_at_its_own_level(self):
        db.set_auto_approve(True, self.admin)
        cid = self.user()
        db.upsert_clinician_profile(cid, PROFILE)
        p = {k: PROFILE[k] for k in ("full_name", "gender", "age", "registration_number", "mobile")}
        res = db.update_clinician_profile(cid, {**p, "role": "psychiatrist", "registration_body": "NMC"})
        self.assertEqual(res, {"verification_status": "verified", "reverify": True})
        self.assertEqual(self.row(cid)["level"], "L3")
        db.set_auto_approve(False, self.admin)
        db.update_clinician_profile(cid, {**p, "role": "psychologist", "registration_body": "RCI"})
        self.assertEqual((self.row(cid)["verification_status"], self.row(cid)["level"]), ("pending", None),
                         "switch off: a change waits for an admin again")

    def test_switching_on_approves_those_already_waiting(self):
        waiting = self.user()
        db.upsert_clinician_profile(waiting, {**PROFILE, "role": "counsellor_trainee", "registration_body": "none"})
        rejected = self.user()
        db.upsert_clinician_profile(rejected, PROFILE)
        db.set_verification(rejected, None, "rejected", "number not on the register", self.admin)
        approved = db.set_auto_approve(True, self.admin)
        self.assertGreaterEqual(approved, 1)
        self.assertEqual((self.row(waiting)["verification_status"], self.row(waiting)["level"]), ("verified", "L1"))
        self.assertEqual(self.row(rejected)["verification_status"], "rejected", "a rejection made by an admin stays")
        changes = q("select detail from admin_audit where actor_id=%s and action='auto_approve_switch' "
                    "order by id desc limit 1", self.admin)
        self.assertEqual(changes[0]["detail"]["on"], True)
