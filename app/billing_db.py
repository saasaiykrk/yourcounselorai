"""
Billing data (migration 006): pricing versions, orders, entitlements, the credit ledger, webhook
events and BYOK credentials. Every credit movement runs in one transaction under a per-clinician
advisory lock, so two report requests at the same moment can never spend the same credit, and a
payment event that arrives twice can never grant twice (one entitlement per order).

Tested against a real Postgres: tests/test_billing_db.py (skipped without TEST_DATABASE_URL).
"""
from __future__ import annotations

import json
import uuid
from datetime import datetime, timedelta, timezone

from . import billing
from .billing import AlreadyCharged, InProgress, NoCredit  # noqa: F401  (raised here; defined without a database)
from .db import _conn

STALE_RESERVATION = timedelta(minutes=20)   # a report that never finished gives its credit back
CREDIT_PLANS = ("per_report", "sub_30", "sub_50", "manual")


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _lock(c, cid) -> None:
    c.execute("select pg_advisory_xact_lock(hashtextextended(%s, 0))", ("billing:" + str(cid),))


# --- pricing configuration ---------------------------------------------------------------
def get_config() -> tuple[int, dict]:
    import psycopg
    try:
        with _conn() as c:
            row = c.execute("select version, config from pricing_config order by version desc limit 1").fetchone()
    except psycopg.errors.UndefinedTable:
        row = None            # migration 006 not applied yet: pricing cannot have been switched on
    if not row:
        return 0, billing.validate({})
    return row["version"], billing.validate(row["config"])


def save_config(cfg: dict, admin_id, changes: dict) -> int:
    with _conn() as c, c.transaction():
        v = c.execute("insert into pricing_config (config, changed_by) values (%s,%s) returning version",
                      (json.dumps(cfg), str(admin_id))).fetchone()["version"]
        c.execute("insert into admin_audit (actor_id, action, target_id, detail) values (%s,'pricing_config',null,%s)",
                  (str(admin_id), json.dumps({"version": v, "changes": changes})))
        return v


def pricing_history(limit: int = 30) -> list[dict]:
    """Who changed the pricing, when, and which values (old → new)."""
    with _conn() as c:
        return c.execute("""select a.created_at, a.detail, u.email as actor_email from admin_audit a
                            left join auth.users u on u.id = a.actor_id
                            where a.action='pricing_config' order by a.id desc limit %s""", (limit,)).fetchall()


def active_counts() -> dict[str, int]:
    """Clinicians with a current entitlement per plan (for "this plan has N active subscribers")."""
    with _conn() as c:
        rows = c.execute(
            """select plan, count(distinct clinician_id) n from entitlements
               where status='active' and starts_at <= now() and (expires_at is null or expires_at > now())
                 and (plan = 'byok' or credits_used + credits_reserved < credits_total)
               group by plan""").fetchall()
    return {r["plan"]: r["n"] for r in rows}


# --- orders ----------------------------------------------------------------------------
_ORDER_COLS = """o.id, o.clinician_id, o.plan, o.report_type, o.amount, o.currency, o.config_version, o.provider,
                 o.provider_order_id, o.provider_payment_id, o.status, o.failure_reason, o.refund_status,
                 o.refunded_amount, o.created_at, o.paid_at, o.updated_at"""


def create_order(cid, price: billing.Price, config_version: int) -> dict:
    with _conn() as c:
        return c.execute(
            f"""insert into billing_orders as o (clinician_id, plan, report_type, amount, currency, config_version)
                values (%s,%s,%s,%s,%s,%s) returning {_ORDER_COLS}""",
            (str(cid), price.plan, price.report_type, price.amount, price.currency, config_version)).fetchone()


def set_provider_order(order_id, provider_order_id: str) -> None:
    with _conn() as c:
        c.execute("update billing_orders set provider_order_id=%s, updated_at=now() where id=%s",
                  (provider_order_id, str(order_id)))


def get_order(order_id, cid=None) -> dict | None:
    with _conn() as c:
        if cid is None:
            return c.execute(f"select {_ORDER_COLS} from billing_orders o where o.id=%s", (str(order_id),)).fetchone()
        return c.execute(f"select {_ORDER_COLS} from billing_orders o where o.id=%s and o.clinician_id=%s",
                         (str(order_id), str(cid))).fetchone()


