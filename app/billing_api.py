"""
Billing endpoints and the check that runs before every report.

Clinician (signed in):
  GET    /v1/billing/plans                 → the plans on sale and the comparison table (admin's configuration)
  GET    /v1/billing/me                    → current plan, what it unlocks, credits, BYOK status, notices
  POST   /v1/billing/orders                → start a purchase: server-priced Razorpay order
  POST   /v1/billing/orders/{id}/verify    → checkout finished: signature + Razorpay's own record
  POST   /v1/billing/orders/{id}/cancel    → checkout closed without paying
  GET    /v1/billing/orders/{id}           → one order (also reconciles a pending payment)
  GET    /v1/billing/orders                → payment history
  GET    /v1/billing/ledger                → credit history
  PUT    /v1/billing/byok                  → save (after checking) the clinician's own Anthropic key
  POST   /v1/billing/byok/check            → check the saved key again
  DELETE /v1/billing/byok                  → remove it
Razorpay:
  POST   /v1/payments/razorpay/webhook     → signed events; each applied once
Funnels (plans bought outside the app):
  POST   /v1/webhooks/purchase             → X-Webhook-Secret; applied at once, or when the buyer signs up
Admin (is_admin; every change audited):
  GET/PUT /v1/admin/pricing · GET /v1/admin/pricing/history · GET /v1/admin/billing/users · GET /v1/admin/billing/users/{id}
  POST /v1/admin/billing/users/{id}/grant  · POST /v1/admin/billing/users/{id}/adjust
  POST /v1/admin/billing/entitlements/{id}/extend · POST /v1/admin/billing/entitlements/{id}/status
  GET  /v1/admin/payments · GET /v1/admin/payments/summary · POST /v1/admin/payments/{id}/refund
  GET  /v1/admin/byok/usage

Before a report: authorize() → the report runs (with the clinician's own key when they chose it)
→ settle() spends the held credit if the report was delivered, gives it back otherwise.
What a plan unlocks (library, PDF, booking page, appointments, AI-Guided Case Taking): features().
Pricing off = everything unlocked and free, as before plans existed.
"""
from __future__ import annotations

import hashlib
import json
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request
from pydantic import BaseModel, ConfigDict, Field, SecretStr

from . import billing, byok
from .razorpay import Razorpay, RazorpayError, webhook_signature_ok


@dataclass
class Funding:
    kind: str                        # free · credit · byok
    report_type: str
    request_key: str
    reserved: bool = False           # a credit is held for this request
    api_key: str | None = field(default=None, repr=False)   # BYOK only; never logged


class OrderIn(BaseModel):
    plan: str = Field(pattern="^(per_report|learn|practice|byok_scale|scale|scale_extra|print)$")
    report_type: str | None = Field(default=None, pattern="^(guided|direct)$")
    item: str | None = Field(default=None, pattern="^[a-z0-9-]{1,80}$")     # single print: the page
    period: str | None = Field(default=None, pattern="^(month|year)$")     # a plan: monthly or yearly


class ExternalPurchaseIn(BaseModel):
    """One sale from a funnel or automation tool. Extra fields the tool sends are ignored."""
    model_config = ConfigDict(extra="ignore")
    event_id: str = Field(min_length=1, max_length=160)      # the tool's own order / transaction id
    email: str = Field(max_length=254)
    plan: str = Field(pattern="^(learn|practice|byok_scale|scale|per_report)$")
    period: str | None = Field(default=None, pattern="^(month|year)$")
    report_type: str | None = Field(default=None, pattern="^(guided|direct)$")
    amount: float | None = Field(default=None, ge=0, le=1_000_000)   # rupees, as paid
    currency: str = Field(default="INR", pattern="^[A-Z]{3}$")
    source: str = Field(default="", max_length=60)
    payment_id: str | None = Field(default=None, max_length=120)


class VerifyPaymentIn(BaseModel):
    razorpay_order_id: str = Field(max_length=64)
    razorpay_payment_id: str = Field(max_length=64)
    razorpay_signature: str = Field(max_length=256)


class ByokIn(BaseModel):
    api_key: SecretStr = Field(max_length=400)


class PricingIn(BaseModel):
    config: dict
    confirm_disable: bool = False     # the admin confirmed switching off a plan that has active users


class GrantIn(BaseModel):
    plan: str = Field(pattern="^(learn|practice|byok_scale|scale|manual)$")
    credits: int | None = Field(default=None, ge=1, le=billing.MAX_REPORTS)
    days: int | None = Field(default=None, ge=1, le=billing.MAX_DAYS)
    reason: str = Field(min_length=3, max_length=300)


class AdjustIn(BaseModel):
    delta: int = Field(ge=-billing.MAX_REPORTS, le=billing.MAX_REPORTS)
    reason: str = Field(min_length=3, max_length=300)


class ExtendIn(BaseModel):
    days: int = Field(ge=1, le=billing.MAX_DAYS)
    reason: str = Field(min_length=3, max_length=300)


class StatusIn(BaseModel):
    active: bool
    reason: str = Field(min_length=3, max_length=300)


