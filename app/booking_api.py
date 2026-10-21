"""
Calendar and public booking endpoints.

Consultant (verified clinician; sees and changes only their own calendar):
  GET  /v1/calendar                               → settings, booking link, hours, time off, stats
  PUT  /v1/calendar/settings                      → link name, on/off, duration, buffer, notice, timezone, approval
  PUT  /v1/calendar/availability                  → weekly working hours (several periods a day = breaks)
  POST /v1/calendar/time-off · DELETE /v1/calendar/time-off/{id}
  GET  /v1/calendar/appointments?start=&end=      → appointments between two local dates (with client details)
  GET  /v1/calendar/slots?start=&days=            → free times (for adding or moving an appointment)
  POST /v1/calendar/appointments                  → add one (no overlap allowed)
  POST /v1/calendar/appointments/{id}/{confirm|reject|cancel|complete}
  POST /v1/calendar/appointments/{id}/reschedule
Public (no sign-in; only what booking needs):
  GET  /{slug} (and the older /book/{slug}) · GET /book/manage/{token}    → the booking page (static)
  GET  /v1/public/booking/{slug}                  → name, short bio, timezone, appointment length
  GET  /v1/public/booking/{slug}/slots            → free times
  POST /v1/public/booking/{slug}                  → book (first name, email, consent)
  GET  /v1/public/booking/manage/{token} · POST …/cancel → the client's own appointment
Cloud Scheduler:
  POST /v1/internal/booking/deliver               → send due emails + reminders, purge old rows (X-Cron-Token)
"""
from __future__ import annotations

import pathlib
import re
import threading
import time as _time
import uuid
from collections import defaultdict, deque
from datetime import date, datetime, timedelta, timezone

from fastapi import BackgroundTasks, Depends, FastAPI, Header, HTTPException, Query, Request
from fastapi.responses import FileResponse, Response
from pydantic import BaseModel, ConfigDict, Field

from . import booking, notify

UTC = timezone.utc
WEB = pathlib.Path(__file__).parent / "booking_web"
ROLE = {"psychologist": "Psychologist", "psychiatrist": "Psychiatrist", "counsellor_trainee": "Counsellor"}
TIMEZONES = ["Asia/Kolkata", "Asia/Dubai", "Asia/Singapore", "Europe/London", "Europe/Berlin",
             "America/New_York", "America/Chicago", "America/Los_Angeles", "Australia/Sydney", "UTC"]


class SettingsIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    slug: str = Field(max_length=40)
    display_name: str = Field(max_length=80)
    bio: str = Field(default="", max_length=500)
    enabled: bool = False
    timezone: str = Field(default="Asia/Kolkata", max_length=64)
    slot_minutes: int = 30
    buffer_minutes: int = 0
    min_notice_minutes: int = 240
    max_advance_days: int = 30
    address: str = Field(default="", max_length=400)
    phone: str = Field(default="", max_length=30)
    links: list[str] = Field(default_factory=list, max_length=10)
    approval: str = "manual"


class PhotoIn(BaseModel):
    image: str = Field(max_length=600_000)          # base64 of a JPEG, PNG or WebP, at most 400 KB


class WindowIn(BaseModel):
    weekday: int
    start: str = Field(max_length=5)
    end: str = Field(max_length=5)


class AvailabilityIn(BaseModel):
    windows: list[WindowIn] = Field(max_length=28)


class TimeOffIn(BaseModel):
    """Either exact times (starts_at/ends_at, UTC ISO) or whole local days (date_from/date_to inclusive)."""
    starts_at: str | None = None
    ends_at: str | None = None
    date_from: date | None = None
    date_to: date | None = None
    label: str = Field(default="", max_length=80)


class ConsultantBookingIn(BaseModel):
    """starts_at: a UTC instant; or starts_local: a wall time in the consultant's timezone (2026-10-13T18:00)."""
    starts_at: str | None = None
    starts_local: str | None = Field(default=None, max_length=16)
    first_name: str | None = Field(default=None, max_length=40)
    email: str | None = Field(default=None, max_length=254)
    tag: str | None = Field(default=None, max_length=20)        # first_session · follow_up · online


class TagIn(BaseModel):
    tag: str | None = Field(default=None, max_length=20)        # None: no tag


class RescheduleIn(BaseModel):
    starts_at: str | None = None
    starts_local: str | None = Field(default=None, max_length=16)
    outside_hours: bool = False        # the consultant may move it outside their published hours


class PublicBookingIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    starts_at: str
    first_name: str = Field(max_length=40)
    email: str = Field(max_length=254)
    consent: bool
    website: str = Field(default="", max_length=200)   # honeypot: people leave it empty
    tag: str | None = Field(default=None, max_length=20)   # first_session · follow_up · online


def _iso(d):
    return d.astimezone(UTC).isoformat().replace("+00:00", "Z") if isinstance(d, datetime) else d


def _local(d: datetime, tz_name: str) -> str:
    """Wall-clock time in the consultant's timezone, e.g. 2026-10-13T10:30 (the app has no tz database)."""
    return d.astimezone(booking.zone(tz_name)).strftime("%Y-%m-%dT%H:%M")


class _RateLimit:
    """Per-visitor limit on public writes (per server instance; Cloud Run may run several)."""

    def __init__(self, limit: int, seconds: int):
        self.limit, self.seconds, self.hits, self.lock = limit, seconds, defaultdict(deque), threading.Lock()

    def allow(self, key: str) -> bool:
        now = _time.monotonic()
        with self.lock:
            q = self.hits[key]
            while q and now - q[0] > self.seconds:
                q.popleft()
            if len(q) >= self.limit:
                return False
            q.append(now)
            if len(self.hits) > 10000:
                self.hits.clear()
            return True


class BookingService:
    def __init__(self, cfg, store, store_on, mailer=None):
        self.cfg, self.store, self.store_on = cfg, store, store_on
        self.sealer = booking.Sealer.from_secret(cfg.booking_encryption_key)
        self.mailer = mailer if mailer is not None else notify.Mailer.from_config(cfg)
        self.limit = _RateLimit(8, 600)

    def base_url(self, request: Request) -> str:
        if self.cfg.public_base_url:
            return self.cfg.public_base_url
        base = str(request.base_url).rstrip("/")
        host = request.url.hostname or ""
        if base.startswith("http://") and host not in ("localhost", "127.0.0.1", "testserver"):
            base = "https://" + base[len("http://"):]        # Cloud Run terminates TLS in front of us
        return base

    def details(self, row: dict) -> dict | None:
        if row.get("client_ct") is None or self.sealer is None:
            return None
        try:
            return self.sealer.open(str(row["id"]), row["client_ct"], row["client_nonce"])
        except Exception:      # noqa: BLE001 - a row sealed under another key: show no details, never crash
            return None

    def view(self, row: dict, tz_name: str) -> dict:
        d = self.details(row)
        return {"id": str(row["id"]), "starts_at": _iso(row["starts_at"]), "ends_at": _iso(row["ends_at"]),
                "local_start": _local(row["starts_at"], tz_name), "local_end": _local(row["ends_at"], tz_name),
                "status": row["status"], "source": row["source"], "tag": row.get("tag"),
                "tag_label": booking.tag_label(row.get("tag")),
                "client": {"first_name": d.get("first_name"), "email": d.get("email")} if d else None,
                "pending_until": _iso(row["pending_until"]), "cancelled_by": row["cancelled_by"],
                "rescheduled_from": str(row["rescheduled_from"]) if row["rescheduled_from"] else None,
                "rescheduled_to": str(row["rescheduled_to"]) if row["rescheduled_to"] else None,
                "created_at": _iso(row["created_at"])}

    def deliver(self, base_url: str, limit: int = 50) -> dict:
        """Sends due notices; without SMTP they are marked not_configured. Never raises."""
        counts = {"sent": 0, "failed": 0, "not_configured": 0}
        try:
            for n in self.store.due_notifications(limit):
                status = "not_configured"
                if self.mailer is not None:
                    try:
                        msg = notify.compose(n, self.details({"id": n["appointment_id"], "client_ct": n["client_ct"],
                                                              "client_nonce": n["client_nonce"]}), base_url)
                        if msg is None:
                            status = "failed"
                        else:
                            self.mailer.send(*msg)
                            status = "sent"
                    except Exception:     # noqa: BLE001 - one bad address must not stop the rest; no details logged
                        status = "failed" if n["attempts"] >= 2 else "pending"
                self.store.mark_notification(n["id"], status)
                counts[status if status in counts else "failed"] += 1
        except Exception:                 # noqa: BLE001 - email is best effort; booking already succeeded
            pass
        return counts