def get_order_by_provider(provider_order_id: str) -> dict | None:
    with _conn() as c:
        return c.execute(f"select {_ORDER_COLS} from billing_orders o where o.provider_order_id=%s",
                         (provider_order_id,)).fetchone()


def mark_order(order_id, status: str, payment_id: str | None = None, reason: str | None = None) -> None:
    """pending / failed / cancelled. A paid order never goes back."""
    with _conn() as c:
        c.execute(
            """update billing_orders set status=%s, provider_payment_id=coalesce(%s, provider_payment_id),
                 failure_reason=%s, updated_at=now()
               where id=%s and status <> 'paid'""",
            (status, payment_id, (reason or "")[:300] or None, str(order_id)))


def cancel_order(order_id, cid) -> bool:
    with _conn() as c:
        row = c.execute("""update billing_orders set status='cancelled', updated_at=now()
                           where id=%s and clinician_id=%s and status='created' returning id""",
                        (str(order_id), str(cid))).fetchone()
        return row is not None


def fulfil(order_id, payment_id: str, cfg: dict) -> dict:
    """Marks the order paid and grants its entitlement, once. Safe to call again for the same order
    (checkout callback, webhook, retry): it returns the entitlement already granted."""
    with _conn() as c, c.transaction():
        o = c.execute("select * from billing_orders where id=%s for update", (str(order_id),)).fetchone()
        if o is None:
            raise LookupError("order not found")
        _lock(c, o["clinician_id"])
        ent = c.execute("select * from entitlements where order_id=%s", (str(order_id),)).fetchone()
        if ent:
            return dict(ent)
        if o["status"] == "paid":
            raise RuntimeError("paid order without an entitlement")
        c.execute("""update billing_orders set status='paid', provider_payment_id=coalesce(%s, provider_payment_id),
                       paid_at=now(), failure_reason=null, updated_at=now() where id=%s""",
                  (payment_id, str(order_id)))
        return _grant(c, o["clinician_id"], o["plan"], o, cfg)


def _grant(c, cid, plan: str, order: dict | None, cfg: dict, *, credits: int | None = None, days: int | None = None,
           actor=None, note: str | None = None) -> dict:
    now = _now()
    p = cfg["plans"].get(plan, {})
    starts, expires, report_type = now, None, None
    if plan == "per_report":
        credits, report_type = 1, order["report_type"]
    elif plan in ("sub_30", "sub_50"):
        credits = p["reports"] if credits is None else credits
        days = p["duration_days"] if days is None else days
        expires = now + timedelta(days=days)
    elif plan == "byok":
        credits = 0
        days = p["fee_days"] if days is None else days
        last = c.execute("""select max(expires_at) e from entitlements where clinician_id=%s and plan='byok'
                              and status='active' and expires_at > %s""", (str(cid), now)).fetchone()["e"]
        starts = max(now, last) if last else now      # a renewal never cuts short a paid period
        expires = starts + timedelta(days=days)
    else:  # manual
        expires = now + timedelta(days=days) if days else None
    ent = c.execute(
        """insert into entitlements (clinician_id, plan, report_type, credits_total, starts_at, expires_at, order_id,
                                      note, created_by)
           values (%s,%s,%s,%s,%s,%s,%s,%s,%s) returning *""",
        (str(cid), plan, report_type, credits, starts, expires, str(order["id"]) if order else None, note,
         str(actor) if actor else None)).fetchone()
    if credits:
        c.execute("""insert into credit_ledger (clinician_id, entitlement_id, kind, amount, report_type, order_id,
                                                actor_id, reason) values (%s,%s,'grant',%s,%s,%s,%s,%s)""",
                  (str(cid), str(ent["id"]), credits, report_type, str(order["id"]) if order else None,
                   str(actor) if actor else None, note))
    if plan in ("sub_30", "sub_50") and cfg.get("rollover"):
        # Unused credits of a running subscription stay usable until the new period ends.
        c.execute("""update entitlements set expires_at=%s
                     where clinician_id=%s and plan in ('sub_30','sub_50') and status='active' and id<>%s
                       and expires_at > %s and credits_used + credits_reserved < credits_total""",
                  (expires, str(cid), str(ent["id"]), now))
    return dict(ent)


