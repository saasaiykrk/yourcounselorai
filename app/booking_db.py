"""
Booking data (migration 007): settings, working hours, time off, appointments, notifications.

Every change to a consultant's appointments runs in one transaction under a per-consultant advisory
lock, re-checks availability inside that lock, and is backed by the appointments_no_overlap
exclusion constraint, so two requests for the same time can never both succeed.
Client details arrive already sealed (app/booking.py); nothing here reads or logs them.
"""
from __future__ import annotations

import json
from datetime import date, datetime, timedelta, timezone

import psycopg

from . import booking
from .db import _conn

UTC = timezone.utc
RETENTION_DAYS = 90


class SlugTaken(Exception):
    pass


class SlotTaken(Exception):
    """The time is no longer free (booked, blocked, outside hours or notice)."""


class TooMany(Exception):
    """This email already holds the maximum number of upcoming bookings with this consultant."""


class NotAllowed(Exception):
    """The change does not fit the appointment's state (e.g. confirming a cancelled one)."""


def _now() -> datetime:
    return datetime.now(UTC)


def _lock(c, cid) -> None:
    c.execute("select pg_advisory_xact_lock(hashtextextended(%s, 0))", ("booking:" + str(cid),))


# --- settings, hours, time off ----------------------------------------------------------------
def get_settings(cid) -> dict | None:
    with _conn() as c:
        return c.execute("select * from booking_settings where clinician_id=%s", (str(cid),)).fetchone()


def public_settings(slug: str) -> dict | None:
    """Settings of an enabled booking page whose consultant is verified, else None."""
    with _conn() as c:
        return c.execute(
            """select s.*, c.role from booking_settings s join clinicians c on c.id = s.clinician_id
               where s.slug=%s and s.enabled and c.verification_status='verified'""", (slug,)).fetchone()


def save_settings(cid, s: dict) -> dict:
    cols = ("slug", "enabled", "display_name", "bio", "timezone", "slot_minutes", "buffer_minutes",
            "min_notice_minutes", "max_advance_days", "approval")
    try:
        with _conn() as c:
            return c.execute(
                f"""insert into booking_settings (clinician_id, {', '.join(cols)}) values (%s, {', '.join(['%s'] * len(cols))})
                    on conflict (clinician_id) do update set {', '.join(f'{k}=excluded.{k}' for k in cols)}, updated_at=now()
                    returning *""", (str(cid), *[s[k] for k in cols])).fetchone()
    except psycopg.errors.UniqueViolation:
        raise SlugTaken()


def slug_free(slug: str, cid) -> bool:
    with _conn() as c:
        return c.execute("select 1 from booking_settings where slug=%s and clinician_id<>%s",
                         (slug, str(cid))).fetchone() is None


def windows(cid) -> list[tuple]:
    with _conn() as c:
        rows = c.execute("select weekday, start_time, end_time from availability_windows where clinician_id=%s "
                         "order by weekday, start_time", (str(cid),)).fetchall()
    return [(r["weekday"], r["start_time"], r["end_time"]) for r in rows]


def save_windows(cid, ws: list[tuple]) -> None:
    with _conn() as c, c.transaction():
        c.execute("delete from availability_windows where clinician_id=%s", (str(cid),))
        for wd, a, b in ws:
            c.execute("insert into availability_windows (clinician_id, weekday, start_time, end_time) values (%s,%s,%s,%s)",
                      (str(cid), wd, a, b))


def time_off(cid, since: datetime | None = None) -> list[dict]:
    with _conn() as c:
        return c.execute("select id, starts_at, ends_at, label from time_off where clinician_id=%s and ends_at > %s "
                         "order by starts_at", (str(cid), since or _now())).fetchall()


def add_time_off(cid, starts_at: datetime, ends_at: datetime, label: str) -> dict:
    with _conn() as c:
        return c.execute("insert into time_off (clinician_id, starts_at, ends_at, label) values (%s,%s,%s,%s) "
                         "returning id, starts_at, ends_at, label", (str(cid), starts_at, ends_at, label)).fetchone()


def delete_time_off(cid, off_id: int) -> bool:
    with _conn() as c:
        return c.execute("delete from time_off where id=%s and clinician_id=%s", (off_id, str(cid))).rowcount > 0


