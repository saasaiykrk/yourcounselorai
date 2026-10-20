"""
Consultant calendar and public booking: the rules, with no web or database code.

  * Times are stored in UTC. Working hours are wall-clock times in the consultant's own IANA
    timezone; each day's slots are built in that zone (zoneinfo), so a daylight-saving change moves
    the slots with the clock. A wall time that does not exist that day (clocks jump forward) is
    skipped; one that happens twice (clocks go back) uses its first occurrence.
  * A slot is free when it lies inside a working window, outside time off, after the minimum notice,
    within the maximum advance period, and its time plus the buffer after it overlaps no pending or
    confirmed appointment (each of which also holds its own buffer).
  * Pending requests hold their slot until the consultant answers or the request expires.
  * Client details are the minimum (first name, email) and are sealed (AES-256-GCM) before storage.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import re
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

UTC = timezone.utc
SLOT_CHOICES = (15, 30, 45, 60)
ACTIVE = ("pending", "confirmed")
PENDING_HOURS = 24                      # an unanswered request frees its slot after this
MAX_WINDOWS_PER_DAY = 4
MAX_ACTIVE_PER_EMAIL = 2                # future pending/confirmed bookings one email may hold per consultant
SLUG_RE = re.compile(r"^[a-z0-9](?:[a-z0-9-]{1,38}[a-z0-9])$")
RESERVED_SLUGS = {"admin", "api", "book", "manage", "assets", "health", "healthz", "v1", "dev", "static", "help"}
EMAIL_RE = re.compile(r"^[^@\s]{1,64}@[^@\s]{1,190}\.[A-Za-z]{2,24}$")
NAME_RE = re.compile(r"^[^\d<>@{}\[\]\\/|=+*#$%^&_~`\"]{1,40}$")
# What kind of session an appointment is: one tag, or none. The client picks it on the booking page;
# the consultant can set or change it in the app.
TAGS = {"first_session": "First Session", "follow_up": "Follow-up", "online": "Online"}
WEEKDAYS = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")

DEFAULT_SETTINGS = {"enabled": False, "bio": "", "timezone": "Asia/Kolkata", "slot_minutes": 30,
                    "buffer_minutes": 0, "min_notice_minutes": 240, "max_advance_days": 30, "approval": "manual"}


class BookingError(ValueError):
    """A request the rules refuse; .problems lists every reason (safe to show)."""
    def __init__(self, problems: list[str] | str):
        problems = [problems] if isinstance(problems, str) else problems
        super().__init__("; ".join(problems))
        self.problems = problems


def zone(name: str) -> ZoneInfo:
    try:
        return ZoneInfo(name)
    except (ZoneInfoNotFoundError, ValueError):
        raise BookingError(f"timezone: unknown timezone '{name}'")


def validate_settings(s: dict) -> dict:
    """The consultant's booking settings, normalised, or BookingError listing every problem."""
    out, problems = dict(DEFAULT_SETTINGS), []
    unknown = set(s) - set(DEFAULT_SETTINGS) - {"slug", "display_name"}
    if unknown:
        problems.append("unknown settings: " + ", ".join(sorted(unknown)))
    out.update({k: v for k, v in s.items() if k in out or k in ("slug", "display_name")})
    slug = str(out.get("slug") or "").strip().lower()
    if not SLUG_RE.match(slug) or slug in RESERVED_SLUGS or "--" in slug:
        problems.append("slug: 3–40 lowercase letters, numbers or single hyphens (not a reserved word)")
    out["slug"] = slug
    name = str(out.get("display_name") or "").strip()
    if not 2 <= len(name) <= 80:
        problems.append("display_name: 2–80 characters")
    out["display_name"] = name
    out["bio"] = str(out.get("bio") or "").strip()
    if len(out["bio"]) > 500:
        problems.append("bio: at most 500 characters")
    if not isinstance(out["enabled"], bool):
        problems.append("enabled: true or false")
    try:
        zone(str(out["timezone"]))
    except BookingError as e:
        problems += e.problems
    def num(key, lo, hi, choices=None):
        v = out.get(key)
        if not isinstance(v, int) or isinstance(v, bool) or not lo <= v <= hi or (choices and v not in choices):
            problems.append(f"{key}: " + (f"one of {', '.join(map(str, choices))}" if choices else f"{lo}–{hi}"))
    num("slot_minutes", 15, 60, SLOT_CHOICES)
    num("buffer_minutes", 0, 120)
    num("min_notice_minutes", 0, 20160)
    num("max_advance_days", 1, 365)
    if out.get("approval") not in ("auto", "manual"):
        problems.append("approval: auto or manual")
    if problems:
        raise BookingError(problems)
    return out