# --- webhook events ----------------------------------------------------------------------
def first_time_event(event_id: str, event: str, provider_order_id: str | None, payment_id: str | None) -> bool:
    """True the first time a webhook event id is seen; False for Razorpay's retries."""
    with _conn() as c:
        row = c.execute(
            """insert into payment_events (id, event, provider_order_id, provider_payment_id) values (%s,%s,%s,%s)
               on conflict (id) do nothing returning id""",
            (event_id, event, provider_order_id, payment_id)).fetchone()
        return row is not None


def event_outcome(event_id: str, outcome: str) -> None:
    with _conn() as c:
        c.execute("update payment_events set outcome=%s where id=%s", (outcome[:200], event_id))


def forget_event(event_id: str) -> None:
    """Processing failed: let Razorpay's retry run it again."""
    with _conn() as c:
        c.execute("delete from payment_events where id=%s", (event_id,))


# --- credits ---------------------------------------------------------------------------
def _release_stale(c, cid) -> None:
    stale = c.execute(
        """select r.request_key, r.entitlement_id from credit_ledger r
           where r.clinician_id=%s and r.kind='reserve' and r.created_at < %s
             and (select count(*) from credit_ledger x where x.clinician_id=r.clinician_id
                    and x.request_key=r.request_key and x.kind in ('consume','release'))
                 < (select count(*) from credit_ledger y where y.clinician_id=r.clinician_id
                    and y.request_key=r.request_key and y.kind='reserve')""",
        (str(cid), _now() - STALE_RESERVATION)).fetchall()
    for s in stale:
        _undo_reserve(c, cid, s["request_key"], s["entitlement_id"], "stale reservation released")


def _open_reservation(c, cid, key: str):
    rows = c.execute("""select kind, entitlement_id from credit_ledger where clinician_id=%s and request_key=%s
                        order by id""", (str(cid), key)).fetchall()
    opened = [r for r in rows if r["kind"] == "reserve"]
    closed = [r for r in rows if r["kind"] in ("consume", "release")]
    return opened[-1]["entitlement_id"] if len(opened) > len(closed) else None


def _undo_reserve(c, cid, key, ent_id, reason: str) -> None:
    c.execute("update entitlements set credits_reserved = credits_reserved - 1 where id=%s and credits_reserved > 0",
              (str(ent_id),))
    c.execute("""insert into credit_ledger (clinician_id, entitlement_id, kind, amount, request_key, reason)
                 values (%s,%s,'release',1,%s,%s)""", (str(cid), str(ent_id), key, reason[:200]))


def reserve(cid, report_type: str, request_key: str) -> str:
    """Holds one credit for this report. Raises AlreadyCharged, InProgress or NoCredit."""
    with _conn() as c, c.transaction():
        _lock(c, cid)
        _release_stale(c, cid)
        if c.execute("select 1 from credit_ledger where clinician_id=%s and request_key=%s and kind='consume'",
                     (str(cid), request_key)).fetchone():
            raise AlreadyCharged()
        if _open_reservation(c, cid, request_key):
            raise InProgress()
        ent = c.execute(
            """select id from entitlements
               where clinician_id=%s and status='active' and starts_at <= now()
                 and (expires_at is null or expires_at > now())
                 and credits_used + credits_reserved < credits_total
                 and (plan in ('sub_30','sub_50','manual') or (plan='per_report' and report_type=%s))
               order by expires_at nulls last, created_at limit 1 for update""",
            (str(cid), report_type)).fetchone()
        if not ent:
            raise NoCredit()
        c.execute("update entitlements set credits_reserved = credits_reserved + 1 where id=%s", (str(ent["id"]),))
        c.execute("""insert into credit_ledger (clinician_id, entitlement_id, kind, amount, report_type, request_key)
                     values (%s,%s,'reserve',-1,%s,%s)""", (str(cid), str(ent["id"]), report_type, request_key))
        return str(ent["id"])


def consume(cid, request_key: str) -> None:
    """The report was delivered: the held credit is spent."""
    with _conn() as c, c.transaction():
        _lock(c, cid)
        ent_id = _open_reservation(c, cid, request_key)
        if ent_id is None:
            return
        c.execute("""update entitlements set credits_reserved = credits_reserved - 1, credits_used = credits_used + 1
                     where id=%s""", (str(ent_id),))
        c.execute("""insert into credit_ledger (clinician_id, entitlement_id, kind, amount, request_key)
                     values (%s,%s,'consume',0,%s)""", (str(cid), str(ent_id), request_key))