# --- availability ------------------------------------------------------------------------------
def _tidy(c, cid) -> None:
    """Expire unanswered requests and mark past confirmed appointments completed (lazy, idempotent)."""
    now = _now()
    c.execute("""update appointments set status='expired', cancelled_by='system', updated_at=now()
                 where clinician_id=%s and status='pending' and (pending_until < %s or starts_at < %s)""",
              (str(cid), now, now))
    c.execute("""update appointments set status='completed', updated_at=now()
                 where clinician_id=%s and status='confirmed' and ends_at < %s""", (str(cid), now))


def _busy(c, cid, start: datetime, end: datetime, ignore: str | None = None) -> list[tuple]:
    rows = c.execute("""select starts_at, blocked_until from appointments where clinician_id=%s
                        and status in ('pending','confirmed') and starts_at < %s and blocked_until > %s
                        and (%s::uuid is null or id <> %s::uuid)""",
                     (str(cid), end, start, ignore, ignore)).fetchall()
    return [(r["starts_at"], r["blocked_until"]) for r in rows]


def _off(c, cid, start: datetime, end: datetime) -> list[tuple]:
    rows = c.execute("select starts_at, ends_at from time_off where clinician_id=%s and starts_at < %s and ends_at > %s",
                     (str(cid), end, start)).fetchall()
    return [(r["starts_at"], r["ends_at"]) for r in rows]


def free_slots(cid, settings: dict, first_day: date, days: int, honour_notice: bool = True,
               ignore: str | None = None, conn=None) -> dict[date, list[datetime]]:
    """Free slots for local dates first_day … +days (consultant timezone)."""
    rules = booking.Rules.of(settings)
    tz = booking.zone(settings["timezone"])
    lo = datetime.combine(first_day - timedelta(days=1), datetime.min.time(), tzinfo=tz).astimezone(UTC)
    hi = datetime.combine(first_day + timedelta(days=days + 1), datetime.min.time(), tzinfo=tz).astimezone(UTC)

    def run(c):
        _tidy(c, cid)
        ws = [(r["weekday"], r["start_time"], r["end_time"]) for r in c.execute(
            "select weekday, start_time, end_time from availability_windows where clinician_id=%s", (str(cid),)).fetchall()]
        return booking.free_slots(rules, ws, _off(c, cid, lo, hi), _busy(c, cid, lo, hi, ignore), _now(),
                                  first_day, days, honour_notice)
    if conn is not None:
        return run(conn)
    with _conn() as c, c.transaction():
        return run(c)


# --- appointments --------------------------------------------------------------------------------
def book(cid, settings: dict, starts_at: datetime, *, source: str, sealer, details: dict | None,
         email_hash: str | None, manage_hash: str | None, status: str, appointment_id: str,
         check_hours: bool = True) -> dict:
    """Create one appointment, or raise SlotTaken / TooMany. Availability is re-checked inside the
    consultant's lock; the exclusion constraint is the last line of defence."""
    slot = timedelta(minutes=settings["slot_minutes"])
    buf = timedelta(minutes=settings["buffer_minutes"])
    try:
        with _conn() as c, c.transaction():
            _lock(c, cid)
            _tidy(c, cid)
            if check_hours:
                day = booking.local_date(starts_at, settings["timezone"])
                if starts_at not in free_slots(cid, settings, day, 1, conn=c).get(day, []):
                    raise SlotTaken()
            elif _busy(c, cid, starts_at, starts_at + slot + buf) or _off(c, cid, starts_at, starts_at + slot) \
                    or starts_at < _now():
                raise SlotTaken()
            if email_hash:
                n = c.execute("""select count(*) n from appointments where clinician_id=%s and email_hash=%s
                                 and status in ('pending','confirmed') and starts_at > now()""",
                              (str(cid), email_hash)).fetchone()["n"]
                if n >= booking.MAX_ACTIVE_PER_EMAIL:
                    raise TooMany()
            ct = nonce = ver = None
            if details:
                ct, nonce, ver = sealer.seal(appointment_id, details)
            pending_until = min(_now() + timedelta(hours=booking.PENDING_HOURS), starts_at) if status == "pending" else None
            row = c.execute(
                """insert into appointments (id, clinician_id, starts_at, ends_at, blocked_until, status, source,
                     client_ct, client_nonce, client_key_ver, email_hash, manage_hash, consent_at, pending_until)
                   values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) returning *""",
                (appointment_id, str(cid), starts_at, starts_at + slot, starts_at + slot + buf, status, source,
                 ct, nonce, ver, email_hash, manage_hash, _now() if source == "public" else None, pending_until)).fetchone()
            _notify_new(c, row)
            return row
    except psycopg.errors.ExclusionViolation:
        raise SlotTaken()


