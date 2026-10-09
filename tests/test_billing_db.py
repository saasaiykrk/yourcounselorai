"""Credits and payments against a real Postgres (db/schema.sql + migration 006).
Set TEST_DATABASE_URL to a throwaway database to run these; they are skipped otherwise.
CI runs them against a Postgres service container."""
import copy
import importlib.util
import os
import threading
import unittest
import uuid

URL = os.environ.get("TEST_DATABASE_URL", "")
HAVE = bool(URL) and importlib.util.find_spec("psycopg") is not None

if HAVE:
    import psycopg

    from app import billing, billing_db, db
    db._DSN = URL


def pay():
    return "pay_" + uuid.uuid4().hex[:14]


def _sql(q, *a):
    with psycopg.connect(URL, autocommit=True) as c:
        return c.execute(q, a).fetchall() if c.execute(q, a).description else None


@unittest.skipUnless(HAVE, "TEST_DATABASE_URL not set")
class BillingDbTests(unittest.TestCase):
    def setUp(self):
        self.cid = str(uuid.uuid4())
        self.admin = str(uuid.uuid4())
        with psycopg.connect(URL, autocommit=True) as c:
            for i, (who, adm) in enumerate(((self.cid, False), (self.admin, True))):
                c.execute("insert into auth.users (id, email) values (%s,%s)", (who, f"u{i}-{who[:6]}@test"))
                c.execute("""insert into clinicians (id, role, registration_body, level, verification_status,
                               consent_version, is_admin) values (%s,'psychologist','RCI','L2','verified','v1',%s)""",
                          (who, adm))
        self.cfg = billing.validate({"enabled": True})

    def order(self, plan="sub_30", rt=None):
        o = billing_db.create_order(self.cid, billing.price_for(self.cfg, plan, rt), 1)
        billing_db.set_provider_order(o["id"], "order_" + uuid.uuid4().hex[:14])
        return o

    def test_payment_grants_once_even_when_reported_twice(self):
        o = self.order("sub_30")
        p = pay()
        e1 = billing_db.fulfil(o["id"], p, self.cfg)
        e2 = billing_db.fulfil(o["id"], p, self.cfg)                # webhook after the checkout callback
        self.assertEqual(e1["id"], e2["id"])
        self.assertEqual(billing_db.balance(self.cid), {"any": 30, "guided": 30, "direct": 30})
        grants = [r for r in billing_db.ledger(self.cid) if r["kind"] == "grant"]
        self.assertEqual(len(grants), 1)
        ent = billing_db.entitlements(self.cid)[0]
        self.assertAlmostEqual((ent["expires_at"] - ent["starts_at"]).days, 30)
        self.assertEqual(billing_db.get_order(o["id"])["status"], "paid")

    def test_fifty_report_plan_and_per_report_credit_for_its_type_only(self):
        billing_db.fulfil(self.order("sub_50")["id"], pay(), self.cfg)
        self.assertEqual(billing_db.balance(self.cid)["any"], 50)
        cid2 = self.cid
        billing_db.fulfil(self.order("per_report", "guided")["id"], pay(), self.cfg)
        b = billing_db.balance(cid2)
        self.assertEqual((b["guided"], b["direct"]), (51, 50))

    def test_reserve_consume_release(self):
        billing_db.fulfil(self.order("per_report", "direct")["id"], pay(), self.cfg)
        with self.assertRaises(billing_db.NoCredit):
            billing_db.reserve(self.cid, "guided", "k-guided")        # a direct credit is not a guided one
        billing_db.reserve(self.cid, "direct", "k1")
        with self.assertRaises(billing_db.InProgress):
            billing_db.reserve(self.cid, "direct", "k1")
        self.assertEqual(billing_db.balance(self.cid)["direct"], 0, "held while the report is written")
        billing_db.release(self.cid, "k1", "held back by the safety check")
        self.assertEqual(billing_db.balance(self.cid)["direct"], 1, "a failed report costs nothing")
        billing_db.reserve(self.cid, "direct", "k1")                  # the retry may reserve again
        billing_db.consume(self.cid, "k1")
        billing_db.consume(self.cid, "k1")                            # a repeat changes nothing
        self.assertEqual(billing_db.balance(self.cid)["direct"], 0)
        with self.assertRaises(billing_db.AlreadyCharged):
            billing_db.reserve(self.cid, "direct", "k1")
        kinds = [r["kind"] for r in reversed(billing_db.ledger(self.cid))]
        self.assertEqual(kinds, ["grant", "reserve", "release", "reserve", "consume"])

    def test_concurrent_requests_cannot_overspend(self):
        billing_db.fulfil(self.order("per_report", "guided")["id"], pay(), self.cfg)
        results, barrier = [], threading.Barrier(5)

        def go(i):
            barrier.wait()
            try:
                billing_db.reserve(self.cid, "guided", f"race-{i}")
                results.append("ok")
            except billing_db.NoCredit:
                results.append("none")
        threads = [threading.Thread(target=go, args=(i,)) for i in range(5)]
        [t.start() for t in threads]
        [t.join() for t in threads]
        self.assertEqual(sorted(results), ["none"] * 4 + ["ok"])

    def test_expired_subscription_cannot_be_used_and_expiry_is_recorded_once(self):
        e = billing_db.fulfil(self.order("sub_30")["id"], pay(), self.cfg)
        _sql("update entitlements set expires_at = now() - interval '1 minute' where id=%s", str(e["id"]))
        with self.assertRaises(billing_db.NoCredit):
            billing_db.reserve(self.cid, "direct", "late")
        billing_db.entitlements(self.cid)
        ents = billing_db.entitlements(self.cid)
        self.assertEqual(ents[0]["state"], "expired")
        self.assertEqual([r["amount"] for r in billing_db.ledger(self.cid) if r["kind"] == "expire"], [-30])

    def test_exhausted_state(self):
        e = billing_db.fulfil(self.order("sub_30")["id"], pay(), self.cfg)
        _sql("update entitlements set credits_used = 30 where id=%s", str(e["id"]))
        self.assertEqual(billing_db.entitlements(self.cid)[0]["state"], "exhausted")
        with self.assertRaises(billing_db.NoCredit):
            billing_db.reserve(self.cid, "guided", "x")

    def test_a_stuck_reservation_is_given_back(self):
        billing_db.fulfil(self.order("per_report", "guided")["id"], pay(), self.cfg)
        billing_db.reserve(self.cid, "guided", "stuck")
        _sql("update credit_ledger set created_at = now() - interval '1 hour' where request_key='stuck'")
        billing_db.reserve(self.cid, "guided", "next")               # finds the credit again
        self.assertEqual(billing_db.balance(self.cid)["guided"], 0)

    def test_renewal_keeps_the_earlier_period_and_rollover_extends_it(self):
        first = billing_db.fulfil(self.order("sub_30")["id"], pay(), self.cfg)
        billing_db.fulfil(self.order("sub_30")["id"], pay(), self.cfg)
        self.assertEqual(billing_db.balance(self.cid)["any"], 60, "renewing early loses nothing")
        rolled = copy.deepcopy(self.cfg)
        rolled["rollover"] = True
        _sql("update entitlements set expires_at = now() + interval '2 days' where id=%s", str(first["id"]))
        third = billing_db.fulfil(self.order("sub_30")["id"], pay(), rolled)
        ents = {str(e["id"]): e for e in billing_db.entitlements(self.cid)}
        self.assertEqual(ents[str(first["id"])]["expires_at"], ents[str(third["id"])]["expires_at"])

    def test_byok_fee_period_stacks(self):
        c = billing.validate({"enabled": True, "plans": {"byok": {"enabled": True, "fee": 9900, "fee_days": 30}}})
        o1 = billing_db.create_order(self.cid, billing.price_for(c, "byok", None), 1)
        o2 = billing_db.create_order(self.cid, billing.price_for(c, "byok", None), 1)
        self.assertFalse(billing_db.byok_access(self.cid))
        a = billing_db.fulfil(o1["id"], pay(), c)
        b = billing_db.fulfil(o2["id"], pay(), c)
        self.assertTrue(billing_db.byok_access(self.cid))
        self.assertEqual(b["starts_at"], a["expires_at"], "a renewal starts when the paid period ends")

    def test_admin_adjust_extend_deactivate_are_audited(self):
        e = billing_db.fulfil(self.order("sub_30")["id"], pay(), self.cfg)
        billing_db.admin_adjust(self.cid, 5, self.admin, "goodwill")
        self.assertEqual(billing_db.balance(self.cid)["any"], 35)
        billing_db.admin_adjust(self.cid, -32, self.admin, "correction")
        self.assertEqual(billing_db.balance(self.cid)["any"], 3)
        with self.assertRaises(billing_db.NoCredit):
            billing_db.admin_adjust(self.cid, -10, self.admin, "too many")
        billing_db.admin_extend(e["id"], 7, self.admin, "outage")
        billing_db.admin_set_status(e["id"], False, self.admin, "chargeback")
        actions = [a["action"] for a in billing_db.admin_user(self.cid)["audit"]]
        self.assertEqual(sorted(set(actions)), ["billing_adjust", "billing_deactivate", "billing_extend"])

    def test_refund_is_counted_once_and_can_revoke_credits(self):
        o = self.order("sub_30")
        billing_db.fulfil(o["id"], pay(), self.cfg)
        billing_db.record_refund(o["id"], "rfnd_1", 199900, self.admin, True, "duplicate purchase")
        self.assertEqual(billing_db.balance(self.cid)["any"], 0)
        self.assertEqual(billing_db.get_order(o["id"])["refund_status"], "pending")
        self.assertTrue(billing_db.refund_settled("rfnd_1", 199900, "processed"))
        self.assertFalse(billing_db.refund_settled("rfnd_1", 199900, "processed"))
        o2 = billing_db.get_order(o["id"])
        self.assertEqual((o2["refund_status"], o2["refunded_amount"]), ("refunded", 199900))

    def test_revenue_counts_only_collected_payments(self):
        paid = self.order("sub_30")
        billing_db.fulfil(paid["id"], pay(), self.cfg)
        failed = self.order("sub_50")
        billing_db.mark_order(failed["id"], "failed", pay(), "card declined")
        self.order("per_report", "guided")                           # left pending
        rev = {r["plan"]: r for r in billing_db.revenue()["by_plan"]}
        self.assertGreaterEqual(rev["sub_30"]["collected"], 199900)
        self.assertEqual(rev["sub_50"]["collected"] if "sub_50" in rev else 0,
                         sum(r["amount"] for r in billing_db.admin_orders("paid", "sub_50", None)) or 0)
        mine = [o for o in billing_db.admin_orders(None, None, self.cid)]
        self.assertEqual(sorted(o["status"] for o in billing_db.orders(self.cid)), ["created", "failed", "paid"])
        self.assertEqual(mine, [])  # admin search is by order/payment id, name or email — not clinician id

    def test_webhook_event_is_applied_once(self):
        eid = "evt_" + uuid.uuid4().hex
        self.assertTrue(billing_db.first_time_event(eid, "payment.captured", "order_x", pay()))
        self.assertFalse(billing_db.first_time_event(eid, "payment.captured", "order_x", pay()))
        billing_db.forget_event(eid)
        self.assertTrue(billing_db.first_time_event(eid, "payment.captured", "order_x", pay()))

    def test_config_versions_and_audit(self):
        v = billing_db.save_config(self.cfg, self.admin, {"enabled": [False, True]})
        version, got = billing_db.get_config()
        self.assertEqual((version, got["enabled"]), (v, True))


if __name__ == "__main__":
    unittest.main()