def _start(body, tz_name: str) -> datetime:
    """The requested start as UTC, from starts_at (UTC) or starts_local (consultant's wall time)."""
    if body.starts_local:
        try:
            wall = datetime.strptime(body.starts_local, "%Y-%m-%dT%H:%M")
        except ValueError:
            raise booking.BookingError("starts_local: a date and time like 2026-10-13T18:00")
        at = booking.local_instant(wall.date(), wall.time(), tz_name)
        if at is None:
            raise booking.BookingError("That time does not exist on that day (the clocks change).")
        return at
    return booking.parse_utc(body.starts_at or "")


def _slugify(name: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", (name or "").lower()).strip("-")
    s = re.sub(r"^(dr|mr|mrs|ms|prof)-", "", s)
    return (s or "consultant")[:40].strip("-")


def install_short_links(app: FastAPI) -> None:
    """https://<server>/<link name>: the booking page at the top level. Registered LAST (main.py), so every
    other route matches first; only a valid, unreserved link name gets the page."""
    headers = {"Cache-Control": "no-store", "Referrer-Policy": "no-referrer", "X-Content-Type-Options": "nosniff",
               "Content-Security-Policy": "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; "
                                          "font-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'; "
                                          "frame-ancestors 'none'"}

    @app.get("/{slug}", include_in_schema=False)
    def booking_short(slug: str):
        if not booking.SLUG_RE.match(slug) or slug in booking.RESERVED_SLUGS or "--" in slug:
            raise HTTPException(404, "not found")
        return FileResponse(WEB / "index.html", media_type="text/html", headers=headers)


def install(app: FastAPI, svc: BookingService, verified_clinician, features=None) -> None:
    """features(clinician id) → what their plan unlocks (main.py: billing). None: everything."""

    def unlocked(cid) -> frozenset | set:
        if features is None:
            return {"appointments", "booking"}
        try:
            return features(cid)
        except Exception:      # noqa: BLE001 - fail closed: no plan check, no calendar
            return set()

    def plan_required(feature: str):
        from .billing_api import plan_required as body
        return HTTPException(402, body(feature))

    def consultant(c: dict = Depends(verified_clinician)) -> dict:
        """Appointments in the app are part of Practice, BYOK Scale and Scale."""
        if "appointments" not in unlocked(c["id"]):
            raise plan_required("appointments")
        return c

    def need_store():
        if not svc.store_on():
            raise HTTPException(503, {"error": "calendar_unavailable", "message": "The calendar needs the database."})

    def tz_of(c) -> str:
        return (svc.store.get_settings(c["id"]) or booking.DEFAULT_SETTINGS)["timezone"]

    def settings_of(c) -> dict:
        s = svc.store.get_settings(c["id"])
        if not s:
            raise HTTPException(409, {"error": "calendar_not_set_up", "message": "Set up your booking settings first."})
        return s

    def problems(e: booking.BookingError, status: int = 422):
        return HTTPException(status, {"error": "invalid", "problems": e.problems, "message": e.problems[0]})

    def deliver_later(bg: BackgroundTasks, request: Request):
        bg.add_task(svc.deliver, svc.base_url(request))

    # --- consultant -------------------------------------------------------------------------------
    @app.get("/v1/calendar")
    def calendar_home(request: Request, c: dict = Depends(consultant)):
        need_store()
        s = svc.store.get_settings(c["id"])
        if s:
            settings = {k: s[k] for k in ("slug", "enabled", "display_name", "bio", "timezone", "slot_minutes",
                                          "buffer_minutes", "min_notice_minutes", "max_advance_days", "approval",
                                          "address", "phone", "links")}
            settings["photo_version"] = s["photo_version"] if s.get("photo") is not None else None
        else:
            name = c.get("full_name") or ""
            settings = {**booking.DEFAULT_SETTINGS, "slug": _slugify(name), "display_name": name}
        tz = settings["timezone"]
        return {"configured": bool(s), "settings": settings,
                "booking_url": f"{svc.base_url(request)}/{settings['slug']}" if s else None,
                "windows": [{"weekday": w, "start": f"{a:%H:%M}", "end": f"{b:%H:%M}"} for w, a, b in svc.store.windows(c["id"])],
                "time_off": [{"id": t["id"], "starts_at": _iso(t["starts_at"]), "ends_at": _iso(t["ends_at"]),
                              "local_start": _local(t["starts_at"], tz), "local_end": _local(t["ends_at"], tz),
                              "label": t["label"]} for t in svc.store.time_off(c["id"])],
                "summary": svc.store.summary(c["id"], tz) if s else None,
                "today": datetime.now(UTC).astimezone(booking.zone(tz)).date().isoformat(),
                "ready": {"booking": svc.sealer is not None, "email": svc.mailer is not None},
                "timezones": TIMEZONES}

    @app.put("/v1/calendar/settings")
    def calendar_settings(body: SettingsIn, request: Request, c: dict = Depends(consultant)):
        need_store()
        try:
            s = booking.validate_settings(body.model_dump())
        except booking.BookingError as e:
            raise problems(e)
        if s["enabled"] and "booking" not in unlocked(c["id"]):
            raise plan_required("booking")
        if s["enabled"] and svc.sealer is None:
            raise HTTPException(503, {"error": "booking_unavailable",
                                      "message": "Online booking is not switched on for this server yet."})
        if not svc.store.slug_free(s["slug"], c["id"]):
            raise HTTPException(409, {"error": "slug_taken", "message": "That link name is taken. Try another."})
        try:
            svc.store.save_settings(c["id"], s)
        except svc.store.SlugTaken:
            raise HTTPException(409, {"error": "slug_taken", "message": "That link name is taken. Try another."})
        return {"settings": s, "booking_url": f"{svc.base_url(request)}/{s['slug']}"}

    @app.put("/v1/calendar/photo")
    def calendar_photo(body: PhotoIn, c: dict = Depends(consultant)):
        """The photo on the booking page. Checked by its own bytes; never shown before it is saved."""
        need_store()
        import base64
        import binascii
        try:
            data = base64.b64decode(body.image, validate=True)
        except (binascii.Error, ValueError):
            raise HTTPException(422, {"error": "invalid", "message": "That photo could not be read."})
        mime = booking.photo_type(data)
        if mime is None:
            raise HTTPException(422, {"error": "invalid", "message": "Choose a JPEG, PNG or WebP photo."})
        if len(data) > booking.PHOTO_MAX_BYTES:
            raise HTTPException(422, {"error": "invalid", "message": "That photo is too large (at most 400 KB)."})
        version = svc.store.set_photo(c["id"], data, mime)
        if version is None:
            raise HTTPException(409, {"error": "calendar_not_set_up", "message": "Save your booking settings first."})
        return {"photo_version": version}

    @app.delete("/v1/calendar/photo")
    def calendar_photo_remove(c: dict = Depends(consultant)):
        need_store()
        svc.store.set_photo(c["id"], None, None)
        return {"photo_version": None}

    @app.get("/v1/calendar/photo")
    def calendar_photo_get(c: dict = Depends(consultant)):
        need_store()
        p = svc.store.photo(c["id"])
        if not p:
            raise HTTPException(404, "no photo")
        return Response(p[0], media_type=p[1], headers={"Cache-Control": "private, no-store",
                                                         "X-Content-Type-Options": "nosniff"})

    @app.put("/v1/calendar/availability")
    def calendar_availability(body: AvailabilityIn, c: dict = Depends(consultant)):
        need_store()
        try:
            ws = booking.validate_windows([w.model_dump() for w in body.windows])
        except booking.BookingError as e:
            raise problems(e)
        svc.store.save_windows(c["id"], ws)
        return {"windows": [{"weekday": w, "start": f"{a:%H:%M}", "end": f"{b:%H:%M}"} for w, a, b in ws]}

    @app.post("/v1/calendar/time-off")
    def calendar_time_off(body: TimeOffIn, c: dict = Depends(consultant)):
        need_store()
        tz_name = (svc.store.get_settings(c["id"]) or booking.DEFAULT_SETTINGS)["timezone"]
        try:
            if body.date_from:
                tz = booking.zone(tz_name)
                last = body.date_to or body.date_from
                if last < body.date_from or (last - body.date_from).days > 365:
                    raise booking.BookingError("dates: the last day must be on or after the first (at most a year)")
                start = datetime.combine(body.date_from, datetime.min.time(), tzinfo=tz).astimezone(UTC)
                end = datetime.combine(last + timedelta(days=1), datetime.min.time(), tzinfo=tz).astimezone(UTC)
            else:
                start, end = booking.parse_utc(body.starts_at or ""), booking.parse_utc(body.ends_at or "")
                if end <= start or end - start > timedelta(days=366):
                    raise booking.BookingError("the end must be after the start (at most a year)")
        except booking.BookingError as e:
            raise problems(e)
        t = svc.store.add_time_off(c["id"], start, end, body.label.strip())
        clash = [a for a in svc.store.list_between(c["id"], start, end) if a["status"] in booking.ACTIVE]
        return {"time_off": {"id": t["id"], "starts_at": _iso(t["starts_at"]), "ends_at": _iso(t["ends_at"]),
                             "label": t["label"]},
                "conflicts": len(clash)}     # existing appointments stay; the consultant decides about them

    @app.delete("/v1/calendar/time-off/{off_id}")
    def calendar_time_off_delete(off_id: int, c: dict = Depends(consultant)):
        need_store()
        if not svc.store.delete_time_off(c["id"], off_id):
            raise HTTPException(404, "not found")
        return {"deleted": True}

    @app.get("/v1/calendar/appointments")
    def calendar_appointments(start: date, end: date, c: dict = Depends(consultant)):
        need_store()
        if end < start or (end - start).days > 62:
            raise HTTPException(422, {"error": "invalid", "message": "Choose up to 62 days."})
        tz_name = tz_of(c)
        tz = booking.zone(tz_name)
        lo = datetime.combine(start, datetime.min.time(), tzinfo=tz).astimezone(UTC)
        hi = datetime.combine(end + timedelta(days=1), datetime.min.time(), tzinfo=tz).astimezone(UTC)
        return {"timezone": tz_name, "appointments": [svc.view(r, tz_name) for r in svc.store.list_between(c["id"], lo, hi)]}

    @app.get("/v1/calendar/slots")
    def calendar_slots(start: date, days: int = Query(7, ge=1, le=31), ignore: uuid.UUID | None = None,
                       c: dict = Depends(consultant)):
        need_store()
        s = settings_of(c)
        slots = svc.store.free_slots(c["id"], s, start, days, honour_notice=False, ignore=str(ignore) if ignore else None)
        return {"timezone": s["timezone"], "days": [
            {"date": d.isoformat(), "slots": [{"starts_at": _iso(t), "local": _local(t, s["timezone"])} for t in ts]}
            for d, ts in sorted(slots.items())]}

    @app.post("/v1/calendar/appointments")
    def calendar_add(body: ConsultantBookingIn, request: Request, bg: BackgroundTasks,
                     c: dict = Depends(consultant)):
        need_store()
        s = settings_of(c)
        try:
            start = _start(body, s["timezone"])
            details = None
            if body.first_name or body.email:
                if svc.sealer is None:
                    raise HTTPException(503, {"error": "booking_unavailable",
                                              "message": "Client details can't be stored on this server yet."})
                first, mail = booking.validate_client(body.first_name or "", body.email or "")
                details = {"first_name": first, "email": mail}
            tag = booking.validate_tag(body.tag)
        except booking.BookingError as e:
            raise problems(e)
        aid = str(uuid.uuid4())
        if details:
            details["manage_token"] = booking.new_manage_token()[0]     # the client's own cancel link
        try:
            row = svc.store.book(c["id"], s, start, source="consultant", sealer=svc.sealer, details=details,
                                 email_hash=None, manage_hash=booking.token_hash(details["manage_token"]) if details else None,
                                 status="confirmed", appointment_id=aid, check_hours=False, tag=tag)
        except svc.store.SlotTaken:
            raise HTTPException(409, {"error": "slot_taken", "message": "That time overlaps another appointment or time off."})
        deliver_later(bg, request)
        return {"appointment": svc.view(row, s["timezone"])}

    @app.put("/v1/calendar/appointments/{appt_id}/tag")
    def calendar_tag(appt_id: uuid.UUID, body: TagIn, c: dict = Depends(consultant)):
        need_store()
        try:
            tag = booking.validate_tag(body.tag)
        except booking.BookingError as e:
            raise problems(e)
        try:
            row = svc.store.set_tag(appt_id, c["id"], tag)
        except LookupError:
            raise HTTPException(404, "not found")
        return {"appointment": svc.view(row, tz_of(c))}

    @app.post("/v1/calendar/appointments/{appt_id}/reschedule")
    def calendar_reschedule(appt_id: uuid.UUID, body: RescheduleIn, request: Request, bg: BackgroundTasks,
                            c: dict = Depends(consultant)):
        need_store()
        s = settings_of(c)
        try:
            start = _start(body, s["timezone"])
        except booking.BookingError as e:
            raise problems(e)
        try:
            r = svc.store.reschedule(appt_id, c["id"], s, start, str(uuid.uuid4()), svc.sealer,
                                     check_hours=not body.outside_hours)
        except LookupError:
            raise HTTPException(404, "not found")
        except svc.store.NotAllowed:
            raise HTTPException(409, {"error": "not_allowed", "message": "Only pending or confirmed appointments can be moved."})
        except svc.store.SlotTaken:
            raise HTTPException(409, {"error": "slot_taken", "message": "That time is not free."})
        deliver_later(bg, request)
        return {"appointment": svc.view(r["new"], s["timezone"]), "previous_id": str(appt_id)}

    @app.post("/v1/calendar/appointments/{appt_id}/{action}")
    def calendar_action(appt_id: uuid.UUID, action: str, request: Request, bg: BackgroundTasks,
                        c: dict = Depends(consultant)):
        need_store()
        if action not in ("confirm", "reject", "cancel", "complete"):
            raise HTTPException(404, "not found")
        try:
            row = svc.store.transition(appt_id, c["id"], action)
        except LookupError:
            raise HTTPException(404, "not found")
        except svc.store.NotAllowed:
            raise HTTPException(409, {"error": "not_allowed", "message": "This appointment can't be changed that way now."})
        deliver_later(bg, request)
        return {"appointment": svc.view(row, tz_of(c))}

    # --- public -----------------------------------------------------------------------------------
    def public_settings(slug: str) -> dict:
        need_store()
        s = svc.store.public_settings(slug.lower()) if booking.SLUG_RE.match(slug.lower()) else None
        if not s or svc.sealer is None or "booking" not in unlocked(s["clinician_id"]):
            # A plan without the booking page reads as no page: clients see nothing about plans.
            raise HTTPException(404, {"error": "not_found", "message": "This booking page does not exist."})
        return s

    @app.get("/v1/public/booking/manage/{token}")
    def public_manage(token: str):
        need_store()
        row = svc.store.by_manage_hash(booking.token_hash(token)) if 20 <= len(token) <= 64 else None
        if not row:
            raise HTTPException(404, {"error": "not_found", "message": "This link is no longer valid."})
        s = svc.store.get_settings(row["clinician_id"])
        return {"status": row["status"], "starts_at": _iso(row["starts_at"]), "ends_at": _iso(row["ends_at"]),
                "tag_label": booking.tag_label(row.get("tag")),
                "timezone": s["timezone"], "display_name": s["display_name"], "slug": s["slug"] if s["enabled"] else None,
                "can_cancel": row["status"] in booking.ACTIVE and row["starts_at"] > datetime.now(UTC)}

    @app.post("/v1/public/booking/manage/{token}/cancel")
    def public_cancel(token: str, request: Request, bg: BackgroundTasks):
        need_store()
        row = svc.store.by_manage_hash(booking.token_hash(token)) if 20 <= len(token) <= 64 else None
        if not row:
            raise HTTPException(404, {"error": "not_found", "message": "This link is no longer valid."})
        if row["starts_at"] <= datetime.now(UTC):
            raise HTTPException(409, {"error": "not_allowed", "message": "This appointment has already started."})
        try:
            svc.store.transition(row["id"], row["clinician_id"], "cancel", by="client")
        except svc.store.NotAllowed:
            raise HTTPException(409, {"error": "not_allowed", "message": "This appointment can no longer be cancelled."})
        deliver_later(bg, request)
        return {"status": "cancelled"}

    @app.get("/v1/public/booking/{slug}")
    def public_profile(slug: str):
        s = public_settings(slug)
        return {"display_name": s["display_name"], "bio": s["bio"], "role": ROLE.get(s["role"], "Consultant"),
                "address": s.get("address") or "", "phone": s.get("phone") or "", "links": s.get("links") or [],
                "photo": f"/v1/public/booking/{s['slug']}/photo?v={s['photo_version']}" if s.get("photo") is not None
                else None,
                "timezone": s["timezone"], "slot_minutes": s["slot_minutes"], "max_advance_days": s["max_advance_days"],
                "approval": s["approval"], "tags": [{"id": k, "label": v} for k, v in booking.TAGS.items()]}

    @app.get("/v1/public/booking/{slug}/photo")
    def public_photo(slug: str):
        s = public_settings(slug)
        p = svc.store.photo(s["clinician_id"])
        if not p:
            raise HTTPException(404, "no photo")
        return Response(p[0], media_type=p[1], headers={"Cache-Control": "public, max-age=86400",
                                                         "X-Content-Type-Options": "nosniff",
                                                         "Content-Security-Policy": "default-src 'none'"})

    @app.get("/v1/public/booking/{slug}/slots")
    def public_slots(slug: str, start: date, days: int = Query(7, ge=1, le=14)):
        s = public_settings(slug)
        slots = svc.store.free_slots(s["clinician_id"], s, start, days)
        return {"timezone": s["timezone"], "days": [{"date": d.isoformat(), "slots": [_iso(t) for t in ts]}
                                                    for d, ts in sorted(slots.items())]}

    @app.post("/v1/public/booking/{slug}")
    def public_book(slug: str, body: PublicBookingIn, request: Request, bg: BackgroundTasks):
        s = public_settings(slug)
        ip = (request.headers.get("x-forwarded-for") or (request.client.host if request.client else "")).split(",")[0].strip()
        if not svc.limit.allow(ip):
            raise HTTPException(429, {"error": "too_many", "message": "Too many attempts. Please try again in a few minutes."})
        if body.website:
            raise HTTPException(422, {"error": "invalid", "message": "Please try again."})
        if not body.consent:
            raise HTTPException(422, {"error": "consent_required",
                                      "message": "Please agree to share your first name and email with this consultant."})
        try:
            start = booking.parse_utc(body.starts_at)
            first, mail = booking.validate_client(body.first_name, body.email)
            tag = booking.validate_tag(body.tag)
        except booking.BookingError as e:
            raise problems(e)
        token, manage_hash = booking.new_manage_token()
        aid = str(uuid.uuid4())
        try:
            row = svc.store.book(s["clinician_id"], s, start, source="public", sealer=svc.sealer,
                                 details={"first_name": first, "email": mail, "manage_token": token},
                                 email_hash=svc.sealer.email_hash(mail), manage_hash=manage_hash,
                                 status="confirmed" if s["approval"] == "auto" else "pending", appointment_id=aid,
                                 tag=tag)
        except svc.store.SlotTaken:
            raise HTTPException(409, {"error": "slot_taken",
                                      "message": "Sorry, that time was just taken or is no longer available. Please pick another."})
        except svc.store.TooMany:
            raise HTTPException(409, {"error": "too_many_bookings",
                                      "message": "You already have upcoming appointments with this consultant."})
        deliver_later(bg, request)
        return {"status": row["status"], "starts_at": _iso(row["starts_at"]), "ends_at": _iso(row["ends_at"]),
                "timezone": s["timezone"], "display_name": s["display_name"], "manage_token": token,
                "tag_label": booking.tag_label(row.get("tag")),
                "email_sent": svc.mailer is not None}

    # --- pages ------------------------------------------------------------------------------------
    headers = {"Cache-Control": "no-store", "Referrer-Policy": "no-referrer", "X-Content-Type-Options": "nosniff",
               "Content-Security-Policy": "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; "
                                          "font-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'; "
                                          "frame-ancestors 'none'"}
    assets = {"booking.js": "text/javascript", "booking.css": "text/css"}

    @app.get("/book/assets/{name}")
    def booking_asset(name: str):
        if name not in assets:
            raise HTTPException(404, "not found")
        return FileResponse(WEB / name, media_type=assets[name], headers={**headers, "Cache-Control": "public, max-age=300"})

    @app.get("/book/manage/{token}")
    @app.get("/book/{slug}")             # links shared before the short /<link name> address keep working
    def booking_page(slug: str = "", token: str = ""):
        return FileResponse(WEB / "index.html", media_type="text/html", headers=headers)

    # --- scheduled delivery -----------------------------------------------------------------------
    @app.post("/v1/internal/booking/deliver")
    def booking_deliver(request: Request, x_cron_token: str = Header("")):
        import hmac
        if not svc.cfg.cron_token or not hmac.compare_digest(x_cron_token, svc.cfg.cron_token):
            raise HTTPException(404, "not found")
        need_store()
        out = svc.deliver(svc.base_url(request), limit=200)
        out["purged"] = svc.store.purge_old()
        return out
