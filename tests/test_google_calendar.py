"""Google Calendar + Google Meet for bookings, against a real Postgres with a fake Google. Skipped without
TEST_DATABASE_URL.

What must hold:
- a consultant connects with Google's consent page; the refresh token is stored sealed, never returned;
- every confirmed appointment gets an event on their calendar, with the client invited and a Meet link when
  their choice allows (Online only, or all); a pending request gets none until it is accepted;
- moving an appointment moves the same event (same Meet link); cancelling or declining deletes it;
- the emails carry the Meet link; nothing clinical goes to Google;
- Google failing never breaks a booking: the scheduled delivery retries, a removed permission asks to
  reconnect, and reconnecting catches up."""
import base64
import os
import unittest
import uuid
from types import SimpleNamespace
from urllib.parse import parse_qs, urlsplit

from tests.test_booking_api import DAY, HAVE, IST, URL, FakeMailer, at

if HAVE:
    import httpx
    import psycopg
    from fastapi.testclient import TestClient

    from app import booking, booking_api, booking_db, byok, db, main
    from app.google_calendar import GoogleCalendar

MEET = "https://meet.google.com/abc-defg-hij"


class FakeGoogle:
    """Just enough of Google's OAuth and Calendar API v3."""

    def __init__(self):
        self.events, self.calls, self.revoked = {}, [], []
        self.down = False
        self.refresh_ok = True

    def handler(self, request):
        url, method = str(request.url), request.method
        self.calls.append((method, url.split("?")[0]))
        if url.startswith("https://oauth2.googleapis.com/token"):
            form = parse_qs(request.content.decode())
            if form["grant_type"] == ["authorization_code"]:
                if form["code"] == ["good"]:
                    return httpx.Response(200, json={"access_token": "at-1", "refresh_token": "rt-secret-1",
                                                     "scope": "openid https://www.googleapis.com/auth/calendar.events "
                                                              "https://www.googleapis.com/auth/userinfo.email"})
                if form["code"] == ["nocal"]:
                    return httpx.Response(200, json={"access_token": "at-1", "refresh_token": "rt-secret-1",
                                                     "scope": "openid email"})
                return httpx.Response(400, json={"error": "invalid_grant"})
            if not self.refresh_ok:
                return httpx.Response(400, json={"error": "invalid_grant"})
            return httpx.Response(200, json={"access_token": "at-2"})
        if url.startswith("https://oauth2.googleapis.com/revoke"):
            self.revoked.append(parse_qs(request.content.decode())["token"][0])
            return httpx.Response(200, json={})
        if url.startswith("https://openidconnect.googleapis.com/v1/userinfo"):
            return httpx.Response(200, json={"email": "dr.asha@gmail.com"})
        if "/calendar/v3/calendars/primary/events" in url:
            if self.down:
                return httpx.Response(503, json={"error": {"status": "UNAVAILABLE"}})
            assert request.headers["authorization"] == "Bearer at-2"
            params = parse_qs(urlsplit(url).query)
            if method == "POST":
                body = __import__("json").loads(request.content)
                eid = "ev" + uuid.uuid4().hex[:8]
                ev = {"id": eid, **body, "params": params}
                if body.get("conferenceData"):
                    ev["hangoutLink"] = MEET
                self.events[eid] = ev
                return httpx.Response(200, json=ev)
            eid = url.split("/events/")[1].split("?")[0]
            if method == "PATCH":
                self.events[eid].update(__import__("json").loads(request.content))
                self.events[eid]["patched"] = params
                return httpx.Response(200, json=self.events[eid])
            if method == "DELETE":
                self.events[eid]["deleted"] = params
                return httpx.Response(204)
        return httpx.Response(404, json={})


