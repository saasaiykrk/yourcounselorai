"""Booking rules with no database: slots from working hours, breaks, buffers, notice, time off,
existing bookings, timezones and daylight-saving days; settings and client-detail validation."""
import importlib.util
import unittest
from datetime import date, datetime, time, timedelta, timezone

from app import booking
from app.booking import BookingError, Rules, free_slots

UTC = timezone.utc
MON = date(2026, 10, 12)                       # a Monday
IST_RULES = Rules("Asia/Kolkata", 30, 0, 0, 30)
NOW = datetime(2026, 10, 11, 0, 0, tzinfo=UTC)  # the day before


def ist(h, m=0, d=MON):
    return datetime(d.year, d.month, d.day, h, m, tzinfo=booking.zone("Asia/Kolkata")).astimezone(UTC)


class SlotTests(unittest.TestCase):
    def test_working_hours_make_slots_and_a_gap_is_a_break(self):
        windows = [(0, time(9), time(11)), (0, time(12), time(13))]       # break 11–12
        got = free_slots(IST_RULES, windows, [], [], NOW, MON, 1)[MON]
        self.assertEqual(got, [ist(9), ist(9, 30), ist(10), ist(10, 30), ist(12), ist(12, 30)])

    def test_slot_lengths_15_to_60(self):
        for minutes, count in ((15, 8), (30, 4), (45, 2), (60, 2)):
            rules = Rules("Asia/Kolkata", minutes, 0, 0, 30)
            got = free_slots(rules, [(0, time(9), time(11))], [], [], NOW, MON, 1)[MON]
            self.assertEqual(len(got), count, minutes)

    def test_booked_time_plus_buffer_is_not_offered(self):
        rules = Rules("Asia/Kolkata", 30, 15, 0, 30)
        busy = [(ist(9, 30), ist(10) + timedelta(minutes=15))]           # 9:30–10:00 booked, +15 buffer
        got = free_slots(rules, [(0, time(9), time(11))], [], busy, NOW, MON, 1)[MON]
        # 9:00 would run into the 9:30 booking once its own buffer is added; 10:00 starts inside the buffer.
        self.assertEqual(got, [ist(10, 30)])

    def test_time_off_and_holidays_remove_slots(self):
        off = [(ist(10), ist(11)), (ist(0, 0, date(2026, 10, 13)), ist(0, 0, date(2026, 10, 14)))]
        got = free_slots(IST_RULES, [(0, time(9), time(11)), (1, time(9), time(11))], off, [], NOW, MON, 2)
        self.assertEqual(got[MON], [ist(9), ist(9, 30)])
        self.assertNotIn(date(2026, 10, 13), got, "a whole day off has no slots")

    def test_minimum_notice_and_maximum_advance(self):
        rules = Rules("Asia/Kolkata", 30, 0, 120, 1)
        now = ist(8, 0)
        got = free_slots(rules, [(0, time(9), time(12)), (1, time(9), time(12))], [], [], now, MON, 3)
        self.assertEqual(got[MON][0], ist(10), "nothing inside the 2-hour notice")
        self.assertNotIn(date(2026, 10, 13), got, "Tuesday 09:00 is more than 1 day ahead of Monday 08:00")
        self.assertTrue(all(s <= now + timedelta(days=1) for d in got for s in got[d]))

    def test_consultant_view_can_ignore_notice(self):
        rules = Rules("Asia/Kolkata", 30, 0, 600, 30)
        got = free_slots(rules, [(0, time(9), time(10))], [], [], ist(8), MON, 1, honour_notice=False)
        self.assertEqual(got[MON], [ist(9), ist(9, 30)])

    def test_slots_follow_the_clock_across_daylight_saving(self):
        rules = Rules("Europe/London", 60, 0, 0, 30)
        spring = date(2026, 3, 29)                                        # 01:00 → 02:00 on this Sunday
        now = datetime(2026, 3, 28, tzinfo=UTC)
        got = free_slots(rules, [(6, time(0), time(4))], [], [], now, spring, 1)[spring]
        london = booking.zone("Europe/London")
        walls = [s.astimezone(london).strftime("%H:%M") for s in got]
        self.assertEqual(walls, ["00:00", "02:00", "03:00"], "01:00 does not exist that day")
        autumn = date(2026, 10, 25)                                       # 02:00 → 01:00
        got = free_slots(rules, [(6, time(9), time(11))], [], [], datetime(2026, 10, 24, tzinfo=UTC), autumn, 1)[autumn]
        self.assertEqual([s.astimezone(london).strftime("%H:%M %Z") for s in got], ["09:00 GMT", "10:00 GMT"])
        self.assertEqual(got[0], datetime(2026, 10, 25, 9, 0, tzinfo=UTC), "after the change, London = UTC")