class RefundIn(BaseModel):
    amount: int | None = Field(default=None, ge=100)     # paise; default: everything not yet refunded
    revoke_credits: bool = True
    reason: str = Field(min_length=3, max_length=300)


def _iso(d):
    return d.isoformat() if isinstance(d, datetime) else d


def _ent_view(e: dict) -> dict:
    return {"id": str(e["id"]), "plan": e["plan"], "report_type": e["report_type"], "state": e.get("state", "active"),
            "period": e.get("period"),
            "credits_total": e["credits_total"], "credits_used": e["credits_used"],
            "remaining": e.get("remaining", e["credits_total"] - e["credits_used"] - e.get("credits_reserved", 0)),
            "starts_at": _iso(e["starts_at"]), "expires_at": _iso(e["expires_at"]),
            "order_id": str(e["order_id"]) if e.get("order_id") else None, "note": e.get("note")}


def _order_view(o: dict) -> dict:
    out = {k: (_iso(v) if isinstance(v, datetime) else str(v) if isinstance(v, uuid.UUID) else v)
           for k, v in dict(o).items()}
    return out


class BillingService:
    def __init__(self, cfg, store, model_factory, store_on):
        """store: app.billing_db (or a test double); model_factory(api_key) → a model client for BYOK;
        store_on(): False in DEV_MODE without a database (pricing then reads as off)."""
        self.cfg, self.store, self.model_factory, self.store_on = cfg, store, model_factory, store_on
        self.razorpay = Razorpay(cfg.razorpay_key_id, cfg.razorpay_key_secret) if cfg.razorpay_configured else None
        self.vault = byok.Vault.from_secrets(cfg.byok_encryption_key, cfg.byok_encryption_key_previous,
                                             cfg.byok_key_version)
        self._cached = None
        self.print_items: dict[str, str] = {}     # education pages a single print may name: {slug: title}

    # --- configuration -------------------------------------------------------------------
    CACHE_SECONDS = 15

    def config(self) -> tuple[int, dict]:
        if not self.store_on():
            return 0, billing.validate({})
        now = time.monotonic()
        if self._cached is None or now - self._cached[0] > self.CACHE_SECONDS:
            self._cached = (now, self.store.get_config())
        return self._cached[1]

    def forget_config(self) -> None:
        self._cached = None

    def enabled(self) -> bool:
        return self.config()[1]["enabled"]

    # --- what the clinician's plan unlocks ------------------------------------------------
    def features(self, cid) -> frozenset:
        """Pricing off (or no database): everything. Otherwise what the running plans unlock; the
        first check of a verified clinician starts Learn's free months."""
        _, cfg = self.config()
        if not (self.store_on() and cfg["enabled"]):
            return billing.ALL_FEATURES
        return frozenset(self.store.plan_features(cid, cfg)["features"])

    def need(self, cid, feature: str) -> None:
        if feature not in self.features(cid):
            raise HTTPException(402, plan_required(feature))

    def guided_access(self, c: dict) -> None:
        """Before a guided consultation starts: a plan with AI-Guided Case Taking, or a guided report
        bought on its own (per report, or a Scale extra)."""
        f = self.features(c["id"])
        if f & {"guided_own_key", "guided_included"} or not self.enabled():
            return
        if self.store.balance(c["id"])["guided"] > 0:
            return
        raise HTTPException(402, plan_required("guided", self._report_price(c, self.config()[1], "guided")))

    # --- the check before every report ---------------------------------------------------
    def authorize(self, c: dict, report_type: str, request_key: str, use_own_key: bool) -> Funding:
        _, cfg = self.config()
        if use_own_key:
            return self._authorize_byok(c, cfg, report_type, request_key)
        if not cfg["enabled"]:
            return Funding("free", report_type, request_key)
        self._reserve(c, cfg, report_type, request_key)
        return Funding("credit", report_type, request_key, reserved=True)

    def _report_price(self, c, cfg, report_type) -> dict:
        """What one more report of this type costs this clinician: a Scale extra, or per report."""
        if report_type == "guided" and cfg["plans"]["scale"]["enabled"] and self.store.scale_active(c["id"]):
            return {"plan": "scale_extra", "price": cfg["plans"]["scale"]["extra_price"]}
        p = cfg["plans"]["per_report"]
        return {"plan": "per_report", "price": p["prices"][report_type] if p["enabled"] else None}

    def _reserve(self, c, cfg, report_type, request_key):
        try:
            self.store.reserve(c["id"], report_type, request_key)
        except billing.NoCredit:
            offer = self._report_price(c, cfg, report_type)
            message = ("You have used this month's AI-Guided reports. Buy an extra report to continue."
                       if offer["plan"] == "scale_extra" else
                       "You have no report credits left. Buy a report or a plan to continue.")
            raise HTTPException(402, {"error": "payment_required", "report_type": report_type, "message": message,
                                      "plan": offer["plan"], "price": offer["price"], "currency": cfg["currency"]})
        except billing.AlreadyCharged:
            raise HTTPException(409, {"error": "already_charged",
                                      "message": "This report was already generated. Open it from History."})
        except billing.InProgress:
            raise HTTPException(409, {"error": "busy", "detail": "this report is already being written"})

    def _authorize_byok(self, c, cfg, report_type, request_key) -> Funding:
        p = cfg["plans"]["byok_scale"]
        if not (cfg["enabled"] and p["enabled"]) or report_type != "guided":
            raise HTTPException(409, {"error": "byok_unavailable",
                                      "message": "Your own AI key is for AI-Guided Case Taking on BYOK Scale."})
        if self.vault is None:
            raise HTTPException(503, {"error": "byok_unavailable", "message": "Not available right now."})
        if "guided_own_key" not in self.features(c["id"]):
            raise HTTPException(402, plan_required("guided_own_key"))
        cred = self.store.byok_get(c["id"])
        if not cred:
            raise HTTPException(424, {"error": "byok_failed", "code": "not_configured",
                                      "message": byok.ByokError.MESSAGES["not_configured"]})
        if cred["status"] != "valid":
            raise HTTPException(424, {"error": "byok_failed", "code": "invalid_key",
                                      "message": byok.ByokError.MESSAGES["invalid_key"]})
        key = self.open_key(c, cred)
        if key is None:
            raise HTTPException(424, {"error": "byok_failed", "code": "not_configured",
                                      "message": byok.ByokError.MESSAGES["not_configured"]})
        return Funding("byok", report_type, request_key, api_key=key)

    def open_key(self, c: dict, cred: dict) -> str | None:
        """The clinician's own key, or None if it can't be read (encryption key lost or rotated away).
        A key sealed under the previous encryption key is sealed again under the current one."""
        try:
            key = self.vault.open(c["id"], cred["ciphertext"], cred["nonce"], cred["key_version"])
        except Exception:   # noqa: BLE001 - never include the stored value in an error
            return None
        if cred["key_version"] != self.vault.current:
            self.store.byok_save(c["id"], self.vault.seal(c["id"], key), cred["status"], cred["last_error"])
        return key

    def model_for(self, f: Funding):
        return self.model_factory(f.api_key) if f.kind == "byok" else None

    def settle(self, c: dict, f: Funding, delivered: bool) -> None:
        if f.reserved:
            if delivered:
                self.store.consume(c["id"], f.request_key)
            else:
                self.store.release(c["id"], f.request_key, "report not delivered")
        if f.kind == "byok":
            self.store.byok_log(c["id"], f.report_type, "ok" if delivered else "held_back")

    def cancel(self, c: dict, f: Funding) -> None:
        """The report was refused before any model call (identifiers found, intake not ready): free."""
        if f.reserved:
            self.store.release(c["id"], f.request_key, "report not started")

    def failed(self, c: dict, f: Funding, exc: Exception) -> HTTPException | None:
        """The report call raised. Gives the credit back; for BYOK returns the clinician-facing error
        (never falling back to the platform key). None = not a BYOK failure: re-raise the original."""
        if f.reserved:
            self.store.release(c["id"], f.request_key, "report failed")
        if f.kind != "byok":
            return None
        err = byok.map_error(exc)
        self.store.byok_log(c["id"], f.report_type, err.code)
        if err.code in ("invalid_key", "no_access"):
            self.store.byok_mark(c["id"], "invalid", err.code)
        return HTTPException(424, {"error": "byok_failed", "code": err.code, "message": err.message,
                                   "retry": err.code in ("rate_limited", "provider_error", "insufficient_balance")})