def release(cid, request_key: str, reason: str) -> None:
    """The report failed or was held back: the held credit is given back."""
    with _conn() as c, c.transaction():
        _lock(c, cid)
        ent_id = _open_reservation(c, cid, request_key)
        if ent_id is not None:
            _undo_reserve(c, cid, request_key, ent_id, reason)


def was_charged(cid, request_key: str) -> bool:
    with _conn() as c:
        return c.execute("select 1 from credit_ledger where clinician_id=%s and request_key=%s and kind='consume'",
                         (str(cid), request_key)).fetchone() is not None


def byok_access(cid) -> bool:
    with _conn() as c:
        return c.execute("""select 1 from entitlements where clinician_id=%s and plan='byok' and status='active'
                              and starts_at <= now() and expires_at > now() limit 1""", (str(cid),)).fetchone() is not None


def _state(e: dict, now: datetime) -> str:
    if e["status"] == "cancelled":
        return "cancelled"
    if e["expires_at"] and e["expires_at"] <= now:
        return "expired"
    if e["starts_at"] > now:
        return "scheduled"
    if e["plan"] != "byok" and e["credits_used"] + e["credits_reserved"] >= e["credits_total"]:
        return "exhausted"
    return "active"


def entitlements(cid, include_old: bool = True) -> list[dict]:
    """Every entitlement with its state and remaining credits; records expiry in the ledger once."""
    now = _now()
    with _conn() as c, c.transaction():
        rows = [dict(r) for r in c.execute("select * from entitlements where clinician_id=%s order by created_at desc",
                                           (str(cid),)).fetchall()]
        for e in rows:
            e["state"] = _state(e, now)
            e["remaining"] = max(0, e["credits_total"] - e["credits_used"] - e["credits_reserved"])
            if e["state"] == "expired" and e["remaining"] > 0:
                c.execute("""insert into credit_ledger (clinician_id, entitlement_id, kind, amount, reason)
                             values (%s,%s,'expire',%s,'period ended') on conflict do nothing""",
                          (str(cid), str(e["id"]), -e["remaining"]))
    return [e for e in rows if include_old or e["state"] in ("active", "scheduled")]


def balance(cid) -> dict:
    """Usable credits now: {"guided": n, "direct": n, "any": n} (any = subscription/admin credits)."""
    ents = [e for e in entitlements(cid) if e["state"] == "active" and e["plan"] in CREDIT_PLANS]
    anyc = sum(e["remaining"] for e in ents if e["plan"] != "per_report")
    out = {"any": anyc}
    for t in billing.REPORT_TYPES:
        out[t] = anyc + sum(e["remaining"] for e in ents if e["plan"] == "per_report" and e["report_type"] == t)
    return out


def ledger(cid, limit: int = 100) -> list[dict]:
    with _conn() as c:
        return c.execute("""select id, entitlement_id, kind, amount, report_type, order_id, reason, created_at
                            from credit_ledger where clinician_id=%s order by id desc limit %s""",
                         (str(cid), limit)).fetchall()


def orders(cid, limit: int = 100) -> list[dict]:
    with _conn() as c:
        return c.execute(f"select {_ORDER_COLS} from billing_orders o where o.clinician_id=%s "
                         f"order by o.created_at desc limit %s", (str(cid), limit)).fetchall()


# --- admin -----------------------------------------------------------------------------
def admin_grant(cid, plan: str, admin_id, reason: str, cfg: dict, credits: int | None, days: int | None) -> dict:
    """Manual activation (no payment): a subscription plan's allowance, or a "manual" credit grant."""
    with _conn() as c, c.transaction():
        _lock(c, cid)
        ent = _grant(c, cid, plan, None, cfg, credits=credits, days=days, actor=admin_id, note=reason)
        _audit(c, admin_id, "billing_grant", cid, {"plan": plan, "credits": ent["credits_total"],
                                                    "expires_at": str(ent["expires_at"]), "reason": reason})
        return ent


def admin_extend(ent_id, days: int, admin_id, reason: str) -> dict | None:
    with _conn() as c, c.transaction():
        e = c.execute("select * from entitlements where id=%s for update", (str(ent_id),)).fetchone()
        if not e:
            return None
        base = max(e["expires_at"] or _now(), _now())
        row = c.execute("update entitlements set expires_at=%s, status='active' where id=%s returning *",
                        (base + timedelta(days=days), str(ent_id))).fetchone()
        _audit(c, admin_id, "billing_extend", e["clinician_id"],
               {"entitlement": str(ent_id), "days": days, "old_expiry": str(e["expires_at"]),
                "new_expiry": str(row["expires_at"]), "reason": reason})
        return dict(row)


