"""Pricing, payments and "use my own key" over HTTP, against a real Postgres (migration 006) and a
fake Razorpay server (httpx MockTransport). The app runs in DEV_MODE with its fake keyless model;
only the billing store is the real database. Skipped without TEST_DATABASE_URL.

What must hold:
- a report is never charged unless it is delivered, and never twice;
- a payment counts only when the signature is valid AND Razorpay reports it captured for the
  right order and amount; the app's word is never enough;
- a webhook delivered twice grants once;
- the clinician's own key is never returned, never stored in clear, and a failure with it never
  falls back to the platform key;
- only admins change prices, and switching off a plan that people use needs a confirmation."""
import base64
import copy
import hashlib
import hmac
import importlib.util
import json
import os
import unittest
import uuid
from types import SimpleNamespace

URL = os.environ.get("TEST_DATABASE_URL", "")
HAVE = bool(URL) and all(importlib.util.find_spec(m) for m in ("fastapi", "httpx", "psycopg", "cryptography",
                                                                "anthropic"))

if HAVE:
    os.environ["DEV_MODE"] = "1"
    import anthropic
    import httpx
    import psycopg
    from fastapi.testclient import TestClient

    from app import billing, billing_db, byok, db, main
    from app.pipeline import Pipeline
    from app.razorpay import Razorpay
    db._DSN = URL

KEY_SECRET, WEBHOOK_SECRET = "test_key_secret", "test_webhook_secret"
OWN_KEY = "sk-ant-api03-" + "x" * 80 + "AbCd"
CASE = "34F, panic attacks for 4 weeks, sudden onset, avoids the metro. Asked and absent for risk."


def sign(order_id, payment_id):
    return hmac.new(KEY_SECRET.encode(), f"{order_id}|{payment_id}".encode(), hashlib.sha256).hexdigest()


class FakeRazorpay:
    """Just enough of Razorpay's REST API: orders, payments (set by the test), refunds."""

    def __init__(self):
        self.orders, self.payments, self.refunds = {}, {}, []

    def pay(self, order_id, status="captured", amount=None):
        o = self.orders[order_id]
        pid = "pay_" + uuid.uuid4().hex[:14]
        self.payments[pid] = {"id": pid, "order_id": order_id, "amount": o["amount"] if amount is None else amount,
                              "currency": o["currency"], "status": status}
        return pid

    def handler(self, request):
        path, body = request.url.path, json.loads(request.content or b"{}")
        if request.headers.get("authorization") != "Basic " + base64.b64encode(f"rzp_test_x:{KEY_SECRET}".encode()).decode():
            return httpx.Response(401, json={"error": {"description": "auth"}})
        if request.method == "POST" and path == "/v1/orders":
            oid = "order_" + uuid.uuid4().hex[:14]
            self.orders[oid] = {"id": oid, "amount": body["amount"], "currency": body["currency"], "status": "created"}
            return httpx.Response(200, json=self.orders[oid])
        if request.method == "GET" and path.startswith("/v1/payments/"):
            p = self.payments.get(path.rsplit("/", 1)[1])
            return httpx.Response(200, json=p) if p else httpx.Response(404, json={"error": {"description": "no"}})
        if request.method == "GET" and path.endswith("/payments"):
            oid = path.split("/")[3]
            return httpx.Response(200, json={"items": [p for p in self.payments.values() if p["order_id"] == oid]})
        if request.method == "POST" and path.endswith("/refund"):
            r = {"id": "rfnd_" + uuid.uuid4().hex[:14], "amount": body["amount"], "status": "processed"}
            self.refunds.append(r)
            return httpx.Response(200, json=r)
        return httpx.Response(404, json={"error": {"description": "unknown"}})


class OwnKeyModel:
    """Stands in for AnthropicClient built with the clinician's own key."""

    def __init__(self, api_key, fail=None):
        self.api_key, self.fail, self.calls = api_key, fail, 0
        self.inner = main._FakeDevModel(main.CFG.skill_dir)
        self.model = "own-key"

    def run(self, *a, **kw):
        self.calls += 1
        if self.fail:
            raise self.fail
        return self.inner.run(*a, **kw)


class PlatformMustNotRun:
    model = "platform"

    def run(self, *a, **kw):
        raise AssertionError("the platform key was used for an own-key report")

    run_structured = run


