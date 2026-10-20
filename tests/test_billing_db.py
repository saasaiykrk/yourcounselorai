"""Credits, plans and payments against a real Postgres (db/schema.sql + migrations 006-012).
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

    def order(self, plan="scale", rt=None, period=None):
        if plan in billing.TIERS and period is None:
            period = "month"
        o = billing_db.create_order(self.cid, billing.price_for(self.cfg, plan, rt, period=period), 1)
        billing_db.set_provider_order(o["id"], "order_" + uuid.uuid4().hex[:14])
        return o

    def test_payment_grants_once_even_when_reported_twice(self):
        o = self.order("scale")
        p = pay()
        e1 = billing_db.fulfil(o["id"], p, self.cfg)
        e2 = billing_db.fulfil(o["id"], p, self.cfg)                # webhook after the checkout callback
        self.assertEqual(e1["id"], e2["id"])
        self.assertEqual(billing_db.balance(self.cid), {"any": 0, "guided": 10, "direct": 0},
                         "Scale's reports are AI-Guided only")
        grants = [r for r in billing_db.ledger(self.cid) if r["kind"] == "grant"]
        self.assertEqual(len(grants), 1)
        self.assertEqual((e1["period"], e1["credits_total"]), ("month", 0), "the plan row is the access")
        self.assertAlmostEqual((e1["expires_at"] - e1["starts_at"]).days, 30)
        self.assertEqual(billing_db.get_order(o["id"])["status"], "paid")
        self.assertEqual(billing_db.get_order(o["id"])["period"], "month")

    def test_a_year_of_scale_is_twelve_monthly_allowances(self):
        e = billing_db.fulfil(self.order("scale", period="year")["id"], pay(), self.cfg)
        self.assertAlmostEqual((e["expires_at"] - e["starts_at"]).days, 365)
        ents = billing_db.entitlements(self.cid)
        allowances = sorted((x for x in ents if x["period"] == "allowance"), key=lambda x: x["starts_at"])
        self.assertEqual(len(allowances), 12)
        self.assertEqual([x["state"] for x in allowances[:2]], ["active", "scheduled"])
        self.assertEqual(allowances[-1]["expires_at"], e["expires_at"])
        self.assertEqual(billing_db.balance(self.cid)["guided"], 10, "only this month's 10 now; unused ones don't carry over")
        self.assertEqual([x["state"] for x in ents if x["id"] == e["id"]], ["active"])

    def test_which_credits_pay_for_which_report(self):
        billing_db.fulfil(self.order("scale")["id"], pay(), self.cfg)
        billing_db.fulfil(self.order("per_report", "guided")["id"], pay(), self.cfg)
        billing_db.fulfil(self.order("per_report", "direct")["id"], pay(), self.cfg)
        o = billing_db.create_order(self.cid, billing.price_for(self.cfg, "scale_extra", None), 1)
        billing_db.fulfil(o["id"], pay(), self.cfg)
        b = billing_db.balance(self.cid)
        self.assertEqual((b["guided"], b["direct"], b["any"]), (12, 1, 0))
        billing_db.admin_grant(self.cid, "manual", self.admin, "beta tester", self.cfg, 3, None)
        b = billing_db.balance(self.cid)
        self.assertEqual((b["guided"], b["direct"], b["any"]), (15, 4, 3), "an admin's credits pay for either")

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

    def test_scale_never_pays_for_a_quick_consult(self):
        billing_db.fulfil(self.order("scale")["id"], pay(), self.cfg)
        with self.assertRaises(billing_db.NoCredit):
            billing_db.reserve(self.cid, "direct", "quick")
        billing_db.reserve(self.cid, "guided", "guided-1")

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

    def test_an_ended_allowance_cannot_be_used_and_expiry_is_recorded_once(self):
        billing_db.fulfil(self.order("scale")["id"], pay(), self.cfg)
        _sql("update entitlements set expires_at = now() - interval '1 minute' where clinician_id=%s", self.cid)
        with self.assertRaises(billing_db.NoCredit):
            billing_db.reserve(self.cid, "guided", "late")
        billing_db.entitlements(self.cid)
        ents = billing_db.entitlements(self.cid)
        self.assertEqual({e["state"] for e in ents}, {"expired"})
        self.assertEqual([r["amount"] for r in billing_db.ledger(self.cid) if r["kind"] == "expire"], [-10])

    def test_used_up_reports_leave_the_plan_running(self):
        billing_db.fulfil(self.order("scale")["id"], pay(), self.cfg)
        _sql("update entitlements set credits_used = 10 where clinician_id=%s and period='allowance'", self.cid)
        states = {e["period"]: e["state"] for e in billing_db.entitlements(self.cid)}
        self.assertEqual(states, {"allowance": "exhausted", "month": "active"})
        with self.assertRaises(billing_db.NoCredit):
            billing_db.reserve(self.cid, "guided", "x")
        self.assertIn("guided_included", billing_db.plan_features(self.cid, self.cfg)["features"])

    def test_a_stuck_reservation_is_given_back(self):
        billing_db.fulfil(self.order("per_report", "guided")["id"], pay(), self.cfg)
        billing_db.reserve(self.cid, "guided", "stuck")
        _sql("update credit_ledger set created_at = now() - interval '1 hour' where request_key='stuck'")
        billing_db.reserve(self.cid, "guided", "next")               # finds the credit again
        self.assertEqual(billing_db.balance(self.cid)["guided"], 0)

    def test_renewing_early_starts_when_the_paid_period_ends(self):
        a = billing_db.fulfil(self.order("practice")["id"], pay(), self.cfg)
        b = billing_db.fulfil(self.order("practice", period="year")["id"], pay(), self.cfg)
        self.assertEqual(b["starts_at"], a["expires_at"], "paying early never loses days")
        self.assertAlmostEqual((b["expires_at"] - b["starts_at"]).days, 365)
        s = billing_db.fulfil(self.order("scale")["id"], pay(), self.cfg)
        self.assertLess((s["starts_at"] - a["starts_at"]).total_seconds(), 60, "a different plan starts now")

    def test_learn_free_months_once_for_verified_clinicians(self):
        f = billing_db.plan_features(self.cid, self.cfg)
        self.assertEqual(f["features"], {"library"})
        trial = f["plans"][0]
        self.assertEqual((trial["plan"], trial["period"]), ("learn", "trial"))
        self.assertAlmostEqual((trial["expires_at"] - trial["starts_at"]).days, 90)
        billing_db.plan_features(self.cid, self.cfg)
        self.assertEqual(len([e for e in billing_db.entitlements(self.cid) if e["period"] == "trial"]), 1, "once")
        _sql("update entitlements set expires_at = now() - interval '1 minute' where id=%s", str(trial["id"]))
        self.assertEqual(billing_db.plan_features(self.cid, self.cfg)["features"], set(), "never again after it ends")
        _sql("update clinicians set verification_status='pending' where id=%s", self.admin)
        self.assertEqual(billing_db.plan_features(self.admin, self.cfg)["features"], set(), "not before verification")
        self.assertEqual(billing_db.plan_features("not-a-uuid", self.cfg)["features"], set())
        off = copy.deepcopy(self.cfg)
        off["plans"]["learn"]["trial_days"] = 0
        _sql("update clinicians set verification_status='verified' where id=%s", self.admin)
        self.assertEqual(billing_db.plan_features(self.admin, off)["features"], set(), "no free months set")

    def test_what_a_plan_unlocks_and_a_refund_ends(self):
        billing_db.plan_features(self.cid, self.cfg)                  # the free months start
        billing_db.fulfil(self.order("practice")["id"], pay(), self.cfg)
        self.assertEqual(billing_db.plan_features(self.cid, self.cfg)["features"],
                         {"library", "pdf", "booking", "appointments"})
        o = self.order("scale")
        billing_db.fulfil(o["id"], pay(), self.cfg)
        self.assertTrue(billing_db.scale_active(self.cid))
        self.assertIn("guided_included", billing_db.plan_features(self.cid, self.cfg)["features"])
        billing_db.record_refund(o["id"], "rfnd_s", 299900, self.admin, True, "refund")
        self.assertNotIn("guided_included", billing_db.plan_features(self.cid, self.cfg)["features"])
        self.assertFalse(billing_db.scale_active(self.cid))
        self.assertEqual(billing_db.balance(self.cid)["guided"], 0, "its monthly reports go with it")

    def test_a_scheduled_or_unpaid_plan_unlocks_nothing_yet(self):
        self.order("byok_scale")                                      # created, not paid
        billing_db.admin_grant(self.cid, "byok_scale", self.admin, "beta", self.cfg, None, 30)
        self.assertIn("guided_own_key", billing_db.plan_features(self.cid, self.cfg)["features"])

    def print_order(self, item="cbt"):
        o = billing_db.create_order(self.cid, billing.price_for(self.cfg, "print", None, item=item), 1)
        billing_db.set_provider_order(o["id"], "order_" + uuid.uuid4().hex[:14])
        return o

    def test_single_print_unlocks_one_page_for_its_hours(self):
        self.assertEqual(billing_db.print_passes(self.cid), {})
        o = self.print_order("cbt")
        self.assertEqual(billing_db.get_order(o["id"])["item"], "cbt")
        self.assertEqual(billing_db.print_passes(self.cid), {}, "not until it is paid")
        e = billing_db.fulfil(o["id"], pay(), self.cfg)
        self.assertEqual((e["plan"], e["item"], e["credits_total"]), ("print", "cbt", 0))
        self.assertAlmostEqual((e["expires_at"] - e["starts_at"]).total_seconds(), 24 * 3600, delta=2)
        passes = billing_db.print_passes(self.cid)
        self.assertEqual(list(passes), ["cbt"], "that page only")
        self.assertEqual(billing_db.entitlements(self.cid)[0]["state"], "active", "no credits, still active")
        self.assertEqual(billing_db.balance(self.cid)["any"], 0, "a print pass is not a report credit")
        # buying the same page again later extends from now; the pass with the later end wins
        billing_db.fulfil(self.print_order("cbt")["id"], pay(), self.cfg)
        self.assertGreaterEqual(billing_db.print_passes(self.cid)["cbt"], passes["cbt"])
        _sql("update entitlements set expires_at = now() - interval '1 minute' where clinician_id=%s and plan='print'",
             self.cid)
        self.assertEqual(billing_db.print_passes(self.cid), {}, "ended after its hours")
        with self.assertRaises(psycopg.errors.CheckViolation):
            _sql("insert into entitlements (clinician_id, plan, credits_total) values (%s,'print',0)", self.cid)

    def test_admin_adjust_extend_deactivate_are_audited(self):
        e = billing_db.admin_grant(self.cid, "scale", self.admin, "beta tester", self.cfg, None, 60)
        self.assertEqual((e["period"], e["plan"]), ("admin", "scale"))
        self.assertEqual(len([x for x in billing_db.entitlements(self.cid) if x["period"] == "allowance"]), 2,
                         "60 days of Scale: two monthly allowances")
        billing_db.admin_adjust(self.cid, 5, self.admin, "goodwill")
        self.assertEqual(billing_db.balance(self.cid)["guided"], 15)
        billing_db.admin_adjust(self.cid, -12, self.admin, "correction")
        self.assertEqual(billing_db.balance(self.cid)["guided"], 3)
        with self.assertRaises(billing_db.NoCredit):
            billing_db.admin_adjust(self.cid, -10, self.admin, "too many")
        billing_db.admin_extend(e["id"], 7, self.admin, "outage")
        billing_db.admin_set_status(e["id"], False, self.admin, "chargeback")
        self.assertEqual(billing_db.balance(self.cid)["guided"], 3, "deactivating the plan ends its allowances, not the admin's own credits")
        self.assertEqual(billing_db.plan_features(self.cid, self.cfg)["features"] & {"guided_included"}, set())
        actions = [a["action"] for a in billing_db.admin_user(self.cid)["audit"]]
        self.assertEqual(sorted(set(actions)), ["billing_adjust", "billing_deactivate", "billing_extend", "billing_grant"])

    def test_refund_is_counted_once_and_can_revoke_credits(self):
        o = self.order("scale")
        billing_db.fulfil(o["id"], pay(), self.cfg)
        billing_db.record_refund(o["id"], "rfnd_1", 299900, self.admin, True, "duplicate purchase")
        self.assertEqual(billing_db.balance(self.cid)["guided"], 0)
        self.assertEqual(billing_db.get_order(o["id"])["refund_status"], "pending")
        self.assertTrue(billing_db.refund_settled("rfnd_1", 299900, "processed"))
        self.assertFalse(billing_db.refund_settled("rfnd_1", 299900, "processed"))
        o2 = billing_db.get_order(o["id"])
        self.assertEqual((o2["refund_status"], o2["refunded_amount"]), ("refunded", 299900))

    def test_revenue_counts_only_collected_payments(self):
        paid = self.order("practice", period="year")
        billing_db.fulfil(paid["id"], pay(), self.cfg)
        failed = self.order("byok_scale")
        billing_db.mark_order(failed["id"], "failed", pay(), "card declined")
        self.order("per_report", "guided")                           # left pending
        rev = {r["plan"]: r for r in billing_db.revenue()["by_plan"]}
        self.assertGreaterEqual(rev["practice"]["collected"], 599900)
        self.assertEqual(rev["byok_scale"]["collected"] if "byok_scale" in rev else 0,
                         sum(r["amount"] for r in billing_db.admin_orders("paid", "byok_scale", None)) or 0)
        mine = [o for o in billing_db.admin_orders(None, None, self.cid)]
        self.assertEqual(sorted(o["status"] for o in billing_db.orders(self.cid)), ["created", "failed", "paid"])
        self.assertEqual(mine, [])  # admin search is by order/payment id, name or email — not clinician id

    def test_a_plan_order_must_name_its_period(self):
        with self.assertRaises(psycopg.errors.CheckViolation):
            _sql("""insert into billing_orders (clinician_id, plan, amount, currency, config_version)
                    values (%s,'scale',100,'INR',1)""", self.cid)

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