class ValidationTests(unittest.TestCase):
    def test_settings_problems_are_all_listed(self):
        with self.assertRaises(BookingError) as cm:
            booking.validate_settings({"slug": "Admin", "display_name": "x", "slot_minutes": 20,
                                       "timezone": "Mars/Base", "approval": "maybe", "colour": "red"})
        text = " | ".join(cm.exception.problems)
        for part in ("slug", "display_name", "slot_minutes", "timezone", "approval", "unknown settings"):
            self.assertIn(part, text)
        ok = booking.validate_settings({"slug": "dr-asha-rao", "display_name": "Dr Asha Rao"})
        self.assertEqual((ok["slot_minutes"], ok["approval"], ok["timezone"]), (30, "manual", "Asia/Kolkata"))

    def test_reserved_and_odd_slugs_are_refused(self):
        for slug in ("book", "a", "-dr", "dr-", "dr--x", "dr_x", "x" * 41):
            with self.assertRaises(BookingError, msg=slug):
                booking.validate_settings({"slug": slug, "display_name": "Dr X"})

    def test_windows_must_not_overlap(self):
        with self.assertRaises(BookingError):
            booking.validate_windows([{"weekday": 0, "start": "09:00", "end": "12:00"},
                                      {"weekday": 0, "start": "11:00", "end": "13:00"}])
        for bad in ({"weekday": 7, "start": "09:00", "end": "10:00"}, {"weekday": 0, "start": "10:00", "end": "09:00"},
                    {"weekday": 0, "start": "9am", "end": "10:00"}):
            with self.assertRaises(BookingError, msg=bad):
                booking.validate_windows([bad])
        self.assertEqual(len(booking.validate_windows([{"weekday": 0, "start": "09:00", "end": "13:00"},
                                                       {"weekday": 0, "start": "14:00", "end": "18:00"}])), 2)

    def test_client_details(self):
        self.assertEqual(booking.validate_client("  Asha ", " Asha@Example.COM "), ("Asha", "asha@example.com"))
        for name, mail in (("", "a@b.co"), ("A1", "a@b.co"), ("<script>", "a@b.co"), ("Asha", "not-an-email")):
            with self.assertRaises(BookingError, msg=(name, mail)):
                booking.validate_client(name, mail)

    def test_times_need_an_offset(self):
        self.assertEqual(booking.parse_utc("2026-10-12T04:30:00Z"), ist(10))
        with self.assertRaises(BookingError):
            booking.parse_utc("2026-10-12T10:00:00")


@unittest.skipUnless(importlib.util.find_spec("cryptography"), "cryptography not installed")
class SealerTests(unittest.TestCase):
    def test_details_are_sealed_and_bound_to_their_appointment(self):
        import base64, os
        s = booking.Sealer(base64.b64encode(os.urandom(32)).decode())
        ct, nonce, _ = s.seal("appt-1", {"first_name": "Asha", "email": "asha@example.com"})
        self.assertNotIn(b"asha", ct.lower())
        self.assertEqual(s.open("appt-1", ct, nonce)["first_name"], "Asha")
        with self.assertRaises(Exception):
            s.open("appt-2", ct, nonce)
        self.assertEqual(s.email_hash("a@b.co"), s.email_hash("a@b.co"))


if __name__ == "__main__":
    unittest.main()