def admin_set_status(ent_id, active: bool, admin_id, reason: str) -> dict | None:
    """Deactivate (cancel) or reactivate an entitlement. Not a refund: no money moves."""
    with _conn() as c, c.transaction():
        e = c.execute("select * from entitlements where id=%s for update", (str(ent_id),)).fetchone()
        if not e:
            return None
        row = c.execute("update entitlements set status=%s where id=%s returning *",
                        ("active" if active else "cancelled", str(ent_id))).fetchone()
        remaining = e["credits_total"] - e["credits_used"] - e["credits_reserved"]
        if not active and remaining > 0:
            c.execute("""insert into credit_ledger (clinician_id, entitlement_id, kind, amount, actor_id, reason)
                         values (%s,%s,'revoke',%s,%s,%s)""", (str(e["clinician_id"]), str(ent_id), -remaining,
                                                               str(admin_id), reason))
        _audit(c, admin_id, "billing_activate" if active else "billing_deactivate", e["clinician_id"],
               {"entitlement": str(ent_id), "reason": reason})
        return dict(row)


def admin_adjust(cid, delta: int, admin_id, reason: str) -> None:
    """+n: a manual grant of n credits (no expiry). −n: removes n unused credits, soonest-expiring first."""
    with _conn() as c, c.transaction():
        _lock(c, cid)
        if delta > 0:
            ent = c.execute("""insert into entitlements (clinician_id, plan, credits_total, note, created_by)
                               values (%s,'manual',%s,%s,%s) returning id""",
                            (str(cid), delta, reason, str(admin_id))).fetchone()
            c.execute("""insert into credit_ledger (clinician_id, entitlement_id, kind, amount, actor_id, reason)
                         values (%s,%s,'adjust',%s,%s,%s)""", (str(cid), str(ent["id"]), delta, str(admin_id), reason))
        else:
            left = -delta
            rows = c.execute(
                """select id, credits_total - credits_used - credits_reserved r from entitlements
                   where clinician_id=%s and status='active' and (expires_at is null or expires_at > now())
                     and plan <> 'byok' and credits_used + credits_reserved < credits_total
                   order by expires_at nulls last, created_at for update""", (str(cid),)).fetchall()
            if sum(r["r"] for r in rows) < left:
                raise NoCredit()
            for r in rows:
                take = min(left, r["r"])
                if take <= 0:
                    break
                c.execute("update entitlements set credits_total = credits_total - %s where id=%s", (take, str(r["id"])))
                c.execute("""insert into credit_ledger (clinician_id, entitlement_id, kind, amount, actor_id, reason)
                             values (%s,%s,'adjust',%s,%s,%s)""", (str(cid), str(r["id"]), -take, str(admin_id), reason))
                left -= take
        _audit(c, admin_id, "billing_adjust", cid, {"delta": delta, "reason": reason})


def record_refund(order_id, refund_id: str, amount: int, admin_id, revoke: bool, reason: str) -> None:
    """A refund requested through Razorpay: pending until Razorpay reports it processed (refund_settled).
    Optionally cancels the order's remaining credits. Money only ever moves through Razorpay's refund."""
    with _conn() as c, c.transaction():
        o = c.execute("select * from billing_orders where id=%s for update", (str(order_id),)).fetchone()
        c.execute("""update billing_orders set refund_status='pending', provider_refund_id=%s, updated_at=now()
                     where id=%s""", (refund_id, str(order_id)))
        if revoke:
            e = c.execute("select * from entitlements where order_id=%s for update", (str(order_id),)).fetchone()
            if e and e["status"] == "active":
                c.execute("update entitlements set status='cancelled' where id=%s", (str(e["id"]),))
                remaining = e["credits_total"] - e["credits_used"] - e["credits_reserved"]
                if remaining > 0:
                    c.execute("""insert into credit_ledger (clinician_id, entitlement_id, kind, amount, order_id,
                                   actor_id, reason) values (%s,%s,'revoke',%s,%s,%s,%s)""",
                              (str(o["clinician_id"]), str(e["id"]), -remaining, str(order_id), str(admin_id),
                               "refund"))
        _audit(c, admin_id, "billing_refund", o["clinician_id"],
               {"order": str(order_id), "amount": amount, "refund": refund_id, "revoke": revoke, "reason": reason})