@unittest.skipUnless(HAVE, "TEST_DATABASE_URL not set")
class GoogleCalendarTests(unittest.TestCase):
    def setUp(self):
        self.cid = str(uuid.uuid4())
        self.slug = "dr-" + self.cid[:8]
        with psycopg.connect(URL, autocommit=True) as c:
            c.execute("insert into auth.users (id, email) values (%s,%s)", (self.cid, f"{self.cid[:8]}@consultant.test"))
            c.execute("""insert into clinicians (id, full_name, role, registration_body, level, verification_status,
                           consent_version) values (%s,'Dr. Asha Rao','psychologist','RCI','L2','verified','v1')""",
                      (self.cid,))
        main.app.dependency_overrides[main.verified_clinician] = lambda: {**db.get_clinician(self.cid), "id": self.cid}
        svc = main.BOOKING
        self.saved = (svc.cfg, svc.store, svc.store_on, svc.sealer, svc.mailer, svc.limit, svc.google, svc.vault)
        svc.cfg = SimpleNamespace(public_base_url="https://yc.test", cron_token="cron-secret-123",
                                  google_oauth_client_id="client-id.apps.googleusercontent.com",
                                  google_oauth_client_secret="client-secret-xyz")
        svc.store, svc.store_on = booking_db, (lambda: True)
        svc.sealer = booking.Sealer(base64.b64encode(os.urandom(32)).decode())
        self.mail = FakeMailer()
        svc.mailer = self.mail
        svc.limit = booking_api._RateLimit(1000, 600)
        self.g = FakeGoogle()
        svc.google = GoogleCalendar("client-id.apps.googleusercontent.com", "client-secret-xyz",
                                    transport=httpx.MockTransport(self.g.handler))
        svc.vault = byok.Vault.from_secrets(base64.b64encode(os.urandom(32)).decode())
        self.client = TestClient(main.app)

    def tearDown(self):
        main.app.dependency_overrides.clear()
        svc = main.BOOKING
        svc.cfg, svc.store, svc.store_on, svc.sealer, svc.mailer, svc.limit, svc.google, svc.vault = self.saved

    # --- helpers --------------------------------------------------------------------------------------
    def setup_calendar(self, approval="auto"):
        s = {"slug": self.slug, "display_name": "Dr Asha Rao", "enabled": True, "timezone": IST, "slot_minutes": 30,
             "buffer_minutes": 0, "min_notice_minutes": 240, "max_advance_days": 30, "approval": approval}
        self.assertEqual(self.client.put("/v1/calendar/settings", json=s).status_code, 200)
        wd = DAY.weekday()
        self.client.put("/v1/calendar/availability", json={"windows": [{"weekday": wd, "start": "09:00", "end": "13:00"}]})

    def connect(self, meet_for="all"):
        url = self.client.post("/v1/calendar/google/connect").json()["url"]
        state = parse_qs(urlsplit(url).query)["state"][0]
        r = self.client.get("/v1/google/callback", params={"code": "good", "state": state})
        self.assertEqual(r.status_code, 200, r.text)
        self.client.put("/v1/calendar/google", json={"meet_for": meet_for})
        return r

    def book(self, h, m=0, **extra):
        r = self.client.post(f"/v1/public/booking/{self.slug}", json={
            "starts_at": at(h, m), "first_name": "Meera", "email": "client@example.com", "consent": True, **extra})
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()

    def row(self):
        with psycopg.connect(URL, autocommit=True, row_factory=psycopg.rows.dict_row) as c:
            return c.execute("""select * from appointments where clinician_id=%s and status in ('pending','confirmed')
                                order by created_at desc limit 1""", (self.cid,)).fetchone()

    def cron(self):
        r = self.client.post("/v1/internal/booking/deliver", headers={"X-Cron-Token": "cron-secret-123"})
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()

    # --- connecting ---------------------------------------------------------------------------------------
    def test_connect_goes_through_googles_consent_page_and_stores_the_token_sealed(self):
        self.setup_calendar()
        self.assertEqual(self.client.get("/v1/calendar/google").json(),
                         {"available": True, "connected": False, "status": None, "email": None, "meet_for": "online"})
        url = self.client.post("/v1/calendar/google/connect").json()["url"]
        q = parse_qs(urlsplit(url).query)
        self.assertTrue(url.startswith("https://accounts.google.com/o/oauth2/v2/auth"))
        self.assertEqual(q["redirect_uri"], ["https://yc.test/v1/google/callback"])
        self.assertEqual((q["access_type"], q["prompt"]), (["offline"], ["consent"]))
        self.assertIn("https://www.googleapis.com/auth/calendar.events", q["scope"][0])
        for bad in ("", "nonsense", q["state"][0][:-2] + "00", f"{uuid.uuid4()}.9999999999.abc"):
            r = self.client.get("/v1/google/callback", params={"code": "good", "state": bad})
            self.assertEqual(r.status_code, 400, bad)
        self.assertFalse(self.client.get("/v1/calendar/google").json()["connected"], "a forged state connects nothing")
        r = self.client.get("/v1/google/callback", params={"code": "nocal", "state": q["state"][0]})
        self.assertEqual(r.status_code, 400, "calendar permission must be granted")
        r = self.client.get("/v1/google/callback", params={"code": "good", "state": q["state"][0]})
        self.assertIn("Google Calendar connected", r.text)
        g = self.client.get("/v1/calendar/google").json()
        self.assertEqual((g["connected"], g["status"], g["email"]), (True, "ok", "dr.asha@gmail.com"))
        stored = booking_db.google_connection(self.cid)
        self.assertNotIn(b"rt-secret-1", bytes(stored["ciphertext"]), "the refresh token is sealed")
        self.assertNotIn("rt-secret", r.text + str(g))

    def test_without_the_oauth_client_it_is_not_offered(self):
        self.setup_calendar()
        main.BOOKING.google = None
        self.assertFalse(self.client.get("/v1/calendar/google").json()["available"])
        self.assertEqual(self.client.post("/v1/calendar/google/connect").status_code, 503)

    # --- events -----------------------------------------------------------------------------------------
    def test_a_booking_gets_an_event_with_the_client_invited_a_meet_link_and_emails_carry_it(self):
        self.setup_calendar()
        self.connect("all")
        self.book(10, tag="first_session")
        ev = next(iter(self.g.events.values()))
        self.assertEqual(ev["attendees"], [{"email": "client@example.com"}])
        self.assertEqual(ev["params"]["sendUpdates"], ["all"], "Google sends the client the invitation")
        self.assertEqual(ev["params"]["conferenceDataVersion"], ["1"])
        self.assertEqual(ev["conferenceData"]["createRequest"]["conferenceSolutionKey"], {"type": "hangoutsMeet"})
        self.assertEqual(ev["summary"], "Appointment with Dr Asha Rao")
        self.assertEqual(ev["description"], "Session: First Session\nBooked with YourCounselor.", "nothing clinical")
        self.assertEqual(ev["start"]["timeZone"], IST)
        r = self.row()
        self.assertEqual((r["meet_url"], r["google_sync"]), (MEET, "done"))
        appt = self.client.get("/v1/calendar/appointments", params={"start": DAY.isoformat(),
                                                                     "end": DAY.isoformat()}).json()["appointments"][0]
        self.assertEqual(appt["meet_url"], MEET, "the app shows Join Google Meet")
        client = [b for to, s, b in self.mail.sent if to == "client@example.com"]
        consultant = [b for to, s, b in self.mail.sent if to != "client@example.com"]
        self.assertIn(f"Join on Google Meet: {MEET}", client[0])
        self.assertIn(f"Google Meet: {MEET}", consultant[0])

    def test_online_only_adds_meet_just_to_online_appointments(self):
        self.setup_calendar()
        self.connect("online")
        self.book(10, tag="first_session")
        self.book(11, tag="online", email="other@example.com")
        evs = sorted(self.g.events.values(), key=lambda e: e["start"]["dateTime"])
        self.assertNotIn("conferenceData", evs[0], "an in-person session: a calendar event, no Meet")
        self.assertIn("conferenceData", evs[1])

    def test_a_request_gets_its_event_only_when_accepted(self):
        self.setup_calendar(approval="manual")
        self.connect("all")
        self.book(10)
        self.assertEqual(self.g.events, {}, "a pending request: no event yet")
        appt_id = self.row()["id"]
        self.assertEqual(self.client.post(f"/v1/calendar/appointments/{appt_id}/confirm").status_code, 200)
        self.assertEqual(len(self.g.events), 1)
        self.assertEqual(self.row()["meet_url"], MEET)

    def test_moving_moves_the_same_event_and_cancelling_deletes_it(self):
        self.setup_calendar()
        self.connect("all")
        self.book(10)
        first = self.row()
        eid = first["google_event_id"]
        r = self.client.post(f"/v1/calendar/appointments/{first['id']}/reschedule", json={"starts_at": at(11)})
        self.assertEqual(r.status_code, 200, r.text)
        moved = self.row()
        self.assertEqual((moved["google_event_id"], moved["meet_url"]), (eid, MEET), "same event, same Meet link")
        self.assertEqual(self.g.events[eid]["patched"]["sendUpdates"], ["all"])
        self.assertTrue(self.g.events[eid]["start"]["dateTime"].startswith(at(11)[:13]))
        self.assertEqual(len(self.g.events), 1, "no second event")
        self.assertEqual(self.client.post(f"/v1/calendar/appointments/{moved['id']}/cancel").status_code, 200)
        self.assertIn("deleted", self.g.events[eid])

    # --- when Google fails ------------------------------------------------------------------------------
    def test_google_down_never_breaks_the_booking_and_the_scheduled_delivery_retries(self):
        self.setup_calendar()
        self.connect("all")
        self.g.down = True
        self.book(10)
        self.assertEqual((self.row()["status"], self.row()["google_sync"]), ("confirmed", "pending"))
        self.g.down = False
        self.assertEqual(self.cron()["google"]["created"], 1)
        self.assertEqual(self.row()["meet_url"], MEET)

    def test_repeated_failures_stop_retrying(self):
        self.setup_calendar()
        self.connect("all")
        self.g.down = True
        self.book(10)
        for _ in range(6):
            self.cron()
        self.assertEqual(self.row()["google_sync"], "failed")

    def test_a_removed_permission_asks_to_reconnect_and_reconnecting_catches_up(self):
        self.setup_calendar()
        self.connect("all")
        self.g.refresh_ok = False
        self.book(10)
        self.assertEqual(self.client.get("/v1/calendar/google").json()["status"], "revoked")
        self.assertEqual(self.row()["google_sync"], "pending", "waits for the reconnect")
        self.g.refresh_ok = True
        self.connect("all")
        self.assertEqual(self.row()["meet_url"], MEET)

    def test_disconnect_revokes_and_forgets(self):
        self.setup_calendar()
        self.connect("all")
        g = self.client.delete("/v1/calendar/google").json()
        self.assertFalse(g["connected"])
        self.assertEqual(self.g.revoked, ["rt-secret-1"])
        self.assertIsNone(booking_db.google_connection(self.cid))
        self.book(10)
        self.assertEqual(self.g.events, {}, "no connection: no event")

    def test_the_clients_manage_page_shows_the_meet_link(self):
        self.setup_calendar()
        self.connect("all")
        token = None
        self.book(10)
        body = next(b for to, s, b in self.mail.sent if to == "client@example.com")
        token = body.split("/book/manage/")[1].split()[0]
        self.assertEqual(self.client.get(f"/v1/public/booking/manage/{token}").json()["meet_url"], MEET)

    def test_deleting_the_account_forgets_the_google_connection(self):
        self.setup_calendar()
        self.connect("all")
        db.delete_account(self.cid)
        self.assertIsNone(booking_db.google_connection(self.cid))
