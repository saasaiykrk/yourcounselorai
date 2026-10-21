"""
Booking emails. Sent only when SMTP is configured (SMTP_HOST, SMTP_FROM, …); otherwise every queued
notice is marked not_configured and booking works exactly the same.

What emails say: the consultant's display name, the date and time, the status, and (to the client)
their own manage/cancel link. Never anything clinical. Emails to the consultant do not name the
client: they say to open the app. Nothing here logs an address or a name.
"""
from __future__ import annotations

import smtplib
import ssl
from datetime import datetime
from email.message import EmailMessage

from . import booking

SUBJECTS = {
    "requested": "Appointment request received",
    "confirmed": "Your appointment is confirmed",
    "rejected": "Your appointment request was declined",
    "cancelled": "Your appointment was cancelled",
    "rescheduled": "Your appointment was moved",
    "reminder": "Reminder: your appointment tomorrow",
    "new_booking": "New appointment on your calendar",
}


def when(dt: datetime, tz_name: str) -> str:
    local = dt.astimezone(booking.zone(tz_name))
    return f"{local:%A %d %B %Y, %I:%M %p} ({tz_name})"


def compose(n: dict, details: dict | None, base_url: str) -> tuple[str, str, str] | None:
    """(to, subject, body) for one queued notice, or None if there is no one to send it to."""
    at = when(n["starts_at"], n["timezone"])
    name = n["display_name"]
    kind = booking.TAGS.get(n.get("tag") or "")
    session = f"\nSession: {kind}\n" if kind else ""
    if n["recipient"] == "consultant":
        to = n.get("clinician_email")
        if not to:
            return None
        if n["kind"] == "cancelled":
            body = f"An appointment on {at} was cancelled by the client. The time is free again."
            subject = "An appointment was cancelled"
        else:
            body = f"A new appointment {'request ' if n['status'] == 'pending' else ''}for {at}.\n\n" \
                   "Open YourCounselor → Calendar to see it" + (" and accept or decline it." if n["status"] == "pending" else ".") \
                   + session.rstrip("\n")
            subject = SUBJECTS["new_booking"]
        return to, subject, body + "\n\n— YourCounselor"
    if not details or not details.get("email"):
        return None
    hello = f"Hello {details.get('first_name') or ''},".replace(" ,", ",")
    manage = f"{base_url}/book/manage/{details['manage_token']}" if details.get("manage_token") else None
    lines = {
        "requested": f"Your request for an appointment with {name} on {at} has been received. "
                     f"{name} will confirm it soon; you will get another email.",
        "confirmed": f"Your appointment with {name} on {at} is confirmed.",
        "rejected": f"{name} could not accept your request for {at}. You are welcome to choose another time.",
        "cancelled": f"Your appointment with {name} on {at} has been cancelled.",
        "rescheduled": f"Your appointment with {name} has been moved to {at}.",
        "reminder": f"A reminder: your appointment with {name} is on {at}.",
    }
    if n["kind"] not in lines:
        return None
    body = f"{hello}\n\n{lines[n['kind']]}\n" + (session if n["kind"] not in ("rejected", "cancelled") else "")
    if manage and n["kind"] in ("requested", "confirmed", "rescheduled", "reminder"):
        body += f"\nTo see or cancel your appointment: {manage}\n"
    if n["kind"] == "rejected":
        body += f"\nBook again: {base_url}/{n['slug']}\n"
    body += "\nIf you are in crisis or need urgent help, contact local emergency services.\n\n— YourCounselor"
    return details["email"], SUBJECTS[n["kind"]], body


class Mailer:
    def __init__(self, host: str, port: int, username: str, password: str, sender: str, timeout: float = 15):
        self.host, self.port, self.username, self.password, self.sender, self.timeout = \
            host, port, username, password, sender, timeout

    @classmethod
    def from_config(cls, cfg) -> "Mailer | None":
        if not cfg.email_configured:
            return None
        return cls(cfg.smtp_host, cfg.smtp_port, cfg.smtp_username, cfg.smtp_password, cfg.smtp_from)

    def send(self, to: str, subject: str, body: str) -> None:
        msg = EmailMessage()
        msg["From"], msg["To"], msg["Subject"] = self.sender, to, subject
        msg.set_content(body)
        ctx = ssl.create_default_context()
        if self.port == 465:
            with smtplib.SMTP_SSL(self.host, self.port, timeout=self.timeout, context=ctx) as s:
                if self.username:
                    s.login(self.username, self.password)
                s.send_message(msg)
        else:
            with smtplib.SMTP(self.host, self.port, timeout=self.timeout) as s:
                s.starttls(context=ctx)
                if self.username:
                    s.login(self.username, self.password)
                s.send_message(msg)