def _enqueue(c, appt_id, kind: str, recipient: str, due_at: datetime | None = None) -> None:
    c.execute("insert into booking_notifications (appointment_id, kind, recipient, due_at) values (%s,%s,%s,%s)",
              (str(appt_id), kind, recipient, due_at or _now()))


def _reminder(c, row) -> None:
    due = row["starts_at"] - timedelta(hours=24)
    if row["client_ct"] is not None and due > _now():
        _enqueue(c, row["id"], "reminder", "client", due)


def _notify_new(c, row) -> None:
    if row["source"] != "public":                     # added by the consultant: tell the client, if an email was given
        if row["client_ct"] is not None:
            _enqueue(c, row["id"], "confirmed", "client")
            _reminder(c, row)
        return
    _enqueue(c, row["id"], "new_booking", "consultant")
    _enqueue(c, row["id"], "confirmed" if row["status"] == "confirmed" else "requested", "client")
    if row["status"] == "confirmed":
        _reminder(c, row)


def get(appt_id, cid=None) -> dict | None:
    with _conn() as c:
        return c.execute("select * from appointments where id=%s and (%s::uuid is null or clinician_id=%s::uuid)",
                         (str(appt_id), cid and str(cid), cid and str(cid))).fetchone()


def by_manage_hash(h: str) -> dict | None:
    with _conn() as c:
        return c.execute("select * from appointments where manage_hash=%s", (h,)).fetchone()


def list_between(cid, start: datetime, end: datetime) -> list[dict]:
    with _conn() as c, c.transaction():
        _tidy(c, cid)
        return c.execute("select * from appointments where clinician_id=%s and starts_at < %s and ends_at > %s "
                         "order by starts_at", (str(cid), end, start)).fetchall()


_MOVES = {
    "confirm": ({"pending"}, "confirmed"),
    "reject": ({"pending"}, "rejected"),
    "cancel": ({"pending", "confirmed"}, "cancelled"),
    "complete": ({"confirmed"}, "completed"),
}


def transition(appt_id, cid, action: str, by: str = "consultant") -> dict:
    allowed, new = _MOVES[action]
    with _conn() as c, c.transaction():
        _lock(c, cid)
        _tidy(c, cid)
        row = c.execute("select * from appointments where id=%s and clinician_id=%s for update",
                        (str(appt_id), str(cid))).fetchone()
        if row is None:
            raise LookupError()
        if row["status"] not in allowed or (action == "complete" and row["starts_at"] > _now()):
            raise NotAllowed()
        row = c.execute("""update appointments set status=%s, cancelled_by=%s, pending_until=null, updated_at=now()
                           where id=%s returning *""",
                        (new, by if new in ("cancelled", "rejected") else None, str(appt_id))).fetchone()
        if row["client_ct"] is not None and new in ("confirmed", "rejected", "cancelled"):
            _enqueue(c, row["id"], new, "client")
        if new == "confirmed":
            _reminder(c, row)
        if new == "cancelled" and by == "client":
            _enqueue(c, row["id"], "cancelled", "consultant")
        if new in ("cancelled", "rejected"):
            c.execute("update booking_notifications set status='failed' where appointment_id=%s and kind='reminder' "
                      "and status='pending'", (str(appt_id),))
        return row


