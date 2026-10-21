"""Calendar and public booking over HTTP, against a real Postgres (migration 007). The app runs in
DEV_MODE; only the booking store is the real database. Skipped without TEST_DATABASE_URL.

What must hold:
- one time can never be booked twice, even by simultaneous requests;
- a pending request holds its time until it is answered or expires;
- moving an appointment leaves exactly one active appointment, and the client's link follows it;
- time off, working hours, notice and buffers are respected for the public;
- a consultant sees and changes only their own calendar;
- public responses carry no client details; stored client details are encrypted;
- invalid, automated or excessive requests are refused."""
import base64
import importlib.util
import os
import threading
import unittest
import uuid
from datetime import date, datetime, time, timedelta, timezone
from types import SimpleNamespace

URL = os.environ.get("TEST_DATABASE_URL", "")
HAVE = bool(URL) and all(importlib.util.find_spec(m) for m in ("fastapi", "httpx", "psycopg", "cryptography",
                                                                "anthropic"))

if HAVE:
    os.environ["DEV_MODE"] = "1"
    import psycopg
    from fastapi.testclient import TestClient

    from app import booking, booking_api, booking_db, db, main
    db._DSN = URL

UTC = timezone.utc
IST = "Asia/Kolkata"


def next_monday(min_days=7) -> date:
    d = datetime.now(UTC).date() + timedelta(days=min_days)
    return d + timedelta(days=(7 - d.weekday()) % 7)


DAY = next_monday()


def at(h, m=0, d=None) -> str:
    """Wall time h:m in India on day d (default DAY), as the UTC string the API uses."""
    d = d or DAY
    local = datetime.combine(d, time(h, m), tzinfo=booking.zone(IST))
    return local.astimezone(UTC).isoformat().replace("+00:00", "Z")


class FakeMailer:
    def __init__(self):
        self.sent = []

    def send(self, to, subject, body):
        self.sent.append((to, subject, body))