def _hhmm(v) -> time:
    if isinstance(v, time):
        return v
    m = re.match(r"^([01]\d|2[0-3]):([0-5]\d)$", str(v or ""))
    if not m:
        raise BookingError(f"'{v}' is not a time like 09:30")
    return time(int(m.group(1)), int(m.group(2)))


def validate_windows(windows: list[dict]) -> list[tuple[int, time, time]]:
    """Weekly working windows → sorted (weekday, start, end); no overlaps, at most 4 a day."""
    out, problems = [], []
    for i, w in enumerate(windows or []):
        try:
            wd = w.get("weekday")
            if not isinstance(wd, int) or isinstance(wd, bool) or not 0 <= wd <= 6:
                raise BookingError("weekday must be 0 (Monday) to 6 (Sunday)")
            start, end = _hhmm(w.get("start")), _hhmm(w.get("end"))
            if end <= start:
                raise BookingError("the end must be after the start")
            out.append((wd, start, end))
        except BookingError as e:
            problems.append(f"window {i + 1}: {e.problems[0]}")
    out.sort()
    for a, b in zip(out, out[1:]):
        if a[0] == b[0] and b[1] < a[2]:
            problems.append(f"{WEEKDAYS[a[0]]}: {a[1]:%H:%M}–{a[2]:%H:%M} overlaps {b[1]:%H:%M}–{b[2]:%H:%M}")
    for wd in range(7):
        if sum(1 for w in out if w[0] == wd) > MAX_WINDOWS_PER_DAY:
            problems.append(f"{WEEKDAYS[wd]}: at most {MAX_WINDOWS_PER_DAY} working periods")
    if problems:
        raise BookingError(problems)
    return out


def _local(d: date, t: time, tz: ZoneInfo) -> datetime | None:
    """d at wall time t in tz, as UTC; None if that wall time does not exist (spring-forward gap)."""
    dt = datetime.combine(d, t, tzinfo=tz)              # fold=0: the first of two repeated times
    back = dt.astimezone(UTC).astimezone(tz)
    if back.replace(tzinfo=None) != dt.replace(tzinfo=None):
        return None
    return dt.astimezone(UTC)


def local_instant(d: date, t: time, tz_name: str) -> datetime | None:
    """Wall time t on day d in tz_name, as UTC; None if it does not exist that day."""
    return _local(d, t, zone(tz_name))


def _overlaps(a0: datetime, a1: datetime, ranges) -> bool:
    return any(a0 < r1 and r0 < a1 for r0, r1 in ranges)


@dataclass(frozen=True)
class Rules:
    timezone: str
    slot_minutes: int
    buffer_minutes: int
    min_notice_minutes: int
    max_advance_days: int

    @classmethod
    def of(cls, s: dict) -> "Rules":
        return cls(s["timezone"], s["slot_minutes"], s["buffer_minutes"], s["min_notice_minutes"], s["max_advance_days"])


