"""Plans, payments and "use my own key" over HTTP, against a real Postgres (migrations 006-012) and a
fake Razorpay server (httpx MockTransport). The app runs in DEV_MODE with its fake keyless model;
only the billing store is the real database. Skipped without TEST_DATABASE_URL.

What must hold:
- a report is never charged unless it is delivered, and never twice;
- a payment counts only when the signature is valid AND Razorpay reports it captured for the
  right order and amount; the app's word is never enough;
- a webhook delivered twice grants once;
- the clinician's own key is never returned, never stored in clear, and a failure with it never
  falls back to the platform key;
- only admins change prices, and switching off a plan that people use needs a confirmation;
- each plan unlocks only what it includes (library, PDF, booking page, appointments, AI-Guided)."""
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
from urllib.parse import urlsplit

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

    def _sql_exec(q, *a):
        with psycopg.connect(URL, autocommit=True) as c:
            c.execute(q, a)
    db._DSN = URL

KEY_SECRET, WEBHOOK_SECRET = "test_key_secret", "test_webhook_secret"
FUNNEL_SECRET = "funnel_secret_123"
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
            razorpay_configured=True, claude_model="claude-test", byok_encryption_key="", byok_key_version=1,
            funnel_webhook_secret=FUNNEL_SECRET)
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

    def buy(self, plan, report_type=None, period=None):
        if plan in billing.TIERS and period is None:
            period = "month"
        r = self.client.post("/v1/billing/orders", json={"plan": plan, "report_type": report_type, "period": period})
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

    def start_guided(self):
        return self.client.post("/v1/consultations", json={"text": CASE, "deid_attested": True})

    def guided_report(self, **extra):
        v = self.start_guided()
        self.assertEqual(v.status_code, 200, v.text)
        return self.client.post(f"/v1/consultations/{v.json()['id']}/report", json={"force": True, **extra})

    def test_guided_report_spends_one_guided_credit_once(self):
        self.configure({"enabled": True})
        r = self.start_guided()
        self.assertEqual(r.status_code, 402, "Learn's free months don't include AI-Guided Case Taking")
        self.assertEqual((r.json()["detail"]["error"], r.json()["detail"]["feature"]), ("plan_required", "guided"))
        self.assertEqual(r.json()["detail"]["price"], 19900, "a single guided report is offered")
        o = self.buy("per_report", "guided")
        self.verify(o, self.rzp.pay(o["checkout"]["order_id"]))
        v = self.start_guided().json()
        r = self.client.post(f"/v1/consultations/{v['id']}/report", json={"force": True})
        self.assertEqual(r.json()["reply"]["status"], "delivered", r.text)
        again = self.client.post(f"/v1/consultations/{v['id']}/report", json={"force": True})
        self.assertEqual(again.status_code, 200, "the written report is returned, not charged again")
        self.assertEqual(self.balance()["guided"], 0)
        self.assertEqual([x["kind"] for x in billing_db.ledger(self.cid)].count("consume"), 1)

    # --- payment verification ---------------------------------------------------------------
    def test_bad_signature_or_unpaid_or_wrong_amount_grants_nothing(self):
        self.configure({"enabled": True})
        o = self.buy("scale")
        pid = self.rzp.pay(o["checkout"]["order_id"])
        r = self.verify(o, pid, signature="0" * 64)
        self.assertEqual(r.status_code, 400)
        self.assertEqual(r.json()["detail"]["error"], "invalid_signature")
        o2 = self.buy("scale")
        r = self.verify(o2, self.rzp.pay(o2["checkout"]["order_id"], status="authorized"))
        self.assertEqual(r.json()["order"]["status"], "pending", "authorised but not captured is not paid")
        o3 = self.buy("scale", period="year")
        r = self.verify(o3, self.rzp.pay(o3["checkout"]["order_id"], amount=100))
        self.assertEqual(r.status_code, 400)
        o4 = self.buy("practice")
        r = self.verify(o4, self.rzp.pay(o4["checkout"]["order_id"], status="failed"))
        self.assertEqual(r.json()["order"]["status"], "failed")
        self.assertEqual(self.balance()["guided"], 0)
        self.assertEqual(billing_db.plan_features(self.cid, main.BILLING.config()[1])["features"], {"library"},
                         "only the free months")
        mine = {x["status"] for x in self.client.get("/v1/billing/orders").json()["orders"]}
        self.assertNotIn("paid", mine)

    def test_signature_from_another_order_is_refused(self):
        self.configure({"enabled": True})
        a, b = self.buy("per_report", "guided"), self.buy("scale", period="year")
        pid = self.rzp.pay(a["checkout"]["order_id"])                    # paid ₹199 …
        r = self.client.post(f"/v1/billing/orders/{b['order']['id']}/verify",   # … claimed for the ₹19,999 plan
                             json={"razorpay_order_id": a["checkout"]["order_id"], "razorpay_payment_id": pid,
                                   "razorpay_signature": sign(a["checkout"]["order_id"], pid)})
        self.assertEqual(r.status_code, 400)
        self.assertEqual(self.balance()["guided"], 0)

    def test_payment_the_app_never_reported_is_found_by_polling(self):
        self.configure({"enabled": True})
        o = self.buy("scale")
        self.rzp.pay(o["checkout"]["order_id"])
        r = self.client.get(f"/v1/billing/orders/{o['order']['id']}")
        self.assertEqual(r.json()["order"]["status"], "paid")
        self.assertEqual(self.balance()["guided"], 10)

    def test_webhook_is_signed_and_applied_once(self):
        self.configure({"enabled": True})
        o = self.buy("scale")
        pid = self.rzp.pay(o["checkout"]["order_id"])
        entity = dict(self.rzp.payments[pid])
        self.assertEqual(self.webhook("payment.captured", "payment", entity, secret="wrong").status_code, 400)
        self.assertEqual(self.balance()["guided"], 0)
        r = self.webhook("payment.captured", "payment", entity, event_id="evt_same_" + pid)
        self.assertEqual(r.json(), {"ok": True})
        r = self.webhook("payment.captured", "payment", entity, event_id="evt_same_" + pid)
        self.assertTrue(r.json()["duplicate"])
        self.webhook("order.paid", "payment", entity)                   # a second event for the same payment
        self.verify(o, pid)                                              # and the app's own report
        self.assertEqual(self.balance()["guided"], 10)

    def test_failed_webhook_and_cancel_leave_no_credit(self):
        self.configure({"enabled": True})
        o = self.buy("scale")
        pid = self.rzp.pay(o["checkout"]["order_id"], status="failed")
        self.webhook("payment.failed", "payment", dict(self.rzp.payments[pid], error_description="declined"))
        self.assertEqual(billing_db.get_order(o["order"]["id"])["status"], "failed")
        o2 = self.buy("scale")
        self.assertTrue(self.client.post(f"/v1/billing/orders/{o2['order']['id']}/cancel").json()["cancelled"])
        self.assertEqual(self.balance()["guided"], 0)

    def test_razorpay_refusing_the_order_records_its_reason(self):
        # Seen live: every purchase failed with only "could not create the Razorpay order" — no way to
        # tell wrong keys from an outage. Razorpay's own reason is kept (never the keys).
        self.configure({"enabled": True})
        main.BILLING.razorpay = Razorpay("rzp_test_x", "wrong-secret", transport=httpx.MockTransport(self.rzp.handler))
        r = self.client.post("/v1/billing/orders", json={"plan": "scale", "period": "month"})
        self.assertEqual(r.status_code, 502)
        o = billing_db.orders(self.cid)[0]
        self.assertEqual(o["status"], "failed")
        self.assertIn("Razorpay 401", o["failure_reason"])
        self.assertNotIn("wrong-secret", o["failure_reason"])
        self.assertNotIn("wrong-secret", r.text)

    def test_disabled_plan_cannot_be_bought_and_prices_are_server_side(self):
        c = billing.validate({"enabled": True})
        c["plans"]["practice"]["enabled"] = False
        self.configure(c)
        r = self.client.post("/v1/billing/orders", json={"plan": "practice", "period": "year"})
        self.assertEqual(r.status_code, 409)
        r = self.client.post("/v1/billing/orders", json={"plan": "scale", "period": "year", "amount": 1})
        self.assertEqual(r.json()["order"]["amount"], 1999900, "an amount sent by the app is ignored")
        self.assertEqual(r.json()["order"]["period"], "year")
        self.assertIn("Scale · yearly", r.json()["checkout"]["description"])
        for bad in ({"plan": "scale"}, {"plan": "scale", "period": "week"}, {"plan": "sub_30"}, {"plan": "byok"}):
            self.assertIn(self.client.post("/v1/billing/orders", json=bad).status_code, (409, 422), bad)
        plans = self.client.get("/v1/billing/plans").json()
        self.assertEqual([p["id"] for p in plans["plans"]], ["learn", "byok_scale", "scale", "per_report"])
        self.assertEqual(plans["rows"][4]["label"], "AI-Guided Case Taking")

    # --- single print (education pages) -------------------------------------------------------
    def paid(self, order):
        r = self.verify(order, self.rzp.pay(order["checkout"]["order_id"]))
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()["order"]

    def education(self):
        r = self.client.get("/v1/education")
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()

    def page(self, edu, slug):
        url = next(p["url"] for p in edu["pages"] if p["slug"] == slug)
        u = urlsplit(url)
        return self.client.get(u.path + "?" + u.query).text

    def test_pricing_off_everyone_prints_and_nothing_is_sold(self):
        edu = self.education()
        self.assertTrue(edu["can_print"])
        self.assertIn("var CAN_PRINT = true;", self.page(edu, "cbt"))
        r = self.client.post("/v1/billing/orders", json={"plan": "print", "item": "cbt"})
        self.assertEqual(r.status_code, 409, "pricing off: nothing to buy")

    def test_single_print_unlocks_that_page_for_24_hours(self):
        self.configure({"enabled": True})
        edu = self.education()
        self.assertFalse(edu["can_print"])
        self.assertEqual(edu["print_offer"], {"price": 4900, "currency": "INR", "hours": 24, "name": "Print one page"})
        self.assertIn("var CAN_PRINT = false;", self.page(edu, "cbt"))
        for bad in ({"plan": "print"}, {"plan": "print", "item": "no-such-page"}, {"plan": "print", "item": "../x"},
                    {"plan": "scale", "period": "month", "item": "cbt"}):
            self.assertIn(self.client.post("/v1/billing/orders", json=bad).status_code, (409, 422), bad)
        o = self.client.post("/v1/billing/orders", json={"plan": "print", "item": "cbt", "amount": 1}).json()
        self.assertEqual((o["order"]["amount"], o["order"]["item"]), (4900, "cbt"), "the price is the server's")
        self.assertIn("Cognitive Behavioural Therapy (CBT)", o["checkout"]["description"])
        self.assertEqual(self.paid(o)["status"], "paid")
        edu = self.education()
        cards = {p["slug"]: p for p in edu["pages"]}
        self.assertTrue(cards["cbt"]["can_print"])
        self.assertIsNotNone(cards["cbt"]["print_until"])
        self.assertFalse(cards["dbt"]["can_print"], "that page only")
        self.assertIn("var CAN_PRINT = true;", self.page(edu, "cbt"))
        self.assertIn("var CAN_PRINT = false;", self.page(edu, "dbt"))
        self.assertEqual(self.balance()["any"], 0, "no report credits")
        _sql_exec("update entitlements set expires_at = now() - interval '1 minute' where clinician_id=%s and plan='print'",
                  self.cid)
        self.assertFalse({p["slug"]: p for p in self.education()["pages"]}["cbt"]["can_print"], "ends after 24 hours")

    def test_a_plan_with_pdf_prints_every_page_and_is_not_sold_a_single_print(self):
        self.configure({"enabled": True})
        self.paid(self.buy("practice"))
        edu = self.education()
        self.assertTrue(edu["can_print"])
        self.assertIsNone(edu["print_offer"])
        self.assertIn("var CAN_PRINT = true;", self.page(edu, "dbt"))
        r = self.client.post("/v1/billing/orders", json={"plan": "print", "item": "cbt"})
        self.assertEqual(r.json()["detail"]["error"], "already_active")

    def test_a_single_report_purchase_does_not_unlock_printing(self):
        self.configure({"enabled": True})
        self.paid(self.buy("per_report", "direct"))
        self.assertFalse(self.education()["can_print"])

    def test_single_print_switched_off_is_not_offered(self):
        c = billing.validate({"enabled": True})
        c["plans"]["print"]["enabled"] = False
        self.configure(c)
        self.assertIsNone(self.education()["print_offer"])
        self.assertEqual(self.client.post("/v1/billing/orders", json={"plan": "print", "item": "cbt"}).status_code, 409)

    # --- the library and what each plan unlocks -------------------------------------------------
    def test_learn_reads_the_library_but_after_the_free_months_it_locks(self):
        self.configure({"enabled": True})
        edu = self.education()
        self.assertTrue(edu["library"], "the free months start at the first visit")
        self.assertFalse(edu["can_print"], "Learn has no PDF downloads")
        self.assertIn("var CAN_PRINT = false;", self.page(edu, "cbt"))
        _sql_exec("update entitlements set expires_at = now() - interval '1 minute' where clinician_id=%s", self.cid)
        edu = self.education()
        self.assertFalse(edu["library"])
        self.assertTrue(all(p["locked"] and p["url"] is None for p in edu["pages"]))
        self.assertIsNone(edu["print_offer"], "no single print without the library")
        token = main.EDUCATION.signer.token(self.cid)
        r = self.client.get(f"/learn/cbt?t={token}")
        self.assertEqual(r.status_code, 402)
        self.assertIn("Choose a plan", r.text)
        self.paid(self.buy("learn", period="year"))
        self.assertTrue(self.education()["library"])

    def test_billing_me_shows_the_plan_and_what_it_unlocks(self):
        self.configure({"enabled": True})
        me = self.client.get("/v1/billing/me").json()
        self.assertEqual((me["plan"]["id"], me["plan"]["trial"]), ("learn", True))
        self.assertEqual(me["features"], ["library"])
        self.paid(self.buy("scale"))
        me = self.client.get("/v1/billing/me").json()
        self.assertEqual((me["plan"]["id"], me["plan"]["period"], me["plan"]["trial"]), ("scale", "month", False))
        self.assertEqual(me["scale"], {**me["scale"], "guided_left": 10, "per_month": 10, "extra_price": 12900})
        self.assertIn("guided_included", me["features"])
        self.assertEqual(self.client.get("/v1/me").json()["features"]["unlocked"], me["features"])

    def test_calendar_and_booking_page_need_practice_or_above(self):
        self.configure({"enabled": True})
        r = self.client.get("/v1/calendar")
        self.assertEqual((r.status_code, r.json()["detail"]["feature"]), (402, "appointments"))
        self.paid(self.buy("practice"))
        self.assertNotEqual(self.client.get("/v1/calendar").status_code, 402)

    def test_scale_reports_then_extras_at_scales_price(self):
        self.configure({"enabled": True})
        r = self.client.post("/v1/billing/orders", json={"plan": "scale_extra"})
        self.assertEqual(r.status_code, 409, "extras are for Scale only")
        self.paid(self.buy("scale"))
        _sql_exec("update entitlements set credits_used = 10 where clinician_id=%s and period='allowance'", self.cid)
        r = self.guided_report()
        self.assertEqual(r.status_code, 402)
        self.assertEqual((r.json()["detail"]["plan"], r.json()["detail"]["price"]), ("scale_extra", 12900))
        o = self.buy("scale_extra")
        self.assertEqual(o["order"]["amount"], 12900)
        self.paid(o)
        self.assertEqual(self.guided_report().json()["reply"]["status"], "delivered")
        self.assertEqual(self.balance()["guided"], 0)

    def test_a_quick_consult_is_always_bought_per_report(self):
        self.configure({"enabled": True})
        self.paid(self.buy("scale"))
        r = self.consult()
        self.assertEqual(r.status_code, 402, "Scale's reports are AI-Guided only")
        self.assertEqual((r.json()["detail"]["plan"], r.json()["detail"]["price"]), ("per_report", 9900))

    # --- own Anthropic key (BYOK Scale) ------------------------------------------------------------
    def byok_on(self, plan=True):
        self.configure({"enabled": True})
        if plan:
            billing_db.admin_grant(self.cid, "byok_scale", self.admin_id, "test", main.BILLING.config()[1], None, 30)

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
        self.own.append(OwnKeyModel(OWN_KEY))
        r = self.guided_report(use_own_key=True)
        self.assertEqual(r.json()["reply"]["status"], "delivered", r.text)
        self.assertGreaterEqual(self.own[-1].calls, 1)
        self.assertEqual([x["kind"] for x in billing_db.ledger(self.cid)], [], "BYOK Scale spends no credit")
        with psycopg.connect(URL) as c:
            used = c.execute("select report_type, outcome from byok_usage where clinician_id=%s", (self.cid,)).fetchall()
        self.assertEqual(used, [("guided", "ok")], "admins see usage counts, never the key")
        self.assertIn("ok", {u["outcome"] for u in billing_db.byok_stats(1)["usage"]})

    def test_own_key_failure_never_falls_back_to_the_platform_key(self):
        self.byok_on()
        self.save_key()
        main.PIPELINE = Pipeline(main.SKILL, PlatformMustNotRun(), main.ICD)
        for exc, code, retry in ((anthropic_error(anthropic.RateLimitError, 429), "rate_limited", True),
                                 (anthropic_error(anthropic.AuthenticationError, 401), "invalid_key", False)):
            self.own.append(OwnKeyModel(OWN_KEY, fail=exc))
            r = self.guided_report(use_own_key=True)
            self.assertEqual(r.status_code, 424, r.text)
            self.assertEqual((r.json()["detail"]["code"], r.json()["detail"]["retry"]), (code, retry))
            self.assertNotIn(OWN_KEY, r.text)
        self.assertEqual(billing_db.byok_get(self.cid)["status"], "invalid")
        r = self.guided_report(use_own_key=True)
        self.assertEqual(r.json()["detail"]["code"], "invalid_key", "a key known to be bad is not tried again")

    def test_own_key_needs_byok_scale_and_is_for_guided_reports_only(self):
        self.byok_on(plan=False)
        self.save_key()
        billing_db.admin_adjust(self.cid, 1, self.admin_id, "so the consultation can start")
        r = self.guided_report(use_own_key=True)
        self.assertEqual((r.status_code, r.json()["detail"]["feature"]), (402, "guided_own_key"))
        self.paid(self.buy("byok_scale"))
        self.own.append(OwnKeyModel(OWN_KEY))
        self.assertEqual(self.guided_report(use_own_key=True).json()["reply"]["status"], "delivered")
        self.assertEqual(self.balance()["any"], 1, "no credit spent")
        self.assertEqual(self.consult(use_own_key=True).status_code, 409, "a quick consult is bought per report")

    def test_encryption_key_rotation_keeps_saved_keys_working(self):
        old = base64.b64encode(os.urandom(32)).decode()
        main.BILLING.vault = byok.Vault.from_secrets(old)
        self.byok_on()
        self.save_key()
        main.BILLING.vault = byok.Vault.from_secrets(base64.b64encode(os.urandom(32)).decode(), old, 2)
        self.own.append(OwnKeyModel(OWN_KEY))
        self.assertEqual(self.guided_report(use_own_key=True).json()["reply"]["status"], "delivered")
        self.assertEqual(billing_db.byok_get(self.cid)["key_version"], 2, "sealed again under the new key")
        main.BILLING.vault = byok.Vault.from_secrets(base64.b64encode(os.urandom(32)).decode(), "", 3)
        r = self.guided_report(use_own_key=True)                        # the encryption key was lost
        self.assertEqual((r.status_code, r.json()["detail"]["code"]), (424, "not_configured"))

    def test_own_key_not_offered_when_switched_off(self):
        self.configure({"enabled": True, "plans": {"byok_scale": {"enabled": False}}})
        self.assertEqual(self.save_key().status_code, 409)
        self.assertEqual(self.consult(use_own_key=True).status_code, 409)

    # --- dollar prices outside India ------------------------------------------------------------------
    def mobile(self, number):
        with psycopg.connect(URL, autocommit=True) as c:
            c.execute("update clinicians set mobile=%s where id=%s", (number, self.cid))

    def test_a_mobile_number_from_outside_india_pays_in_dollars(self):
        self.configure({"enabled": True, "usd_rate": 85})
        self.mobile("+447911123456")
        plans = self.client.get("/v1/billing/plans").json()
        practice = next(p for p in plans["plans"] if p["id"] == "practice")
        self.assertEqual((plans["currency"], practice["price_month"]),
                         ("USD", billing.usd_price(billing.DEFAULT_CONFIG["plans"]["practice"]["price_month"], 85)))
        self.assertEqual(self.client.get("/v1/billing/me").json()["currency"], "USD")
        o = self.buy("practice")
        self.assertEqual((o["checkout"]["currency"], o["checkout"]["amount"]), ("USD", practice["price_month"]))
        rz = self.rzp.orders[o["checkout"]["order_id"]]
        self.assertEqual((rz["currency"], rz["amount"]), ("USD", practice["price_month"]), "Razorpay charges dollars")
        self.assertEqual(self.verify(o, self.rzp.pay(o["checkout"]["order_id"])).status_code, 200)
        self.assertIn("appointments", main.BILLING.features(self.cid))
        self.assertEqual(billing_db.orders(self.cid)[0]["currency"], "USD")

    def test_india_and_old_accounts_without_a_number_pay_in_rupees(self):
        self.configure({"enabled": True, "usd_rate": 85})
        self.assertEqual(self.client.get("/v1/billing/plans").json()["currency"], "INR", "no number: rupees")
        self.mobile("+919876543210")
        self.assertEqual(self.client.get("/v1/billing/plans").json()["currency"], "INR")
        self.configure({"enabled": True})
        self.mobile("+447911123456")
        self.assertEqual(self.client.get("/v1/billing/plans").json()["currency"], "INR", "rate 0: dollars off")

    def test_the_buy_a_report_offer_names_its_currency(self):
        self.configure({"enabled": True, "usd_rate": 85})
        self.mobile("+15551234567")
        r = self.consult()
        self.assertEqual(r.status_code, 402, r.text)
        d = r.json()["detail"]
        self.assertEqual((d["currency"], d["price"]), ("USD", billing.usd_price(9900, 85)))

    # --- plans bought outside the app (funnels) -----------------------------------------------------
    def funnel(self, secret=FUNNEL_SECRET, **body):
        sale = {"event_id": "ord_" + uuid.uuid4().hex[:10], "plan": "scale", "period": "year",
                "amount": 19999, "source": "Landing page", "payment_id": "pay_" + uuid.uuid4().hex[:8], **body}
        if "email" not in body:
            sale["email"] = self.email()
        return self.client.post("/v1/webhooks/purchase", json=sale, headers={"X-Webhook-Secret": secret} if secret else {})

    def email(self, who=None, proven=True):
        """A real-looking sign-in email for this clinician (the webhook checks the address). proven: they
        have opened the app with an emailed code to it (the only proof they own it)."""
        who = who or self.cid
        mail = f"buyer-{who[:8]}@example.com"
        with psycopg.connect(URL, autocommit=True) as c:
            c.execute("update auth.users set email=%s where id=%s", (mail, who))
        if proven:
            self.sign_in_with_code(who, mail)
        return mail

    def sign_in_with_code(self, who, mail):
        before = self.who
        main.app.dependency_overrides[main.current_user] = lambda: {"id": who, "proven_email": mail}
        self.client.get("/v1/me")
        main.app.dependency_overrides[main.current_user] = lambda: {"id": self.who}
        self.who = before

    def test_a_funnel_sale_for_an_existing_account_starts_at_once_and_shows_in_payments(self):
        self.configure({"enabled": True})
        self.assertEqual(self.funnel(secret="wrong").status_code, 401)
        self.assertEqual(self.funnel(secret="").status_code, 401)
        ev = "ord_same_" + uuid.uuid4().hex[:8]
        r = self.funnel(event_id=ev, email=self.email().upper())
        self.assertEqual((r.status_code, r.json()["status"]), (200, "applied"), r.text)
        again = self.funnel(event_id=ev)
        self.assertTrue(again.json()["duplicate"], "the tool's retry grants nothing more")
        self.assertEqual(self.balance()["guided"], 10, "a year of Scale: this month's reports, once")
        self.assertIn("guided_included", billing_db.plan_features(self.cid, main.BILLING.config()[1])["features"])
        o = billing_db.orders(self.cid)[0]
        self.assertEqual((o["provider"], o["status"], o["amount"], o["plan"], o["period"]),
                         ("external", "paid", 1999900, "scale", "year"))
        self.who = self.admin_id
        pays = self.client.get("/v1/admin/payments").json()["payments"]
        self.assertIn(str(o["id"]), [p["id"] for p in pays], "in the admin's transaction history")
        lst = self.client.get("/v1/admin/external-purchases").json()
        self.assertEqual(lst["purchases"][0]["status"], "applied")

    def test_a_funnel_sale_before_sign_up_waits_for_that_email(self):
        self.configure({"enabled": True})
        newbie = str(uuid.uuid4())
        mail = f"new-{newbie[:6]}@example.com"
        r = self.funnel(email=mail, plan="practice", period="month", amount=999)
        self.assertEqual(r.json()["status"], "pending")
        self.who = self.admin_id
        self.assertEqual(self.client.get("/v1/admin/external-purchases", params={"status": "pending"})
                         .json()["purchases"][0]["email"], mail)
        with psycopg.connect(URL, autocommit=True) as c:          # they sign up and are verified
            c.execute("insert into auth.users (id, email) values (%s,%s)", (newbie, mail))
            c.execute("""insert into clinicians (id, role, registration_body, level, verification_status, consent_version)
                         values (%s,'psychologist','RCI','L2','verified','v1')""", (newbie,))
        self.sign_in_with_code(newbie, mail)
        f = billing_db.plan_features(newbie, main.BILLING.config()[1])
        self.assertTrue({"pdf", "appointments"} <= f["features"], "the plan starts at their first visit")
        self.assertEqual(billing_db.get_external(r.request.content and json.loads(r.request.content)["event_id"])["status"],
                         "applied")

    def test_a_funnel_sale_goes_only_to_an_account_that_proved_the_email_with_a_code(self):
        """Sign-up needs no confirmation email, so an account can hold an address its owner never received a
        code at (a password sign-up, or an email change). Such an account must not collect that buyer's plan."""
        self.configure({"enabled": True})
        cfg = main.BILLING.config()[1]
        mail = self.email(proven=False)                            # never signed in with a code to it
        r = self.funnel(email=mail, plan="practice", period="month", amount=999)
        self.assertEqual(r.json()["status"], "pending", r.text)
        self.assertNotIn("pdf", billing_db.plan_features(self.cid, cfg)["features"])
        self.who = self.cid
        self.client.get("/v1/me")                                  # a password sign-in proves nothing
        self.assertNotIn("pdf", billing_db.plan_features(self.cid, cfg)["features"])
        other = f"proven-{self.cid[:6]}@example.com"               # proved another address, then switched
        self.sign_in_with_code(self.cid, other)
        self.assertNotIn("pdf", billing_db.plan_features(self.cid, cfg)["features"])
        self.sign_in_with_code(self.cid, mail.upper())             # the owner signs in with the code
        self.assertIn("pdf", billing_db.plan_features(self.cid, cfg)["features"])
        self.assertEqual(billing_db.get_external(json.loads(r.request.content)["event_id"])["status"], "applied")

    def test_bad_funnel_sales_are_refused_and_an_admin_can_cancel_a_waiting_one(self):
        self.configure({"enabled": True})
        for bad in ({"plan": "gold"}, {"plan": "scale", "period": None}, {"plan": "per_report"},
                    {"email": "not-an-email"}, {"event_id": ""}, {"period": "week"}):
            self.assertEqual(self.funnel(**bad).status_code, 422, bad)
        ev = "ord_cancel_" + uuid.uuid4().hex[:8]
        r = self.funnel(email="later@example.com", event_id=ev)
        pid = billing_db.get_external(ev)["id"]
        self.who = self.admin_id
        self.assertEqual(self.client.post(f"/v1/admin/external-purchases/{pid}/cancel",
                                          json={"active": False, "reason": "refunded in the funnel"}).status_code, 200)
        self.assertEqual(billing_db.get_external(ev)["status"], "cancelled")
        self.assertEqual(r.json()["status"], "pending")
        self.assertEqual(self.client.post(f"/v1/admin/external-purchases/{pid}/cancel",
                                          json={"active": False, "reason": "again"}).status_code, 409)

    def test_the_funnel_webhook_is_off_without_its_secret(self):
        main.BILLING.cfg.funnel_webhook_secret = ""
        self.assertEqual(self.funnel().status_code, 404)

    # --- admin -------------------------------------------------------------------------------
    def test_only_admins_change_pricing(self):
        self.assertEqual(self.client.get("/v1/admin/pricing").status_code, 403)
        self.assertEqual(self.client.put("/v1/admin/pricing", json={"config": {"enabled": True}}).status_code, 403)
        self.assertEqual(self.client.get("/v1/admin/payments/summary").status_code, 403)

    def test_pricing_change_is_validated_confirmed_and_audited(self):
        self.configure({"enabled": True})
        o = self.buy("scale")
        self.verify(o, self.rzp.pay(o["checkout"]["order_id"]))
        self.who = self.admin_id
        cfg = self.client.get("/v1/admin/pricing").json()["config"]
        bad = copy.deepcopy(cfg)
        bad["plans"]["scale"]["price_year"] = -5
        r = self.client.put("/v1/admin/pricing", json={"config": bad})
        self.assertEqual(r.status_code, 422)
        off = copy.deepcopy(cfg)
        off["plans"]["scale"]["enabled"] = False
        r = self.client.put("/v1/admin/pricing", json={"config": off})
        self.assertEqual(r.status_code, 409)
        self.assertGreaterEqual(r.json()["detail"]["affected"]["scale"], 1)
        r = self.client.put("/v1/admin/pricing", json={"config": off, "confirm_disable": True})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["changes"], {"plans.scale.enabled": [True, False]})
        with psycopg.connect(URL) as c:
            row = c.execute("select actor_id, detail from admin_audit where action='pricing_config' "
                            "order by created_at desc limit 1").fetchone()
        self.assertEqual((str(row[0]), row[1]["changes"]), (self.admin_id, {"plans.scale.enabled": [True, False]}))
        hist = self.client.get("/v1/admin/pricing/history").json()["history"]
        self.assertEqual(hist[0]["detail"]["changes"], {"plans.scale.enabled": [True, False]})
        self.assertTrue(hist[0]["actor_email"].endswith("@test"))
        self.who = self.cid
        self.assertEqual(self.balance()["guided"], 10, "people already on the plan keep it")

    def test_paid_plans_need_razorpay_keys(self):
        main.BILLING.cfg.razorpay_configured = False
        self.who = self.admin_id
        r = self.client.put("/v1/admin/pricing", json={"config": billing.validate({"enabled": True})})
        self.assertEqual(r.json()["detail"]["error"], "payments_unavailable")

    def test_admin_adjust_needs_a_reason_and_refund_goes_through_razorpay(self):
        self.configure({"enabled": True})
        o = self.buy("scale")
        self.verify(o, self.rzp.pay(o["checkout"]["order_id"]))
        self.who = self.admin_id
        r = self.client.post(f"/v1/admin/billing/users/{self.cid}/adjust", json={"delta": 3, "reason": ""})
        self.assertEqual(r.status_code, 422)
        r = self.client.post(f"/v1/admin/billing/users/{self.cid}/adjust", json={"delta": 3, "reason": "goodwill"})
        self.assertEqual(r.json()["balance"]["guided"], 13)
        r = self.client.post(f"/v1/admin/payments/{o['order']['id']}/refund", json={"reason": "asked to cancel"})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["order"]["refund_status"], "refunded")
        self.assertEqual(len(self.rzp.refunds), 1)
        again = self.client.post(f"/v1/admin/payments/{o['order']['id']}/refund", json={"reason": "again"})
        self.assertEqual(again.status_code, 422, "nothing left to refund")
        self.assertEqual(billing_db.balance(self.cid)["guided"], 3, "the refunded plan's reports are withdrawn")
        r = self.client.post(f"/v1/admin/billing/users/{self.cid}/grant",
                             json={"plan": "scale", "days": 90, "reason": "Play reviewer"})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(billing_db.balance(self.cid)["guided"], 13, "a granted Scale brings this month's reports")
        self.assertEqual(self.client.post(f"/v1/admin/billing/users/{self.cid}/grant",
                                          json={"plan": "sub_30", "reason": "old plan"}).status_code, 422)


if __name__ == "__main__":
    unittest.main()


@unittest.skipUnless(HAVE, "TEST_DATABASE_URL not set")
class ProvenEmailTests(unittest.TestCase):
    """Which sign-ins prove the account owns its email (Supabase's `amr` claim in the login token)."""

    def test_only_an_emailed_code_proves_the_address(self):
        code = {"sub": "u", "email": "Dr.Ravi@Example.com", "amr": [{"method": "otp", "timestamp": 1}]}
        self.assertEqual(main.proven_email(code), "dr.ravi@example.com")
        self.assertEqual(main.proven_email({**code, "amr": [{"method": "magiclink", "timestamp": 1}]}),
                         "dr.ravi@example.com")
        for not_proof in ({**code, "amr": [{"method": "password", "timestamp": 1}]}, {**code, "amr": []},
                          {"sub": "u", "email": "x@example.com"}, {**code, "email": ""}, {**code, "amr": "otp"}):
            self.assertIsNone(main.proven_email(not_proof), not_proof)