@unittest.skipUnless(HAVE, "TEST_DATABASE_URL not set")
class BookingApiTests(unittest.TestCase):
    def setUp(self):
        self.cid, self.other = str(uuid.uuid4()), str(uuid.uuid4())
        self.slug = "dr-" + self.cid[:8]
        with psycopg.connect(URL, autocommit=True) as c:
            for who, name in ((self.cid, "Dr. Asha Rao"), (self.other, "Rohan Mehta")):
                c.execute("insert into auth.users (id, email) values (%s,%s)", (who, f"{who[:8]}@consultant.test"))
                c.execute("""insert into clinicians (id, full_name, role, registration_body, level, verification_status,
                               consent_version) values (%s,%s,'psychologist','RCI','L2','verified','v1')""", (who, name))
        self.who = self.cid
        main.app.dependency_overrides[main.verified_clinician] = lambda: {**db.get_clinician(self.who), "id": self.who}
        svc = main.BOOKING
        self.saved = (svc.cfg, svc.store, svc.store_on, svc.sealer, svc.mailer, svc.limit)
        svc.cfg = SimpleNamespace(public_base_url="https://yc.test", cron_token="cron-secret-123")
        svc.store, svc.store_on = booking_db, (lambda: True)
        svc.sealer = booking.Sealer(base64.b64encode(os.urandom(32)).decode())
        svc.mailer = None
        svc.limit = booking_api._RateLimit(1000, 600)
        self.client = TestClient(main.app)

    def tearDown(self):
        main.app.dependency_overrides.clear()
        svc = main.BOOKING
        svc.cfg, svc.store, svc.store_on, svc.sealer, svc.mailer, svc.limit = self.saved

    # --- helpers --------------------------------------------------------------------------------
    def as_(self, who):
        self.who = who
        return self

    def setup_calendar(self, **over):
        s = {"slug": self.slug, "display_name": "Dr Asha Rao", "bio": "Anxiety and mood.", "enabled": True,
             "timezone": IST, "slot_minutes": 30, "buffer_minutes": 0, "min_notice_minutes": 240,
             "max_advance_days": 30, "approval": "manual", **over}
        r = self.client.put("/v1/calendar/settings", json=s)
        self.assertEqual(r.status_code, 200, r.text)
        wd = DAY.weekday()
        r = self.client.put("/v1/calendar/availability", json={"windows": [
            {"weekday": wd, "start": "09:00", "end": "11:00"}, {"weekday": wd, "start": "12:00", "end": "13:00"},
            {"weekday": (wd + 1) % 7, "start": "09:00", "end": "11:00"}]})
        self.assertEqual(r.status_code, 200, r.text)
        return r

    def slots(self, slug=None, d=None):
        r = self.client.get(f"/v1/public/booking/{slug or self.slug}/slots", params={"start": (d or DAY).isoformat(), "days": 1})
        self.assertEqual(r.status_code, 200, r.text)
        days = r.json()["days"]
        return days[0]["slots"] if days else []

    def book(self, starts_at, email="client@example.com", name="Meera", **extra):
        body = {"starts_at": starts_at, "first_name": name, "email": email, "consent": True, **extra}
        return self.client.post(f"/v1/public/booking/{self.slug}", json=body)

    def appts(self, who=None):
        if who:
            self.as_(who)
        r = self.client.get("/v1/calendar/appointments", params={"start": DAY.isoformat(),
                                                                  "end": (DAY + timedelta(days=2)).isoformat()})
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()["appointments"]

    def rows(self):
        with psycopg.connect(URL, autocommit=True, row_factory=psycopg.rows.dict_row) as c:
            return c.execute("select * from appointments where clinician_id=%s order by created_at", (self.cid,)).fetchall()

    # --- set-up and the public page -----------------------------------------------------------------
    def test_set_up_then_the_public_page_shows_only_what_booking_needs(self):
        r = self.client.get("/v1/calendar").json()
        self.assertFalse(r["configured"])
        self.assertEqual(r["settings"]["slug"], "asha-rao", "a suggested link name from the consultant's name")
        self.setup_calendar()
        home = self.client.get("/v1/calendar").json()
        self.assertTrue(home["configured"])
        self.assertEqual(home["booking_url"], f"https://yc.test/{self.slug}", "the short link, without /book/")
        slots = self.client.get("/v1/calendar/slots", params={"start": DAY.isoformat(), "days": 1}).json()["days"][0]["slots"]
        self.assertEqual(slots[0], {"starts_at": at(9), "local": f"{DAY}T09:00"})
        self.assertEqual(len(home["windows"]), 3)
        prof = self.client.get(f"/v1/public/booking/{self.slug}")
        self.assertEqual(prof.status_code, 200)
        self.assertEqual(set(prof.json()), {"display_name", "bio", "role", "timezone", "slot_minutes",
                                            "max_advance_days", "approval", "tags"})
        self.assertEqual(self.slots(), [at(9), at(9, 30), at(10), at(10, 30), at(12), at(12, 30)],
                         "working periods with a break between them")
        page = self.client.get(f"/book/{self.slug}")
        self.assertEqual(page.status_code, 200)
        self.assertIn("frame-ancestors 'none'", page.headers["content-security-policy"])
        short = self.client.get(f"/{self.slug}")
        self.assertEqual(short.status_code, 200, "the booking page at the top level")
        self.assertEqual(short.text, page.text)
        self.assertIn("frame-ancestors 'none'", short.headers["content-security-policy"])

    def test_top_level_links_never_hide_the_servers_own_pages(self):
        self.assertEqual(self.client.get("/health").headers["content-type"], "application/json")
        self.assertIn("text/html", self.client.get("/delete-account").headers["content-type"])
        self.assertEqual(self.client.get("/admin").status_code, 200)
        for bad in ("/favicon.ico", "/x", "/Has-Caps", "/a--b", "/learn", "/docs-x/y"):
            r = self.client.get(bad)
            self.assertNotEqual((r.status_code, r.headers.get("content-security-policy", "")[:11]), (200, "default-src"),
                                bad)
        for name in ("learn", "delete-account", "docs", "privacy"):
            r = self.client.put("/v1/calendar/settings", json={"slug": name, "display_name": "Dr Asha Rao"})
            self.assertEqual(r.status_code, 422, f"{name} is reserved")

    def test_link_names_are_unique_and_pages_off_or_unverified_are_hidden(self):
        self.setup_calendar()
        self.as_(self.other)
        r = self.client.put("/v1/calendar/settings", json={"slug": self.slug, "display_name": "Rohan Mehta"})
        self.assertEqual(r.status_code, 409)
        self.assertEqual(r.json()["detail"]["error"], "slug_taken")
        self.as_(self.cid)
        self.setup_calendar(enabled=False)
        self.assertEqual(self.client.get(f"/v1/public/booking/{self.slug}").status_code, 404)
        self.setup_calendar()
        with psycopg.connect(URL, autocommit=True) as c:
            c.execute("update clinicians set verification_status='pending' where id=%s", (self.cid,))
        self.assertEqual(self.client.get(f"/v1/public/booking/{self.slug}").status_code, 404)
        self.assertEqual(self.client.get("/v1/public/booking/no-such-person").status_code, 404)

    def test_booking_cannot_be_switched_on_without_the_encryption_key(self):
        main.BOOKING.sealer = None
        r = self.client.put("/v1/calendar/settings", json={"slug": self.slug, "display_name": "Dr Asha Rao",
                                                           "enabled": True})
        self.assertEqual(r.status_code, 503)

    # --- booking and approval -----------------------------------------------------------------------
    def test_manual_approval_holds_the_time_until_answered(self):
        self.setup_calendar()
        r = self.book(at(10))
        self.assertEqual(r.status_code, 200, r.text)
        out = r.json()
        self.assertEqual(out["status"], "pending")
        self.assertNotIn(at(10), self.slots(), "a pending request holds its time")
        [a] = self.appts()
        self.assertEqual(a["client"], {"first_name": "Meera", "email": "client@example.com"})
        r = self.client.post(f"/v1/calendar/appointments/{a['id']}/confirm")
        self.assertEqual(r.json()["appointment"]["status"], "confirmed")
        self.assertEqual(self.client.post(f"/v1/calendar/appointments/{a['id']}/confirm").status_code, 409)
        self.assertEqual(self.client.get(f"/v1/public/booking/manage/{out['manage_token']}").json()["status"], "confirmed")

    def test_rejecting_frees_the_time(self):
        self.setup_calendar()
        self.book(at(10))
        [a] = self.appts()
        self.assertEqual(self.client.post(f"/v1/calendar/appointments/{a['id']}/reject").json()["appointment"]["status"],
                         "rejected")
        self.assertIn(at(10), self.slots())

    def test_auto_approval_confirms_at_once(self):
        self.setup_calendar(approval="auto")
        self.assertEqual(self.book(at(9)).json()["status"], "confirmed")

    def test_an_unanswered_request_expires_and_frees_the_time(self):
        self.setup_calendar()
        self.book(at(10))
        with psycopg.connect(URL, autocommit=True) as c:
            c.execute("update appointments set pending_until=now() - interval '1 minute' where clinician_id=%s", (self.cid,))
        self.assertIn(at(10), self.slots())
        self.assertEqual(self.appts()[0]["status"], "expired")
        self.assertEqual(self.book(at(10), email="other@example.com").status_code, 200)

    # --- double booking -----------------------------------------------------------------------------
    def test_the_same_time_cannot_be_booked_twice(self):
        self.setup_calendar(approval="auto")
        self.assertEqual(self.book(at(9)).status_code, 200)
        r = self.book(at(9), email="second@example.com")
        self.assertEqual(r.status_code, 409)
        self.assertEqual(r.json()["detail"]["error"], "slot_taken")

    def test_simultaneous_requests_for_one_time_give_exactly_one_booking(self):
        self.setup_calendar(approval="auto")
        codes, go = [], threading.Barrier(8)

        def attempt(i):
            client = TestClient(main.app)
            go.wait()
            codes.append(client.post(f"/v1/public/booking/{self.slug}", json={
                "starts_at": at(9, 30), "first_name": "Client", "email": f"c{i}@example.com", "consent": True}).status_code)
        threads = [threading.Thread(target=attempt, args=(i,)) for i in range(8)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.assertEqual(sorted(codes), [200] + [409] * 7)
        self.assertEqual(len([r for r in self.rows() if r["status"] in booking.ACTIVE]), 1)

    def test_the_database_refuses_an_overlap_even_without_the_app_checks(self):
        self.setup_calendar(approval="auto")
        self.book(at(9))
        with self.assertRaises(psycopg.errors.ExclusionViolation), psycopg.connect(URL, autocommit=True) as c:
            c.execute("""insert into appointments (clinician_id, starts_at, ends_at, blocked_until, status, source)
                         values (%s, %s, %s, %s, 'confirmed', 'consultant')""",
                      (self.cid, at(9, 15), at(9, 45), at(9, 45)))

    def test_buffer_blocks_the_time_on_both_sides(self):
        self.setup_calendar(approval="auto", buffer_minutes=15)
        self.book(at(10))
        free = self.slots()
        self.assertNotIn(at(9, 30), free, "9:30 + 30 min + 15 min buffer runs into 10:00")
        self.assertNotIn(at(10, 30), free, "10:30 starts inside the 10:00 booking's buffer")
        self.assertIn(at(9), free)

    # --- unavailable times --------------------------------------------------------------------------
    def test_outside_hours_past_and_too_soon_are_refused(self):
        self.setup_calendar()
        self.assertEqual(self.book(at(11)).status_code, 409, "the break")
        self.assertEqual(self.book(at(9, 10)).status_code, 409, "not on a slot boundary")
        self.assertEqual(self.book(at(9, d=DAY + timedelta(days=60))).status_code, 409, "beyond the advance limit")
        self.assertEqual(self.book("2020-01-06T04:00:00Z").status_code, 409, "the past")

    def test_time_off_and_holidays_remove_times_and_report_clashes(self):
        self.setup_calendar(approval="auto")
        self.book(at(9))
        r = self.client.post("/v1/calendar/time-off", json={"date_from": DAY.isoformat(), "label": "Holiday"})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["conflicts"], 1, "the existing appointment is reported, not silently cancelled")
        self.assertEqual(self.slots(), [])
        self.assertEqual(self.book(at(10), email="x@example.com").status_code, 409)
        self.assertEqual(self.client.post("/v1/calendar/appointments", json={"starts_at": at(12)}).status_code, 409)
        self.assertEqual(self.client.delete(f"/v1/calendar/time-off/{r.json()['time_off']['id']}").status_code, 200)
        self.assertIn(at(10), self.slots())
        r = self.client.post("/v1/calendar/time-off", json={"starts_at": at(12), "ends_at": at(13), "label": "Lunch"})
        self.assertEqual(r.json()["conflicts"], 0)
        self.assertNotIn(at(12, 30), self.slots())
        bad = self.client.post("/v1/calendar/time-off", json={"starts_at": at(13), "ends_at": at(12)})
        self.assertEqual(bad.status_code, 422)

    def test_consultant_adds_outside_hours_but_never_over_another_appointment(self):
        self.setup_calendar(approval="auto")
        r = self.client.post("/v1/calendar/appointments", json={"starts_at": at(18), "first_name": "Ravi",
                                                                "email": "ravi@example.com"})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["appointment"]["status"], "confirmed")
        self.assertEqual(self.client.post("/v1/calendar/appointments", json={"starts_at": at(18, 15)}).status_code, 409)
        self.assertEqual(self.client.post("/v1/calendar/appointments", json={"starts_at": "2020-01-06T04:00:00Z"}).status_code,
                         409)
        self.assertEqual(self.client.post("/v1/calendar/appointments", json={"starts_at": at(19)}).status_code, 200,
                         "an appointment with no client details")
        r = self.client.post("/v1/calendar/appointments", json={"starts_local": f"{DAY}T20:00"})
        self.assertEqual((r.status_code, r.json()["appointment"]["starts_at"]), (200, at(20)), "a wall time in India")
        self.assertEqual(self.client.post("/v1/calendar/appointments", json={"starts_local": "tomorrow 8pm"}).status_code, 422)

    # --- tags: First Session, Follow-up, Online ----------------------------------------------------------
    def test_the_client_picks_a_tag_and_the_consultant_can_change_it(self):
        self.setup_calendar()
        tags = self.client.get(f"/v1/public/booking/{self.slug}").json()["tags"]
        self.assertEqual([t["label"] for t in tags], ["First Session", "Follow-up", "Online"])
        r = self.book(at(9), tag="first_session")
        self.assertEqual((r.status_code, r.json()["tag_label"]), (200, "First Session"), r.text)
        self.assertEqual(self.book(at(10), email="b@example.com", tag="gold").status_code, 422, "one of the three only")
        self.assertEqual(self.book(at(10), email="b@example.com", tag=["online", "follow_up"]).status_code, 422,
                         "one tag, not several")
        self.assertIsNone(self.book(at(10), email="c@example.com").json()["tag_label"], "a tag is optional")
        [a, b] = self.appts()
        self.assertEqual((a["tag"], a["tag_label"], b["tag"]), ("first_session", "First Session", None))
        r = self.client.put(f"/v1/calendar/appointments/{a['id']}/tag", json={"tag": "follow_up"})
        self.assertEqual(r.json()["appointment"]["tag_label"], "Follow-up")
        self.assertIsNone(self.client.put(f"/v1/calendar/appointments/{a['id']}/tag", json={"tag": None})
                          .json()["appointment"]["tag"], "cleared")
        self.assertEqual(self.client.put(f"/v1/calendar/appointments/{a['id']}/tag", json={"tag": "x"}).status_code, 422)
        r = self.client.post("/v1/calendar/appointments", json={"starts_at": at(18), "tag": "online"})
        self.assertEqual(r.json()["appointment"]["tag_label"], "Online", "the consultant tags their own entries")
        with psycopg.connect(URL, autocommit=True) as c:
            with self.assertRaises(psycopg.errors.CheckViolation):
                c.execute("update appointments set tag='gold' where clinician_id=%s", (self.cid,))

    def test_a_tag_moves_with_a_reschedule_and_shows_on_the_clients_link(self):
        self.setup_calendar()
        token = self.book(at(9), tag="online").json()["manage_token"]
        [a] = self.appts()
        new = self.client.post(f"/v1/calendar/appointments/{a['id']}/reschedule",
                               json={"starts_at": at(10, 30)}).json()["appointment"]
        self.assertEqual(new["tag"], "online")
        self.assertEqual(self.client.get(f"/v1/public/booking/manage/{token}").json()["tag_label"], "Online")

    def test_the_tag_is_in_the_emails(self):
        self.setup_calendar()
        mail = main.BOOKING.mailer = FakeMailer()
        self.book(at(9), email="meera@example.com", tag="follow_up")
        bodies = {t: b for t, s, b in mail.sent}
        self.assertIn("Session: Follow-up", bodies["meera@example.com"])
        self.assertIn("Session: Follow-up", next(b for t, b in bodies.items() if t.endswith("@consultant.test")))

    # --- reschedule and cancel ----------------------------------------------------------------------
    def test_reschedule_moves_without_duplicates_and_the_client_link_follows(self):
        self.setup_calendar()
        token = self.book(at(9)).json()["manage_token"]
        [a] = self.appts()
        taken = self.book(at(12), email="b@example.com")
        self.assertEqual(taken.status_code, 200)
        self.assertEqual(self.client.post(f"/v1/calendar/appointments/{a['id']}/reschedule",
                                          json={"starts_at": at(12)}).status_code, 409, "onto a held time")
        r = self.client.post(f"/v1/calendar/appointments/{a['id']}/reschedule", json={"starts_at": at(10, 30)})
        self.assertEqual(r.status_code, 200, r.text)
        new = r.json()["appointment"]
        self.assertEqual((new["status"], new["starts_at"], new["rescheduled_from"]), ("confirmed", at(10, 30), a["id"]))
        self.assertEqual(new["client"]["first_name"], "Meera", "details re-sealed for the new appointment")
        self.assertEqual(new["local_start"], f"{DAY}T10:30", "wall-clock time in the consultant's timezone")
        active = [x for x in self.appts() if x["status"] in booking.ACTIVE]
        self.assertEqual(sorted(x["starts_at"] for x in active), [at(10, 30), at(12)])
        self.assertIn(at(9), self.slots(), "the old time is free again")
        self.assertEqual(self.client.get(f"/v1/public/booking/manage/{token}").json()["starts_at"], at(10, 30))
        self.assertEqual(self.client.post(f"/v1/calendar/appointments/{a['id']}/reschedule",
                                          json={"starts_at": at(9)}).status_code, 409, "the old row can't be moved again")
        r = self.client.post(f"/v1/calendar/appointments/{new['id']}/reschedule",
                             json={"starts_at": at(17), "outside_hours": True})
        self.assertEqual(r.status_code, 200, "the consultant may move it outside published hours")

    def test_the_client_cancels_with_their_link_once(self):
        self.setup_calendar(approval="auto")
        token = self.book(at(9)).json()["manage_token"]
        view = self.client.get(f"/v1/public/booking/manage/{token}").json()
        self.assertTrue(view["can_cancel"])
        self.assertNotIn("email", str(view))
        self.assertEqual(self.client.post(f"/v1/public/booking/manage/{token}/cancel").status_code, 200)
        self.assertEqual(self.client.post(f"/v1/public/booking/manage/{token}/cancel").status_code, 409)
        self.assertIn(at(9), self.slots())
        [a] = self.appts()
        self.assertEqual((a["status"], a["cancelled_by"]), ("cancelled", "client"))
        self.assertEqual(self.client.get("/v1/public/booking/manage/" + "x" * 32).status_code, 404)

    def test_consultant_cancels_and_completes(self):
        self.setup_calendar(approval="auto")
        self.book(at(9))
        [a] = self.appts()
        self.assertEqual(self.client.post(f"/v1/calendar/appointments/{a['id']}/complete").status_code, 409,
                         "not before it has started")
        self.assertEqual(self.client.post(f"/v1/calendar/appointments/{a['id']}/cancel").json()["appointment"]["status"],
                         "cancelled")
        self.assertEqual(self.client.post(f"/v1/calendar/appointments/{a['id']}/explode").status_code, 404)

    # --- access ----------------------------------------------------------------------------------------
    def test_a_consultant_sees_and_changes_only_their_own_calendar(self):
        self.setup_calendar(approval="auto")
        self.book(at(9))
        [a] = self.appts()
        self.as_(self.other)
        self.assertEqual(self.appts(), [])
        for action in ("confirm", "cancel", "reject", "complete"):
            self.assertEqual(self.client.post(f"/v1/calendar/appointments/{a['id']}/{action}").status_code, 404)
        self.client.put("/v1/calendar/settings", json={"slug": "rohan-" + self.other[:6], "display_name": "Rohan"})
        self.assertEqual(self.client.post(f"/v1/calendar/appointments/{a['id']}/reschedule",
                                          json={"starts_at": at(10), "outside_hours": True}).status_code, 404)
        self.as_(self.cid)
        self.assertEqual(self.appts()[0]["status"], "confirmed")

    def test_calendar_needs_a_verified_clinician(self):
        main.app.dependency_overrides.clear()
        self.assertEqual(self.client.get("/v1/calendar").status_code, 422, "no Authorization header")

    # --- invalid, automated and excessive requests --------------------------------------------------------
    def test_invalid_public_requests_are_refused(self):
        self.setup_calendar()
        cases = [
            ({"starts_at": at(9).replace("Z", "")}, 422),                     # no timezone offset
            ({"email": "not-an-email"}, 422),
            ({"name": "<b>x</b>"}, 422),
            ({"consent": False}, 422),
            ({"website": "http://spam.example"}, 422),                         # honeypot filled
            ({"phone": "9876543210"}, 422),                                    # unknown field
        ]
        for over, code in cases:
            body = {"starts_at": at(9), "first_name": "Meera", "email": "m@example.com", "consent": True}
            if "name" in over:
                body["first_name"] = over.pop("name")
            body.update(over)
            r = self.client.post(f"/v1/public/booking/{self.slug}", json=body)
            self.assertEqual(r.status_code, code, over)
        self.assertEqual(self.rows(), [], "nothing was stored")
        bad = self.client.get(f"/v1/public/booking/{self.slug}/slots", params={"start": DAY.isoformat(), "days": 90})
        self.assertEqual(bad.status_code, 422)

    def test_one_email_holds_at_most_two_upcoming_bookings(self):
        self.setup_calendar(approval="auto")
        self.assertEqual(self.book(at(9), email="Same@Example.com").status_code, 200)
        self.assertEqual(self.book(at(10), email="same@example.com").status_code, 200)
        r = self.book(at(12), email="same@example.com ")
        self.assertEqual(r.status_code, 409)
        self.assertEqual(r.json()["detail"]["error"], "too_many_bookings")

    def test_public_writes_are_rate_limited(self):
        self.setup_calendar()
        main.BOOKING.limit = booking_api._RateLimit(3, 600)
        codes = [self.book(at(9), email=f"r{i}@example.com").status_code for i in range(4)]
        self.assertEqual(codes[-1], 429)

    # --- privacy ---------------------------------------------------------------------------------------
    def test_client_details_are_encrypted_and_never_public(self):
        self.setup_calendar()
        token = self.book(at(9), email="private.person@example.com", name="Priyanka").json()["manage_token"]
        [row] = self.rows()
        raw = bytes(row["client_ct"])
        self.assertNotIn(b"Priyanka", raw)
        self.assertNotIn(b"private.person", raw)
        self.assertNotIn("private.person", str(row["email_hash"]))
        self.assertNotEqual(row["manage_hash"], token, "only a hash of the client's link is stored")
        for path in (f"/v1/public/booking/{self.slug}", f"/v1/public/booking/{self.slug}/slots?start={DAY}",
                     f"/v1/public/booking/manage/{token}"):
            text = self.client.get(path).text
            self.assertNotIn("Priyanka", text, path)
            self.assertNotIn("private.person", text, path)

    def test_emails_go_out_without_clinical_or_client_details_to_the_consultant(self):
        self.setup_calendar()
        mail = main.BOOKING.mailer = FakeMailer()
        self.book(at(9), email="meera@example.com")
        to = {t: (s, b) for t, s, b in mail.sent}
        self.assertIn("meera@example.com", to)
        self.assertIn("/book/manage/", to["meera@example.com"][1])
        consultant = [b for t, s, b in mail.sent if t.endswith("@consultant.test")]
        self.assertEqual(len(consultant), 1)
        self.assertNotIn("Meera", consultant[0])

    def test_without_email_notices_are_marked_not_configured(self):
        self.setup_calendar()
        self.book(at(9))
        with psycopg.connect(URL, autocommit=True) as c:
            statuses = {r[0] for r in c.execute(
                "select n.status from booking_notifications n join appointments a on a.id=n.appointment_id "
                "where a.clinician_id=%s", (self.cid,)).fetchall()}
        self.assertEqual(statuses, {"not_configured"})

    def test_scheduled_delivery_needs_the_cron_token(self):
        self.assertEqual(self.client.post("/v1/internal/booking/deliver").status_code, 404)
        self.assertEqual(self.client.post("/v1/internal/booking/deliver", headers={"X-Cron-Token": "wrong"}).status_code, 404)
        r = self.client.post("/v1/internal/booking/deliver", headers={"X-Cron-Token": "cron-secret-123"})
        self.assertEqual(r.status_code, 200)
        self.assertIn("purged", r.json())


if __name__ == "__main__":
    unittest.main()