def refund_settled(provider_refund_id: str, amount: int, status: str) -> bool:
    """Razorpay says the refund was processed (or failed). Applied once per refund: a repeated
    report finds the refund no longer pending and changes nothing."""
    with _conn() as c:
        row = c.execute(
            """update billing_orders set
                 refunded_amount = refunded_amount + case when %(st)s='processed' then %(amt)s else 0 end,
                 refund_status = case when %(st)s <> 'processed' then 'failed'
                                      when refunded_amount + %(amt)s >= amount then 'refunded' else 'partial' end,
                 updated_at = now()
               where provider_refund_id=%(rid)s and refund_status='pending' returning id""",
            {"st": status, "amt": amount, "rid": provider_refund_id}).fetchone()
        return row is not None


def _audit(c, admin_id, action: str, target, detail: dict) -> None:
    c.execute("insert into admin_audit (actor_id, action, target_id, detail) values (%s,%s,%s,%s)",
              (str(admin_id), action, str(target), json.dumps(detail, default=str)))


def admin_users(plan: str | None, state: str | None, q: str | None, pay: str | None,
                since=None, until=None, limit: int = 200) -> list[dict]:
    """Clinicians with their latest subscription-type entitlement, credits and last payment."""
    with _conn() as c:
        rows = c.execute(
            """select c.id, c.full_name, u.email, c.level, c.verification_status,
                 (select row_to_json(e) from (select id, plan, status, credits_total, credits_used, credits_reserved,
                    starts_at, expires_at, created_at from entitlements where clinician_id=c.id and plan <> 'per_report'
                    order by created_at desc limit 1) e) as latest,
                 (select coalesce(sum(credits_total - credits_used - credits_reserved), 0) from entitlements
                    where clinician_id=c.id and status='active' and starts_at <= now()
                      and (expires_at is null or expires_at > now()) and plan <> 'byok') as remaining,
                 (select count(*) from credit_ledger where clinician_id=c.id and kind='consume') as reports_charged,
                 (select row_to_json(o) from (select id, plan, status, amount, currency, provider_order_id,
                    provider_payment_id, created_at, paid_at, refund_status from billing_orders
                    where clinician_id=c.id order by created_at desc limit 1) o) as last_order,
                 (select status from byok_credentials where clinician_id=c.id) as byok_status
               from clinicians c left join auth.users u on u.id = c.id
               where (%(q)s::text is null or c.full_name ilike %(like)s or u.email ilike %(like)s
                      or c.id::text = %(q)s)
               order by c.created_at desc limit %(limit)s""",
            {"q": q, "like": f"%{q}%" if q else None, "limit": limit}).fetchall()
    now = _now()
    out = []
    for r in rows:
        r = dict(r)
        lat = r["latest"]
        if lat:
            for k in ("starts_at", "expires_at", "created_at"):
                if lat.get(k):
                    lat[k] = datetime.fromisoformat(lat[k])
            lat["state"] = _state(lat, now)
        r["state"] = lat["state"] if lat else "none"
        r["plan"] = lat["plan"] if lat else None
        lo = r["last_order"]
        if plan and r["plan"] != plan:
            continue
        if state and r["state"] != state:
            continue
        if pay and (not lo or lo["status"] != pay):
            continue
        if since and (not lat or lat["created_at"] < since):
            continue
        if until and (not lat or not lat.get("expires_at") or lat["expires_at"] > until):
            continue
        out.append(r)
    return out


def admin_user(cid) -> dict:
    with _conn() as c:
        audit = c.execute("""select a.created_at, a.action, a.detail, a.actor_id, u.email as actor_email
                             from admin_audit a left join auth.users u on u.id = a.actor_id
                             where a.target_id=%s and a.action like 'billing_%%' order by a.id desc limit 100""",
                          (str(cid),)).fetchall()
        byok = c.execute("select last4, status, last_error, validated_at, updated_at from byok_credentials "
                         "where clinician_id=%s", (str(cid),)).fetchone()
    return {"entitlements": entitlements(cid), "orders": orders(cid), "ledger": ledger(cid, 200),
            "audit": audit, "byok": byok}