def free_slots(rules: Rules, windows, time_off, busy, now: datetime, first_day: date, days: int,
               honour_notice: bool = True) -> dict[date, list[datetime]]:
    """Free slot start times (UTC) per local date. windows: (weekday, start, end) wall times;
    time_off and busy: (start, end) UTC ranges (busy ends already include each booking's buffer)."""
    tz = zone(rules.timezone)
    slot, buf = timedelta(minutes=rules.slot_minutes), timedelta(minutes=rules.buffer_minutes)
    earliest = now + timedelta(minutes=rules.min_notice_minutes) if honour_notice else now
    latest = now + timedelta(days=rules.max_advance_days)
    out: dict[date, list[datetime]] = {}
    for i in range(days):
        d = first_day + timedelta(days=i)
        found: list[datetime] = []
        for wd, w0, w1 in windows:
            if wd != d.weekday():
                continue
            wall, wall_end = datetime.combine(d, w0), datetime.combine(d, w1)
            while wall + slot <= wall_end:
                start = _local(d, wall.time(), tz)
                wall += slot
                if start is None:
                    continue                                   # this wall time does not exist today
                end = start + slot
                if start < earliest or start > latest:
                    continue
                if _overlaps(start, end, time_off) or _overlaps(start, end + buf, busy):
                    continue
                found.append(start)
        if found:
            out[d] = sorted(set(found))
    return out


def local_date(dt: datetime, tz_name: str) -> date:
    return dt.astimezone(zone(tz_name)).date()


def parse_utc(value: str) -> datetime:
    """An ISO-8601 instant with an offset (e.g. 2026-10-13T04:30:00Z) → aware UTC datetime."""
    try:
        dt = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        raise BookingError("starts_at: not a date and time")
    if dt.tzinfo is None:
        raise BookingError("starts_at: include the timezone offset (e.g. Z)")
    return dt.astimezone(UTC).replace(microsecond=0)


def validate_tag(tag: str | None) -> str | None:
    """One of TAGS, or None for no tag ("" counts as none)."""
    if tag in (None, ""):
        return None
    if tag not in TAGS:
        raise BookingError("tag: First Session, Follow-up or Online")
    return tag


def tag_label(tag: str | None) -> str | None:
    return TAGS.get(tag) if tag else None


def validate_client(first_name: str, email: str) -> tuple[str, str]:
    name = re.sub(r"\s+", " ", str(first_name or "")).strip()
    mail = str(email or "").strip().lower()
    problems = []
    if not NAME_RE.match(name):
        problems.append("first_name: 1–40 letters (no numbers or symbols)")
    if not EMAIL_RE.match(mail) or len(mail) > 254:
        problems.append("email: a valid email address")
    if problems:
        raise BookingError(problems)
    return name, mail


# --- sealing client details (AES-256-GCM, appointment id as associated data) -----------------
class Sealer:
    """BOOKING_ENCRYPTION_KEY (32 bytes, base64). The appointment id is bound in as associated data,
    so sealed details cannot be moved to another appointment."""

    def __init__(self, key_b64: str, version: int = 1):
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
        raw = base64.b64decode(key_b64)
        if len(raw) != 32:
            raise ValueError("BOOKING_ENCRYPTION_KEY must be 32 bytes, base64-encoded")
        self._aes, self.version = AESGCM(raw), version
        self._mac_key = hashlib.sha256(b"booking-email-hash:" + raw).digest()

    @classmethod
    def from_secret(cls, key_b64: str) -> "Sealer | None":
        return cls(key_b64) if key_b64 else None

    def seal(self, appointment_id: str, details: dict) -> tuple[bytes, bytes, int]:
        nonce = os.urandom(12)
        ct = self._aes.encrypt(nonce, json.dumps(details).encode(), str(appointment_id).encode())
        return ct, nonce, self.version

    def open(self, appointment_id: str, ct: bytes, nonce: bytes) -> dict:
        return json.loads(self._aes.decrypt(bytes(nonce), bytes(ct), str(appointment_id).encode()))

    def email_hash(self, email: str) -> str:
        return hmac.new(self._mac_key, email.encode(), hashlib.sha256).hexdigest()


def new_manage_token() -> tuple[str, str]:
    """(token for the client's link, its sha256 to store)."""
    token = base64.urlsafe_b64encode(os.urandom(24)).decode().rstrip("=")
    return token, hashlib.sha256(token.encode()).hexdigest()


def token_hash(token: str) -> str:
    return hashlib.sha256(str(token).encode()).hexdigest()