PLAN_MESSAGES = {
    "library": "The practice library is part of every plan. Choose a plan to keep reading.",
    "pdf": "PDF downloads with your name are in Practice, BYOK Scale and Scale.",
    "booking": "Your booking page is in Practice, BYOK Scale and Scale.",
    "appointments": "Appointments are in Practice, BYOK Scale and Scale.",
    "guided": "AI-Guided Case Taking is in BYOK Scale and Scale, or buy a single guided report.",
    "guided_own_key": "Using your own AI key is part of BYOK Scale.",
}


def plan_required(feature: str, offer: dict | None = None) -> dict:
    """The 402 body when the clinician's plan doesn't include something: the app opens Plans."""
    out = {"error": "plan_required", "feature": feature, "message": PLAN_MESSAGES[feature]}
    if offer and offer.get("price") is not None:
        out.update(plan=offer["plan"], price=offer["price"], report_type="guided")
    return out


def install(app: FastAPI, svc: BillingService, current_user, verified_clinician, admin) -> None:

    def _need_store():
        if not svc.store_on():
            raise HTTPException(503, {"error": "billing_unavailable", "message": "Payments are not available here."})

    # --- clinician ---------------------------------------------------------------------
    @app.get("/v1/billing/plans")
    def billing_plans(user: dict = Depends(current_user)):
        _, cfg = svc.config()
        return {**billing.public_plans(cfg), "payments_available": svc.razorpay is not None}

    @app.get("/v1/billing/me")
    def billing_me(c: dict = Depends(verified_clinician)):
        _, cfg = svc.config()
        out = {"enabled": cfg["enabled"], "currency": cfg["currency"], "prices": cfg["plans"]["per_report"]["prices"]
               if cfg["plans"]["per_report"]["enabled"] else None}
        if not svc.store_on():
            return {**out, "balance": {"any": 0, "guided": 0, "direct": 0}, "plan": None,
                    "features": sorted(billing.ALL_FEATURES), "scale": None, "subscriptions": [], "per_report": [],
                    "byok": {"available": False}, "notices": []}
        pf = svc.store.plan_features(c["id"], cfg) if cfg["enabled"] else {"features": billing.ALL_FEATURES,
                                                                              "plans": []}
        ents = svc.store.entitlements(c["id"])
        now = datetime.now(timezone.utc)
        live = [e for e in ents if e["state"] in ("active", "scheduled")]
        balance = svc.store.balance(c["id"])
        rank = {t: i for i, t in enumerate(billing.TIERS)}
        running = sorted(pf["plans"], key=lambda e: (rank[e["plan"]], e["expires_at"]), reverse=True)
        current = running[0] if running else None
        plan = None
        if current:
            until = max(e["expires_at"] for e in ents if e["plan"] == current["plan"] and e["state"] in
                        ("active", "scheduled") and e.get("period") not in ("allowance", None))
            plan = {"id": current["plan"], "name": cfg["plans"][current["plan"]]["name"], "period": current["period"],
                    "trial": current["period"] == "trial", "expires_at": _iso(until)}
        allowance = [e for e in live if e["plan"] == "scale" and e.get("period") == "allowance" and e["state"] == "active"]
        scale = None
        if any(e["plan"] == "scale" for e in pf["plans"]):
            scale = {"guided_left": sum(e["remaining"] for e in allowance),
                     "resets_at": _iso(min((e["expires_at"] for e in allowance), default=None)),
                     "per_month": cfg["plans"]["scale"]["guided_per_month"],
                     "extra_price": cfg["plans"]["scale"]["extra_price"]}
        subs = [_ent_view(e) for e in ents if e["plan"] in billing.TIERS + ("manual",)
                and e.get("period") != "allowance"][:10]
        per = [_ent_view(e) for e in live if e["plan"] in ("per_report", "scale_extra")]
        p = cfg["plans"]["byok_scale"]
        cred = svc.store.byok_get(c["id"])
        b = {"available": bool(cfg["enabled"] and p["enabled"] and svc.vault is not None),
             "included": "guided_own_key" in pf["features"],
             "connected": bool(cred), "status": cred["status"] if cred else None,
             "last4": cred["last4"] if cred else None, "last_error": cred["last_error"] if cred else None,
             "report_types": ["guided"], "instructions": p["instructions"]}
        notices = []
        if plan and plan["expires_at"]:
            ends = datetime.fromisoformat(plan["expires_at"])
            if ends - now < timedelta(days=7 if plan["trial"] else 3):
                notices.append({"kind": "expiring", "message": (
                    f"Your free months end on {ends:%d %b %Y}. Choose a plan to keep the library." if plan["trial"]
                    else f"Your {plan['name']} plan ends on {ends:%d %b %Y}.")})
        elif cfg["enabled"]:
            notices.append({"kind": "no_plan", "message": "Choose a plan to use the practice library and more."})
        if scale and scale["guided_left"] == 0 and balance["guided"] == 0:
            notices.append({"kind": "exhausted", "message": "You have used this month's AI-Guided reports."})
        pending = [o for o in svc.store.orders(c["id"], 20) if o["status"] == "pending"]
        if pending:
            notices.append({"kind": "pending_payment", "message": "A payment is still being confirmed by the bank."})
        if cred and cred["status"] == "invalid":
            notices.append({"kind": "byok_invalid", "message": byok.ByokError.MESSAGES["invalid_key"]})
        return {**out, "balance": balance, "plan": plan, "features": sorted(pf["features"]), "scale": scale,
                "subscriptions": subs, "per_report": per, "byok": b, "notices": notices}

    @app.post("/v1/billing/orders")
    def billing_order(body: OrderIn, c: dict = Depends(verified_clinician)):
        _need_store()
        version, cfg = svc.config()
        if body.plan == "print":
            if body.item not in svc.print_items:
                raise HTTPException(409, {"error": "not_purchasable", "message": "unknown page"})
            if "pdf" in svc.features(c["id"]):
                raise HTTPException(409, {"error": "already_active",
                                          "message": "Your plan already includes PDF downloads."})
        if body.plan == "scale_extra" and not svc.store.scale_active(c["id"]):
            raise HTTPException(409, {"error": "not_purchasable", "message": "Extra reports are for the Scale plan."})
        try:
            price = billing.price_for(cfg, body.plan, body.report_type, item=body.item, period=body.period)
        except billing.NotPurchasable as e:
            raise HTTPException(409, {"error": "not_purchasable", "message": e.detail})
        if price.amount == 0:
            # A free plan: granted at once, at most one running at a time.
            if any(e["plan"] == body.plan and e.get("item") == price.item and e["state"] in ("active", "scheduled")
                   for e in svc.store.entitlements(c["id"])):
                raise HTTPException(409, {"error": "already_active", "message": "This plan is already active."})
            o = svc.store.create_order(c["id"], price, version)
            svc.store.fulfil(o["id"], None, cfg)
            return {"order": _order_view(svc.store.get_order(o["id"])), "checkout": None}
        if svc.razorpay is None:
            raise HTTPException(503, {"error": "payments_unavailable", "message": "Payments are not set up yet."})
        o = svc.store.create_order(c["id"], price, version)
        try:
            ro = svc.razorpay.create_order(price.amount, price.currency, receipt=str(o["id"]),
                                           notes={"order": str(o["id"]), "plan": price.plan})
        except RazorpayError as e:
            # Razorpay's own reason (e.g. "Razorpay 401: Authentication failed"), shown in /admin → Payments.
            # RazorpayError never carries the keys.
            svc.store.mark_order(o["id"], "failed", reason=f"could not create the Razorpay order ({e})"[:300])
            raise HTTPException(502, {"error": "payments_unreachable", "message": "Couldn't reach the payment service. Try again."})
        svc.store.set_provider_order(o["id"], ro["id"])
        plan = cfg["plans"]["scale" if price.plan == "scale_extra" else price.plan]
        return {"order": _order_view(svc.store.get_order(o["id"])),
                "checkout": {"key": svc.cfg.razorpay_key_id, "order_id": ro["id"], "amount": price.amount,
                             "currency": price.currency, "name": "YourCounselor",
                             "description": (plan["name"] if price.plan != "scale_extra" else "Extra AI-Guided report")
                             + (f" · {'monthly' if price.period == 'month' else 'yearly'}" if price.period else "")
                             + (f" · {price.report_type}" if price.report_type and price.plan == "per_report" else "")
                             + (f" · {svc.print_items[price.item]}"[:250] if price.item else "")}}

    def _finish(order: dict, payment: dict, cfg: dict) -> dict:
        """Apply Razorpay's own record of a payment to our order (shared by verify, poll and webhook)."""
        if payment.get("order_id") != order["provider_order_id"]:
            raise HTTPException(400, {"error": "payment_mismatch"})
        if payment.get("amount") != order["amount"] or payment.get("currency") != order["currency"]:
            svc.store.mark_order(order["id"], "failed", payment.get("id"), "amount mismatch")
            raise HTTPException(400, {"error": "payment_mismatch"})
        st = payment.get("status")
        if st == "captured":
            svc.store.fulfil(order["id"], payment["id"], cfg)
        elif st in ("authorized", "created"):
            svc.store.mark_order(order["id"], "pending", payment.get("id"))
        elif st == "failed":
            svc.store.mark_order(order["id"], "failed", payment.get("id"),
                                 (payment.get("error_description") or "payment failed"))
        return _order_view(svc.store.get_order(order["id"]))

    @app.post("/v1/billing/orders/{order_id}/verify")
    def billing_verify(order_id: uuid.UUID, body: VerifyPaymentIn, c: dict = Depends(verified_clinician)):
        _need_store()
        o = svc.store.get_order(order_id, c["id"])
        if not o:
            raise HTTPException(404, "order not found")
        if o["status"] == "paid":
            return {"order": _order_view(o)}
        if svc.razorpay is None:
            raise HTTPException(503, {"error": "payments_unavailable"})
        if body.razorpay_order_id != o["provider_order_id"] or not svc.razorpay.signature_ok(
                body.razorpay_order_id, body.razorpay_payment_id, body.razorpay_signature):
            raise HTTPException(400, {"error": "invalid_signature", "message": "This payment could not be verified."})
        try:
            payment = svc.razorpay.payment(body.razorpay_payment_id)
        except RazorpayError:
            svc.store.mark_order(o["id"], "pending", body.razorpay_payment_id)
            return {"order": _order_view(svc.store.get_order(o["id"]))}   # the webhook or a later poll finishes it
        return {"order": _finish(o, payment, svc.config()[1])}

    @app.post("/v1/billing/orders/{order_id}/cancel")
    def billing_cancel(order_id: uuid.UUID, c: dict = Depends(verified_clinician)):
        _need_store()
        return {"cancelled": svc.store.cancel_order(order_id, c["id"])}

    @app.get("/v1/billing/orders/{order_id}")
    def billing_get_order(order_id: uuid.UUID, c: dict = Depends(verified_clinician)):
        _need_store()
        o = svc.store.get_order(order_id, c["id"])
        if not o:
            raise HTTPException(404, "order not found")
        if o["status"] in ("created", "pending", "cancelled") and o["provider_order_id"] and svc.razorpay:
            try:   # a payment the app never reported (closed app, slow bank): ask Razorpay
                for p in svc.razorpay.order_payments(o["provider_order_id"]):
                    if p.get("status") in ("captured", "authorized"):
                        return {"order": _finish(o, p, svc.config()[1])}
            except RazorpayError:
                pass
        return {"order": _order_view(o)}

    @app.get("/v1/billing/orders")
    def billing_orders(c: dict = Depends(verified_clinician)):
        _need_store()
        return {"orders": [_order_view(o) for o in svc.store.orders(c["id"])]}

    @app.get("/v1/billing/ledger")
    def billing_ledger(c: dict = Depends(verified_clinician)):
        _need_store()
        return {"ledger": [_order_view(r) for r in svc.store.ledger(c["id"])]}

    # --- BYOK ----------------------------------------------------------------------------
    def _byok_ready():
        _need_store()
        _, cfg = svc.config()
        if svc.vault is None or not (cfg["enabled"] and cfg["plans"]["byok_scale"]["enabled"]):
            raise HTTPException(409, {"error": "byok_unavailable",
                                      "message": "Using your own Anthropic key is not available."})

    @app.put("/v1/billing/byok")
    def byok_save(body: ByokIn, c: dict = Depends(verified_clinician)):
        _byok_ready()
        key = body.api_key.get_secret_value().strip()
        if not byok.looks_like_key(key):
            raise HTTPException(422, {"error": "byok_invalid", "code": "format",
                                      "message": "That does not look like an Anthropic API key (it starts with sk-ant-)."})
        try:
            byok.check_key(key, svc.cfg.claude_model)
        except byok.ByokError as e:
            status = 503 if e.code in ("rate_limited", "provider_error") else 422
            raise HTTPException(status, {"error": "byok_invalid", "code": e.code, "message": e.message})
        svc.store.byok_save(c["id"], svc.vault.seal(c["id"], key), "valid", None)
        return {"connected": True, "status": "valid", "last4": key[-4:]}

    @app.post("/v1/billing/byok/check")
    def byok_recheck(c: dict = Depends(verified_clinician)):
        _byok_ready()
        cred = svc.store.byok_get(c["id"])
        if not cred:
            raise HTTPException(404, {"error": "byok_not_found"})
        key = svc.open_key(c, cred)
        if key is None:
            return {"connected": True, "status": "invalid", "last4": cred["last4"], "code": "not_configured",
                    "message": byok.ByokError.MESSAGES["not_configured"]}
        try:
            byok.check_key(key, svc.cfg.claude_model)
        except byok.ByokError as e:
            if e.code in ("invalid_key", "no_access"):
                svc.store.byok_mark(c["id"], "invalid", e.code)
            return {"connected": True, "status": "invalid" if e.code in ("invalid_key", "no_access") else cred["status"],
                    "last4": cred["last4"], "code": e.code, "message": e.message}
        svc.store.byok_mark(c["id"], "valid", None)
        return {"connected": True, "status": "valid", "last4": cred["last4"]}

    @app.delete("/v1/billing/byok")
    def byok_remove(c: dict = Depends(verified_clinician)):
        _need_store()
        return {"removed": svc.store.byok_delete(c["id"])}

    # --- Razorpay webhook ------------------------------------------------------------------
    @app.post("/v1/payments/razorpay/webhook")
    async def razorpay_webhook(request: Request, x_razorpay_signature: str = Header(""),
                               x_razorpay_event_id: str = Header("")):
        if not (svc.store_on() and svc.cfg.razorpay_configured):
            raise HTTPException(404, "not found")
        raw = await request.body()
        if not webhook_signature_ok(svc.cfg.razorpay_webhook_secret, raw, x_razorpay_signature):
            raise HTTPException(400, "invalid signature")
        try:
            ev = json.loads(raw)
        except ValueError:
            raise HTTPException(400, "bad body")
        name = ev.get("event", "")
        pay = ((ev.get("payload") or {}).get("payment") or {}).get("entity") or {}
        ref = ((ev.get("payload") or {}).get("refund") or {}).get("entity") or {}
        event_id = x_razorpay_event_id or hashlib.sha256(raw).hexdigest()
        if not svc.store.first_time_event(event_id, name, pay.get("order_id"), pay.get("id") or ref.get("payment_id")):
            return {"ok": True, "duplicate": True}
        try:
            outcome = "ignored"
            if name.startswith("payment.") or name == "order.paid":
                o = svc.store.get_order_by_provider(pay.get("order_id") or "")
                if o:
                    if name == "payment.failed":
                        svc.store.mark_order(o["id"], "failed", pay.get("id"), pay.get("error_description"))
                    else:
                        _finish(o, pay, svc.config()[1])
                    outcome = svc.store.get_order(o["id"])["status"]
                else:
                    outcome = "unknown order"
            elif name in ("refund.processed", "refund.failed"):
                applied = svc.store.refund_settled(ref.get("id", ""), int(ref.get("amount") or 0),
                                                   "processed" if name == "refund.processed" else "failed")
                outcome = "refund applied" if applied else "refund already applied"
            svc.store.event_outcome(event_id, outcome)
        except HTTPException as e:
            svc.store.event_outcome(event_id, f"rejected {e.status_code}")
        except Exception:
            svc.store.forget_event(event_id)       # Razorpay retries; the retry runs it again
            raise
        return {"ok": True}

    # --- plans bought outside the app (funnels) ----------------------------------------------
    @app.post("/v1/webhooks/purchase")
    def external_purchase(body: ExternalPurchaseIn, x_webhook_secret: str = Header(""), authorization: str = Header("")):
        import hmac
        import re
        secret = getattr(svc.cfg, "funnel_webhook_secret", "") or ""
        if not (svc.store_on() and secret):
            raise HTTPException(404, "not found")
        given = x_webhook_secret or authorization.removeprefix("Bearer ").strip()
        if not given or not hmac.compare_digest(given.encode(), secret.encode()):
            raise HTTPException(401, {"error": "bad_secret", "message": "Wrong or missing X-Webhook-Secret."})
        email = body.email.strip().lower()
        if not re.match(r"^[^@\s]{1,64}@[^@\s]{1,190}\.[A-Za-z]{2,24}$", email):
            raise HTTPException(422, {"error": "invalid", "message": "email: not an email address"})
        tier = body.plan in billing.TIERS
        if tier and not body.period:
            raise HTTPException(422, {"error": "invalid", "message": "period: month or year for this plan"})
        if body.plan == "per_report" and not body.report_type:
            raise HTTPException(422, {"error": "invalid", "message": "report_type: guided or direct for a single report"})
        row, new = svc.store.record_external({
            "event_id": body.event_id.strip(), "source": body.source.strip(), "email": email, "plan": body.plan,
            "period": body.period if tier else None, "report_type": body.report_type if body.plan == "per_report" else None,
            "amount": round((body.amount or 0) * 100), "currency": body.currency,
            "payment_ref": (body.payment_id or "").strip() or None})
        if new or row["status"] == "pending":
            if svc.store.apply_external_for_email(email, svc.config()[1]):
                row = svc.store.get_external(row["event_id"]) or row
        return {"ok": True, "duplicate": not new, "status": row["status"],
                "message": {"applied": "The plan is active on their account.",
                            "pending": "No account with this email yet: the plan starts when they sign up.",
                            "cancelled": "This purchase was cancelled by an admin."}[row["status"]]}

    @app.get("/v1/admin/external-purchases")
    def admin_external(status: str | None = Query(None, pattern="^(pending|applied|cancelled)$"), a: dict = Depends(admin)):
        _need_store()
        return {"purchases": [_order_view(r) for r in svc.store.external_purchases(status)],
                "configured": bool(getattr(svc.cfg, "funnel_webhook_secret", ""))}

    @app.post("/v1/admin/external-purchases/{pid}/cancel")
    def admin_external_cancel(pid: int, body: StatusIn, a: dict = Depends(admin)):
        _need_store()
        if not svc.store.cancel_external(pid, a["id"], body.reason):
            raise HTTPException(409, {"error": "not_pending", "message": "Only a purchase still waiting can be cancelled."})
        return {"cancelled": True}

    # --- admin -------------------------------------------------------------------------
    @app.get("/v1/admin/pricing")
    def admin_pricing(a: dict = Depends(admin)):
        svc.forget_config()
        version, cfg = svc.config()
        return {"version": version, "config": cfg, "defaults": billing.DEFAULT_CONFIG,
                "active": svc.store.active_counts() if svc.store_on() else {},
                "payments_configured": svc.cfg.razorpay_configured, "byok_configured": svc.vault is not None}

    @app.get("/v1/admin/pricing/history")
    def admin_pricing_history(a: dict = Depends(admin)):
        _need_store()
        return {"history": [_order_view(r) for r in svc.store.pricing_history()]}

    @app.put("/v1/admin/pricing")
    def admin_save_pricing(body: PricingIn, a: dict = Depends(admin)):
        _need_store()
        try:
            new = billing.validate(body.config)
        except billing.ConfigError as e:
            raise HTTPException(422, {"error": "invalid_config", "problems": e.problems})
        svc.forget_config()
        _, old = svc.config()
        changes = billing.diff(old, new)
        if not changes:
            return {"version": svc.config()[0], "changes": {}}
        off = billing.newly_disabled(old, new)
        if old["enabled"] and not new["enabled"]:
            off = list(billing.PLANS)
        active = svc.store.active_counts()
        affected = {p: active.get(p, 0) for p in off if active.get(p, 0)}
        if affected and not body.confirm_disable:
            raise HTTPException(409, {"error": "confirm_disable", "affected": affected,
                                      "message": "These plans have active users. Their current plans keep working; "
                                                 "new purchases stop. Confirm to save."})
        if new["enabled"] and not svc.cfg.razorpay_configured and any(
                new["plans"][p]["enabled"] for p in ("per_report",) + billing.TIERS):
            raise HTTPException(409, {"error": "payments_unavailable",
                                      "message": "Razorpay keys are not set on the server yet."})
        version = svc.store.save_config(new, a["id"], changes)
        svc.forget_config()
        return {"version": version, "changes": changes}

    @app.get("/v1/admin/billing/users")
    def admin_billing_users(plan: str | None = Query(None, pattern="^(learn|practice|byok_scale|scale|manual)$"),
                            state: str | None = Query(None, pattern="^(active|expired|exhausted|cancelled|none|scheduled)$"),
                            q: str | None = Query(None, max_length=100),
                            payment: str | None = Query(None, pattern="^(created|pending|paid|failed|cancelled)$"),
                            since: datetime | None = None, until: datetime | None = None,
                            a: dict = Depends(admin)):
        _need_store()
        rows = svc.store.admin_users(plan, state, (q or "").strip() or None, payment, since, until)
        return {"users": [_order_view(r) for r in rows]}

    @app.get("/v1/admin/billing/users/{clinician_id}")
    def admin_billing_user(clinician_id: uuid.UUID, a: dict = Depends(admin)):
        _need_store()
        d = svc.store.admin_user(clinician_id)
        return {"entitlements": [_ent_view(e) for e in d["entitlements"]],
                "orders": [_order_view(o) for o in d["orders"]],
                "ledger": [_order_view(r) for r in d["ledger"]],
                "audit": [_order_view(r) for r in d["audit"]],
                "byok": _order_view(d["byok"]) if d["byok"] else None}

    @app.post("/v1/admin/billing/users/{clinician_id}/grant")
    def admin_billing_grant(clinician_id: uuid.UUID, body: GrantIn, a: dict = Depends(admin)):
        _need_store()
        if body.plan == "manual" and not body.credits:
            raise HTTPException(422, "credits required for a manual grant")
        e = svc.store.admin_grant(clinician_id, body.plan, a["id"], body.reason, svc.config()[1], body.credits, body.days)
        return {"entitlement": {k: _iso(v) if isinstance(v, datetime) else str(v) if isinstance(v, uuid.UUID) else v
                                for k, v in e.items()}}

    @app.post("/v1/admin/billing/users/{clinician_id}/adjust")
    def admin_billing_adjust(clinician_id: uuid.UUID, body: AdjustIn, a: dict = Depends(admin)):
        _need_store()
        if body.delta == 0:
            raise HTTPException(422, "delta must not be 0")
        try:
            svc.store.admin_adjust(clinician_id, body.delta, a["id"], body.reason)
        except billing.NoCredit:
            raise HTTPException(409, {"error": "not_enough_credits", "message": "They do not have that many unused credits."})
        return {"balance": svc.store.balance(clinician_id)}

    @app.post("/v1/admin/billing/entitlements/{ent_id}/extend")
    def admin_billing_extend(ent_id: uuid.UUID, body: ExtendIn, a: dict = Depends(admin)):
        _need_store()
        e = svc.store.admin_extend(ent_id, body.days, a["id"], body.reason)
        if not e:
            raise HTTPException(404, "not found")
        return {"expires_at": _iso(e["expires_at"])}

    @app.post("/v1/admin/billing/entitlements/{ent_id}/status")
    def admin_billing_status(ent_id: uuid.UUID, body: StatusIn, a: dict = Depends(admin)):
        _need_store()
        e = svc.store.admin_set_status(ent_id, body.active, a["id"], body.reason)
        if not e:
            raise HTTPException(404, "not found")
        return {"status": e["status"]}

    @app.get("/v1/admin/payments")
    def admin_payments(status: str | None = Query(None, pattern="^(created|pending|paid|failed|cancelled|refunded)$"),
                       plan: str | None = Query(None, pattern=
                                                "^(per_report|learn|practice|byok_scale|scale|scale_extra|print|sub_30|sub_50|byok)$"),
                       q: str | None = Query(None, max_length=100),
                       since: datetime | None = None, until: datetime | None = None, a: dict = Depends(admin)):
        _need_store()
        return {"payments": [_order_view(o) for o in
                             svc.store.admin_orders(status, plan, (q or "").strip() or None, since, until)]}

    @app.get("/v1/admin/payments/summary")
    def admin_payments_summary(since: datetime | None = None, until: datetime | None = None, a: dict = Depends(admin)):
        _need_store()
        return svc.store.revenue(since, until)

    @app.post("/v1/admin/payments/{order_id}/refund")
    def admin_refund(order_id: uuid.UUID, body: RefundIn, a: dict = Depends(admin)):
        _need_store()
        o = svc.store.get_order(order_id)
        if not o:
            raise HTTPException(404, "order not found")
        if o["status"] != "paid" or not o["provider_payment_id"] or o["provider"] != "razorpay":
            raise HTTPException(409, {"error": "not_refundable", "message": "Only a paid Razorpay order can be refunded."})
        if o["refund_status"] == "pending":
            raise HTTPException(409, {"error": "refund_pending", "message": "A refund is already in progress."})
        amount = body.amount or (o["amount"] - o["refunded_amount"])
        if amount <= 0 or amount > o["amount"] - o["refunded_amount"]:
            raise HTTPException(422, {"error": "bad_amount", "message": "More than what is left to refund."})
        if svc.razorpay is None:
            raise HTTPException(503, {"error": "payments_unavailable"})
        try:
            r = svc.razorpay.refund(o["provider_payment_id"], amount, {"order": str(o["id"]), "reason": body.reason[:200]})
        except RazorpayError as e:
            raise HTTPException(502, {"error": "refund_failed", "message": str(e)})
        svc.store.record_refund(o["id"], r["id"], amount, a["id"], body.revoke_credits, body.reason)
        if r.get("status") == "processed":
            svc.store.refund_settled(r["id"], amount, "processed")
        return {"order": _order_view(svc.store.get_order(o["id"])), "refund": {"id": r["id"], "status": r.get("status")}}

    @app.get("/v1/admin/byok/usage")
    def admin_byok_usage(days: int = Query(30, ge=1, le=366), a: dict = Depends(admin)):
        _need_store()
        return svc.store.byok_stats(days)