def admin_orders(status: str | None, plan: str | None, q: str | None, since=None, until=None,
                 limit: int = 300) -> list[dict]:
    with _conn() as c:
        return c.execute(
            f"""select {_ORDER_COLS}, c.full_name, u.email, e.id as entitlement_id
                from billing_orders o join clinicians c on c.id=o.clinician_id left join auth.users u on u.id=c.id
                left join entitlements e on e.order_id=o.id
                where (%(status)s::text is null or o.status=%(status)s or (%(status)s='refunded' and o.refund_status is not null))
                  and (%(plan)s::text is null or o.plan=%(plan)s)
                  and (%(since)s::timestamptz is null or o.created_at >= %(since)s)
                  and (%(until)s::timestamptz is null or o.created_at < %(until)s)
                  and (%(q)s::text is null or o.id::text=%(q)s or o.provider_order_id=%(q)s or o.provider_payment_id=%(q)s
                       or c.full_name ilike %(like)s or u.email ilike %(like)s)
                order by o.created_at desc limit %(limit)s""",
            {"status": status, "plan": plan, "since": since, "until": until, "q": q,
             "like": f"%{q}%" if q else None, "limit": limit}).fetchall()


def revenue(since=None, until=None) -> dict:
    """Per plan: collected (paid minus refunded), refunded, pending and failed — in minor units.
    Only paid orders count as collected."""
    with _conn() as c:
        rows = c.execute(
            """select plan, currency,
                 coalesce(sum(amount - refunded_amount) filter (where status='paid'), 0) collected,
                 coalesce(sum(refunded_amount) filter (where status='paid'), 0) refunded,
                 count(*) filter (where status='paid') paid_count,
                 coalesce(sum(amount) filter (where status in ('created','pending')), 0) pending,
                 count(*) filter (where status in ('created','pending')) pending_count,
                 coalesce(sum(amount) filter (where status='failed'), 0) failed,
                 count(*) filter (where status='failed') failed_count
               from billing_orders
               where (%(since)s::timestamptz is null or created_at >= %(since)s)
                 and (%(until)s::timestamptz is null or created_at < %(until)s)
               group by plan, currency order by plan""", {"since": since, "until": until}).fetchall()
    return {"by_plan": rows}


# --- BYOK ------------------------------------------------------------------------------
def byok_get(cid) -> dict | None:
    with _conn() as c:
        return c.execute("select * from byok_credentials where clinician_id=%s", (str(cid),)).fetchone()


def byok_save(cid, sealed, status: str, error: str | None) -> None:
    with _conn() as c:
        c.execute(
            """insert into byok_credentials (clinician_id, ciphertext, nonce, key_version, last4, status, last_error,
                                              validated_at)
               values (%s,%s,%s,%s,%s,%s,%s, now())
               on conflict (clinician_id) do update set ciphertext=excluded.ciphertext, nonce=excluded.nonce,
                 key_version=excluded.key_version, last4=excluded.last4, status=excluded.status,
                 last_error=excluded.last_error, validated_at=now(), updated_at=now()""",
            (str(cid), sealed.ciphertext, sealed.nonce, sealed.key_version, sealed.last4, status, error))


def byok_mark(cid, status: str, error: str | None) -> None:
    with _conn() as c:
        c.execute("""update byok_credentials set status=%s, last_error=%s, validated_at=now(), updated_at=now()
                     where clinician_id=%s""", (status, error, str(cid)))


def byok_delete(cid) -> bool:
    with _conn() as c:
        return c.execute("delete from byok_credentials where clinician_id=%s returning clinician_id",
                         (str(cid),)).fetchone() is not None


def byok_log(cid, report_type: str, outcome: str) -> None:
    with _conn() as c:
        c.execute("insert into byok_usage (clinician_id, report_type, outcome) values (%s,%s,%s)",
                  (str(cid), report_type, outcome))


def byok_stats(days: int = 30) -> dict:
    with _conn() as c:
        rows = c.execute("""select outcome, report_type, count(*) n, count(distinct clinician_id) clinicians
                            from byok_usage where created_at > now() - make_interval(days => %s)
                            group by outcome, report_type order by outcome""", (days,)).fetchall()
        keys = c.execute("select status, count(*) n from byok_credentials group by status").fetchall()
    return {"days": days, "usage": rows, "keys": {r["status"]: r["n"] for r in keys}}


def new_request_key() -> str:
    return uuid.uuid4().hex