def reschedule(appt_id, cid, settings: dict, new_start: datetime, new_id: str, sealer=None,
               check_hours: bool = True) -> dict:
    """Moves an appointment: the old row becomes 'rescheduled' (freeing its time), a new confirmed row
    takes the new time with the same client details and manage link. One transaction: all or nothing."""
    slot = timedelta(minutes=settings["slot_minutes"])
    buf = timedelta(minutes=settings["buffer_minutes"])
    try:
        with _conn() as c, c.transaction():
            _lock(c, cid)
            _tidy(c, cid)
            old = c.execute("select * from appointments where id=%s and clinician_id=%s for update",
                            (str(appt_id), str(cid))).fetchone()
            if old is None:
                raise LookupError()
            if old["status"] not in booking.ACTIVE:
                raise NotAllowed()
            if check_hours:
                day = booking.local_date(new_start, settings["timezone"])
                if new_start not in free_slots(cid, settings, day, 1, ignore=str(appt_id), conn=c).get(day, []):
                    raise SlotTaken()
            elif _busy(c, cid, new_start, new_start + slot + buf, ignore=str(appt_id)) \
                    or _off(c, cid, new_start, new_start + slot) or new_start < _now():
                raise SlotTaken()
            ct = nonce = ver = None
            if old["client_ct"] is not None:            # sealing binds details to the row id: seal again for the new row
                if sealer is None:
                    raise NotAllowed()
                ct, nonce, ver = sealer.seal(new_id, sealer.open(str(appt_id), old["client_ct"], old["client_nonce"]))
            c.execute("update appointments set status='rescheduled', manage_hash=null, rescheduled_to=null, "
                      "updated_at=now() where id=%s", (str(appt_id),))
            new = c.execute(
                """insert into appointments (id, clinician_id, starts_at, ends_at, blocked_until, status, source,
                     client_ct, client_nonce, client_key_ver, email_hash, manage_hash, consent_at, rescheduled_from)
                   values (%s,%s,%s,%s,%s,'confirmed',%s,%s,%s,%s,%s,%s,%s,%s) returning *""",
                (new_id, str(cid), new_start, new_start + slot, new_start + slot + buf, old["source"], ct, nonce, ver,
                 old["email_hash"], old["manage_hash"], old["consent_at"], str(appt_id))).fetchone()
            c.execute("update appointments set rescheduled_to=%s where id=%s", (new_id, str(appt_id)))
            c.execute("update booking_notifications set status='failed' where appointment_id=%s and kind='reminder' "
                      "and status='pending'", (str(appt_id),))
            if ct is not None:
                _enqueue(c, new_id, "rescheduled", "client")
                _reminder(c, new)
            return {"old": old, "new": new}
    except psycopg.errors.ExclusionViolation:
        raise SlotTaken()


def summary(cid, tz_name: str) -> dict:
    tz = booking.zone(tz_name)
    today = _now().astimezone(tz).date()
    d0 = datetime.combine(today, datetime.min.time(), tzinfo=tz).astimezone(UTC)
    m0 = datetime.combine(today.replace(day=1), datetime.min.time(), tzinfo=tz).astimezone(UTC)
    with _conn() as c, c.transaction():
        _tidy(c, cid)
        r = c.execute(
            """select count(*) filter (where status in ('pending','confirmed','completed') and starts_at >= %(d0)s
                                         and starts_at < %(d1)s) today,
                      count(*) filter (where status in ('pending','confirmed') and starts_at >= now()) upcoming,
                      count(*) filter (where status='pending' and starts_at >= now()) pending,
                      count(*) filter (where starts_at >= %(m0)s and status not in ('rescheduled','expired')) this_month,
                      count(*) filter (where status='completed') completed,
                      count(*) filter (where status in ('cancelled','rejected','expired')) cancelled,
                      count(*) filter (where status <> 'rescheduled') total
               from appointments where clinician_id=%(cid)s""",
            {"cid": str(cid), "d0": d0, "d1": d0 + timedelta(days=1), "m0": m0}).fetchone()
    return dict(r)


# --- notifications -------------------------------------------------------------------------------
def due_notifications(limit: int = 50) -> list[dict]:
    with _conn() as c:
        return c.execute(
            """select n.id, n.kind, n.recipient, n.attempts, a.id as appointment_id, a.clinician_id, a.starts_at,
                      a.ends_at, a.status, a.client_ct, a.client_nonce, s.display_name, s.timezone, s.slug, u.email as clinician_email
               from booking_notifications n join appointments a on a.id = n.appointment_id
               join booking_settings s on s.clinician_id = a.clinician_id
               left join auth.users u on u.id = a.clinician_id
               where n.status='pending' and n.due_at <= now() order by n.due_at limit %s""", (limit,)).fetchall()


def mark_notification(nid: int, status: str) -> None:
    with _conn() as c:
        c.execute("update booking_notifications set status=%s, attempts=attempts+1, "
                  "sent_at=case when %s='sent' then now() else sent_at end where id=%s", (status, status, nid))


def purge_old() -> int:
    """Deletes appointments (and their client details) RETENTION_DAYS after they ended."""
    with _conn() as c:
        c.execute("update appointments set rescheduled_to=null where rescheduled_to in "
                  "(select id from appointments where ends_at < now() - make_interval(days => %s))", (RETENTION_DAYS,))
        c.execute("update appointments set rescheduled_from=null where rescheduled_from in "
                  "(select id from appointments where ends_at < now() - make_interval(days => %s))", (RETENTION_DAYS,))
        return c.execute("delete from appointments where ends_at < now() - make_interval(days => %s)",
                         (RETENTION_DAYS,)).rowcount