def anthropic_error(cls, status):
    req = httpx.Request("POST", "https://api.anthropic.com/v1/messages")
    return cls("nope", response=httpx.Response(status, request=req), body=None)


@unittest.skipUnless(HAVE, "TEST_DATABASE_URL not set")
class BillingApiTests(unittest.TestCase):
    def setUp(self):
        self.cid, self.admin_id = str(uuid.uuid4()), str(uuid.uuid4())
        with psycopg.connect(URL, autocommit=True) as c:
            for i, (who, adm) in enumerate(((self.cid, False), (self.admin_id, True))):
                c.execute("insert into auth.users (id, email) values (%s,%s)", (who, f"a{i}-{who[:6]}@test"))
                c.execute("""insert into clinicians (id, role, registration_body, level, verification_status,
                               consent_version, is_admin) values (%s,'psychologist','RCI','L2','verified','v1',%s)""",
                          (who, adm))
        self.who = self.cid
        clin = lambda: {**db.get_clinician(self.who), "id": self.who}   # noqa: E731

        def adm():
            row = db.get_clinician(self.who)
            if not row.get("is_admin"):
                raise main.HTTPException(403, "admin only")
            return {**row, "id": self.who}
        main.app.dependency_overrides[main.verified_clinician] = clin
        main.app.dependency_overrides[main.admin] = adm
        main.app.dependency_overrides[main.current_user] = lambda: {"id": self.who}

        svc = main.BILLING
        self.saved = (svc.cfg, svc.store, svc.store_on, svc.razorpay, svc.vault, svc.model_factory, main.PIPELINE)
        svc.cfg = SimpleNamespace(
            razorpay_key_id="rzp_test_x", razorpay_key_secret=KEY_SECRET, razorpay_webhook_secret=WEBHOOK_SECRET,
            razorpay_configured=True, claude_model="claude-test", byok_encryption_key="", byok_key_version=1)
        svc.store, svc.store_on = billing_db, (lambda: True)
        self.rzp = FakeRazorpay()
        svc.razorpay = Razorpay("rzp_test_x", KEY_SECRET, transport=httpx.MockTransport(self.rzp.handler))
        svc.vault = byok.Vault.from_secrets(base64.b64encode(os.urandom(32)).decode())
        self.own = []
        svc.model_factory = lambda key: self.own[-1] if self.own and self.own[-1].api_key == key else OwnKeyModel(key)
        self.configure({"enabled": False})
        main._dev_history = main.DevHistoryStore()
        main._dev_consults = main.DevConsultationStore()
        self.client = TestClient(main.app)

    def tearDown(self):
        main.app.dependency_overrides.clear()
        svc = main.BILLING
        svc.cfg, svc.store, svc.store_on, svc.razorpay, svc.vault, svc.model_factory, main.PIPELINE = self.saved
        svc.forget_config()

    # --- helpers --------------------------------------------------------------------------
    def configure(self, cfg):
        billing_db.save_config(billing.validate(cfg), self.admin_id, {"test": [None, None]})
        main.BILLING.forget_config()

    def consult(self, **extra):
        return self.client.post("/v1/consult", json={"text": CASE, "deid_attested": True, "mode": "B", **extra})

    def buy(self, plan, report_type=None):
        r = self.client.post("/v1/billing/orders", json={"plan": plan, "report_type": report_type})
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()

    def verify(self, order, payment_id, signature=None):
        rid = order["checkout"]["order_id"]
        return self.client.post(f"/v1/billing/orders/{order['order']['id']}/verify",
                                json={"razorpay_order_id": rid, "razorpay_payment_id": payment_id,
                                      "razorpay_signature": signature or sign(rid, payment_id)})

    def balance(self):
        return billing_db.balance(self.cid)

    def webhook(self, event, entity_key, entity, event_id=None, secret=WEBHOOK_SECRET):
        raw = json.dumps({"event": event, "payload": {entity_key: {"entity": entity}}}).encode()
        sig = hmac.new(secret.encode(), raw, hashlib.sha256).hexdigest()
        return self.client.post("/v1/payments/razorpay/webhook", content=raw,
                                headers={"X-Razorpay-Signature": sig, "X-Razorpay-Event-Id": event_id or uuid.uuid4().hex,
                                         "Content-Type": "application/json"})

    # --- reports with pricing off / on ----------------------------------------------------
    def test_pricing_off_reports_stay_free(self):
        r = self.consult()
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["status"], "delivered")
        self.assertEqual(billing_db.ledger(self.cid), [])
        self.assertFalse(self.client.get("/v1/billing/plans").json()["enabled"])

    def test_no_credit_means_402_and_nothing_is_generated(self):
        self.configure({"enabled": True})
        main.PIPELINE = Pipeline(main.SKILL, PlatformMustNotRun(), main.ICD)
        r = self.consult()
        self.assertEqual(r.status_code, 402)
        self.assertEqual(r.json()["detail"]["error"], "payment_required")
        self.assertEqual(r.json()["detail"]["price"], 9900, "the price comes from the admin's configuration")

    def test_buy_one_report_then_spend_it(self):
        self.configure({"enabled": True})
        o = self.buy("per_report", "direct")
        self.assertEqual(o["order"]["amount"], 9900)
        self.assertEqual(o["checkout"]["key"], "rzp_test_x")
        self.assertNotIn(KEY_SECRET, json.dumps(o))
        pid = self.rzp.pay(o["checkout"]["order_id"])
        r = self.verify(o, pid)
        self.assertEqual(r.json()["order"]["status"], "paid", r.text)
        self.verify(o, pid)                                              # reported twice
        self.assertEqual(self.balance()["direct"], 1)
        r = self.consult(request_id="req-0001")
        self.assertEqual(r.json()["status"], "delivered")
        self.assertEqual(self.balance()["direct"], 0)
        self.assertEqual(self.consult().status_code, 402)

    def test_a_retried_request_is_not_charged_twice(self):
        self.configure({"enabled": True})
        billing_db.admin_adjust(self.cid, 2, self.admin_id, "test")
        self.assertEqual(self.consult(request_id="same-request").status_code, 200)
        r = self.consult(request_id="same-request")
        self.assertEqual(r.status_code, 409)
        self.assertEqual(r.json()["detail"]["error"], "already_charged")
        self.assertEqual(self.balance()["any"], 1)

    def test_held_back_report_costs_nothing(self):
        self.configure({"enabled": True})
        billing_db.admin_adjust(self.cid, 1, self.admin_id, "test")

        class Junk:
            model = "junk"

            def run(self, *a, **kw):
                from app.pipeline import ModelResult
                return ModelResult(text="no contract line", model="junk", usage={})
        main.PIPELINE = Pipeline(main.SKILL, Junk(), main.ICD)
        r = self.consult()
        self.assertEqual(r.json()["status"], "blocked")
        self.assertEqual(self.balance()["any"], 1)

    def test_identifiers_refused_without_charge(self):
        self.configure({"enabled": True})
        billing_db.admin_adjust(self.cid, 1, self.admin_id, "test")
        r = self.client.post("/v1/consult", json={"text": "Call her on 9876543210 today please", "deid_attested": True})
        self.assertEqual(r.status_code, 422)
        self.assertEqual(self.balance()["any"], 1)

    def test_guided_report_spends_one_guided_credit_once(self):
        self.configure({"enabled": True})
        v = self.client.post("/v1/consultations", json={"text": CASE, "deid_attested": True}).json()
        r = self.client.post(f"/v1/consultations/{v['id']}/report", json={"force": True})
        self.assertEqual(r.status_code, 402)
        o = self.buy("per_report", "guided")
        self.verify(o, self.rzp.pay(o["checkout"]["order_id"]))
        r = self.client.post(f"/v1/consultations/{v['id']}/report", json={"force": True})
        self.assertEqual(r.json()["reply"]["status"], "delivered", r.text)
        again = self.client.post(f"/v1/consultations/{v['id']}/report", json={"force": True})
        self.assertEqual(again.status_code, 200, "the written report is returned, not charged again")
        self.assertEqual(self.balance()["guided"], 0)
        self.assertEqual([x["kind"] for x in billing_db.ledger(self.cid)].count("consume"), 1)

    # --- payment verification ---------------------------------------------------------------
    def test_bad_signature_or_unpaid_or_wrong_amount_grants_nothing(self):
        self.configure({"enabled": True})
        o = self.buy("sub_30")
        pid = self.rzp.pay(o["checkout"]["order_id"])
        r = self.verify(o, pid, signature="0" * 64)
        self.assertEqual(r.status_code, 400)
        self.assertEqual(r.json()["detail"]["error"], "invalid_signature")
        o2 = self.buy("sub_30")
        r = self.verify(o2, self.rzp.pay(o2["checkout"]["order_id"], status="authorized"))
        self.assertEqual(r.json()["order"]["status"], "pending", "authorised but not captured is not paid")
        o3 = self.buy("sub_30")
        r = self.verify(o3, self.rzp.pay(o3["checkout"]["order_id"], amount=100))
        self.assertEqual(r.status_code, 400)
        o4 = self.buy("sub_30")
        r = self.verify(o4, self.rzp.pay(o4["checkout"]["order_id"], status="failed"))
        self.assertEqual(r.json()["order"]["status"], "failed")
        self.assertEqual(self.balance()["any"], 0)
        mine = {x["status"] for x in self.client.get("/v1/billing/orders").json()["orders"]}
        self.assertNotIn("paid", mine)

    def test_signature_from_another_order_is_refused(self):
        self.configure({"enabled": True})
        a, b = self.buy("per_report", "guided"), self.buy("sub_50")
        pid = self.rzp.pay(a["checkout"]["order_id"])                    # paid ₹199 …
        r = self.client.post(f"/v1/billing/orders/{b['order']['id']}/verify",   # … claimed for the ₹2,999 plan
                             json={"razorpay_order_id": a["checkout"]["order_id"], "razorpay_payment_id": pid,
                                   "razorpay_signature": sign(a["checkout"]["order_id"], pid)})
        self.assertEqual(r.status_code, 400)
        self.assertEqual(self.balance()["any"], 0)

    def test_payment_the_app_never_reported_is_found_by_polling(self):
        self.configure({"enabled": True})
        o = self.buy("sub_50")
        self.rzp.pay(o["checkout"]["order_id"])
        r = self.client.get(f"/v1/billing/orders/{o['order']['id']}")
        self.assertEqual(r.json()["order"]["status"], "paid")
        self.assertEqual(self.balance()["any"], 50)

    def test_webhook_is_signed_and_applied_once(self):
        self.configure({"enabled": True})
        o = self.buy("sub_30")
        pid = self.rzp.pay(o["checkout"]["order_id"])
        entity = dict(self.rzp.payments[pid])
        self.assertEqual(self.webhook("payment.captured", "payment", entity, secret="wrong").status_code, 400)
        self.assertEqual(self.balance()["any"], 0)
        r = self.webhook("payment.captured", "payment", entity, event_id="evt_same_" + pid)
        self.assertEqual(r.json(), {"ok": True})
        r = self.webhook("payment.captured", "payment", entity, event_id="evt_same_" + pid)
        self.assertTrue(r.json()["duplicate"])
        self.webhook("order.paid", "payment", entity)                   # a second event for the same payment
        self.verify(o, pid)                                              # and the app's own report
        self.assertEqual(self.balance()["any"], 30)

    def test_failed_webhook_and_cancel_leave_no_credit(self):
        self.configure({"enabled": True})
        o = self.buy("sub_30")
        pid = self.rzp.pay(o["checkout"]["order_id"], status="failed")
        self.webhook("payment.failed", "payment", dict(self.rzp.payments[pid], error_description="declined"))
        self.assertEqual(billing_db.get_order(o["order"]["id"])["status"], "failed")
        o2 = self.buy("sub_30")
        self.assertTrue(self.client.post(f"/v1/billing/orders/{o2['order']['id']}/cancel").json()["cancelled"])
        self.assertEqual(self.balance()["any"], 0)

    def test_disabled_plan_cannot_be_bought_and_prices_are_server_side(self):
        c = billing.validate({"enabled": True})
        c["plans"]["sub_50"]["enabled"] = False
        self.configure(c)
        r = self.client.post("/v1/billing/orders", json={"plan": "sub_50"})
        self.assertEqual(r.status_code, 409)
        r = self.client.post("/v1/billing/orders", json={"plan": "sub_30", "amount": 1})
        self.assertEqual(r.json()["order"]["amount"], 199900, "an amount sent by the app is ignored")
        plans = self.client.get("/v1/billing/plans").json()
        self.assertEqual([p["id"] for p in plans["plans"]], ["per_report", "sub_30"])

    # --- own Anthropic key -----------------------------------------------------------------------
    def byok_on(self, **plan):
        self.configure({"enabled": True, "plans": {"byok": {"enabled": True, **plan}}})

    def save_key(self, outcome=None):
        orig = byok.check_key

        def fake(key, model):
            if outcome:
                raise byok.ByokError(outcome)
        byok.check_key = fake
        try:
            return self.client.put("/v1/billing/byok", json={"api_key": OWN_KEY})
        finally:
            byok.check_key = orig

    def test_own_key_is_checked_sealed_and_never_returned(self):
        self.byok_on()
        r = self.save_key("invalid_key")
        self.assertEqual(r.status_code, 422)
        self.assertIsNone(billing_db.byok_get(self.cid))
        r = self.save_key()
        self.assertEqual(r.json(), {"connected": True, "status": "valid", "last4": "AbCd"})
        stored = billing_db.byok_get(self.cid)
        self.assertNotIn(OWN_KEY.encode(), bytes(stored["ciphertext"]))
        everything = json.dumps(self.client.get("/v1/billing/me").json()) + json.dumps(
            self.client.get("/v1/billing/ledger").json())
        self.assertNotIn(OWN_KEY, everything)
        self.assertNotIn("x" * 20, everything)
        self.who = self.admin_id
        admin_view = json.dumps(self.client.get(f"/v1/admin/billing/users/{self.cid}").json(), default=str)
        self.assertNotIn(OWN_KEY, admin_view)
        self.assertNotIn("ciphertext", admin_view)

    def test_own_key_report_uses_only_that_key_and_spends_no_credit(self):
        self.byok_on()
        self.save_key()
        main.PIPELINE = Pipeline(main.SKILL, PlatformMustNotRun(), main.ICD)
        self.own.append(OwnKeyModel(OWN_KEY))
        r = self.consult(use_own_key=True)
        self.assertEqual(r.json()["status"], "delivered", r.text)
        self.assertEqual(self.own[-1].calls, 1)
        self.assertEqual([x["kind"] for x in billing_db.ledger(self.cid)], [], "BYOK spends no credit by default")
        with psycopg.connect(URL) as c:
            used = c.execute("select report_type, outcome from byok_usage where clinician_id=%s", (self.cid,)).fetchall()
        self.assertEqual(used, [("direct", "ok")], "admins see usage counts, never the key")
        self.assertIn("ok", {u["outcome"] for u in billing_db.byok_stats(1)["usage"]})

    def test_own_key_failure_never_falls_back_to_the_platform_key(self):
        self.byok_on()
        self.save_key()
        main.PIPELINE = Pipeline(main.SKILL, PlatformMustNotRun(), main.ICD)
        for exc, code, retry in ((anthropic_error(anthropic.RateLimitError, 429), "rate_limited", True),
                                 (anthropic_error(anthropic.AuthenticationError, 401), "invalid_key", False)):
            self.own.append(OwnKeyModel(OWN_KEY, fail=exc))
            r = self.consult(use_own_key=True)
            self.assertEqual(r.status_code, 424, r.text)
            self.assertEqual((r.json()["detail"]["code"], r.json()["detail"]["retry"]), (code, retry))
            self.assertNotIn(OWN_KEY, r.text)
        self.assertEqual(billing_db.byok_get(self.cid)["status"], "invalid")
        r = self.consult(use_own_key=True)
        self.assertEqual(r.json()["detail"]["code"], "invalid_key", "a key known to be bad is not tried again")

    def test_own_key_with_platform_fee_and_credits(self):
        self.byok_on(fee=9900, consumes_credits=True)
        self.save_key()
        r = self.consult(use_own_key=True)
        self.assertEqual((r.status_code, r.json()["detail"]["plan"]), (402, "byok"))
        o = self.buy("byok")
        self.verify(o, self.rzp.pay(o["checkout"]["order_id"]))
        self.assertEqual(self.consult(use_own_key=True).status_code, 402, "this setup also needs a credit")
        billing_db.admin_adjust(self.cid, 1, self.admin_id, "test")
        self.own.append(OwnKeyModel(OWN_KEY))
        self.assertEqual(self.consult(use_own_key=True).json()["status"], "delivered")
        self.assertEqual(self.balance()["any"], 0)

    def test_encryption_key_rotation_keeps_saved_keys_working(self):
        old = base64.b64encode(os.urandom(32)).decode()
        main.BILLING.vault = byok.Vault.from_secrets(old)
        self.byok_on()
        self.save_key()
        main.BILLING.vault = byok.Vault.from_secrets(base64.b64encode(os.urandom(32)).decode(), old, 2)
        self.own.append(OwnKeyModel(OWN_KEY))
        self.assertEqual(self.consult(use_own_key=True).json()["status"], "delivered")
        self.assertEqual(billing_db.byok_get(self.cid)["key_version"], 2, "sealed again under the new key")
        main.BILLING.vault = byok.Vault.from_secrets(base64.b64encode(os.urandom(32)).decode(), "", 3)
        r = self.consult(use_own_key=True)                              # the encryption key was lost
        self.assertEqual((r.status_code, r.json()["detail"]["code"]), (424, "not_configured"))

    def test_own_key_not_offered_when_switched_off(self):
        self.configure({"enabled": True})
        self.assertEqual(self.save_key().status_code, 409)
        self.assertEqual(self.consult(use_own_key=True).status_code, 409)

    # --- admin -------------------------------------------------------------------------------
    def test_only_admins_change_pricing(self):
        self.assertEqual(self.client.get("/v1/admin/pricing").status_code, 403)
        self.assertEqual(self.client.put("/v1/admin/pricing", json={"config": {"enabled": True}}).status_code, 403)
        self.assertEqual(self.client.get("/v1/admin/payments/summary").status_code, 403)

    def test_pricing_change_is_validated_confirmed_and_audited(self):
        self.configure({"enabled": True})
        o = self.buy("sub_30")
        self.verify(o, self.rzp.pay(o["checkout"]["order_id"]))
        self.who = self.admin_id
        cfg = self.client.get("/v1/admin/pricing").json()["config"]
        bad = copy.deepcopy(cfg)
        bad["plans"]["sub_30"]["price"] = -5
        r = self.client.put("/v1/admin/pricing", json={"config": bad})
        self.assertEqual(r.status_code, 422)
        off = copy.deepcopy(cfg)
        off["plans"]["sub_30"]["enabled"] = False
        r = self.client.put("/v1/admin/pricing", json={"config": off})
        self.assertEqual(r.status_code, 409)
        self.assertGreaterEqual(r.json()["detail"]["affected"]["sub_30"], 1)
        r = self.client.put("/v1/admin/pricing", json={"config": off, "confirm_disable": True})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["changes"], {"plans.sub_30.enabled": [True, False]})
        with psycopg.connect(URL) as c:
            row = c.execute("select actor_id, detail from admin_audit where action='pricing_config' "
                            "order by created_at desc limit 1").fetchone()
        self.assertEqual((str(row[0]), row[1]["changes"]), (self.admin_id, {"plans.sub_30.enabled": [True, False]}))
        hist = self.client.get("/v1/admin/pricing/history").json()["history"]
        self.assertEqual(hist[0]["detail"]["changes"], {"plans.sub_30.enabled": [True, False]})
        self.assertTrue(hist[0]["actor_email"].endswith("@test"))
        self.who = self.cid
        self.assertEqual(self.balance()["any"], 30, "people already on the plan keep it")

    def test_paid_plans_need_razorpay_keys(self):
        main.BILLING.cfg.razorpay_configured = False
        self.who = self.admin_id
        r = self.client.put("/v1/admin/pricing", json={"config": billing.validate({"enabled": True})})
        self.assertEqual(r.json()["detail"]["error"], "payments_unavailable")

    def test_admin_adjust_needs_a_reason_and_refund_goes_through_razorpay(self):
        self.configure({"enabled": True})
        o = self.buy("sub_30")
        self.verify(o, self.rzp.pay(o["checkout"]["order_id"]))
        self.who = self.admin_id
        r = self.client.post(f"/v1/admin/billing/users/{self.cid}/adjust", json={"delta": 3, "reason": ""})
        self.assertEqual(r.status_code, 422)
        r = self.client.post(f"/v1/admin/billing/users/{self.cid}/adjust", json={"delta": 3, "reason": "goodwill"})
        self.assertEqual(r.json()["balance"]["any"], 33)
        r = self.client.post(f"/v1/admin/payments/{o['order']['id']}/refund", json={"reason": "asked to cancel"})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["order"]["refund_status"], "refunded")
        self.assertEqual(len(self.rzp.refunds), 1)
        again = self.client.post(f"/v1/admin/payments/{o['order']['id']}/refund", json={"reason": "again"})
        self.assertEqual(again.status_code, 422, "nothing left to refund")
        self.assertEqual(billing_db.balance(self.cid)["any"], 3, "the refunded plan's credits are withdrawn")


if __name__ == "__main__":
    unittest.main()
