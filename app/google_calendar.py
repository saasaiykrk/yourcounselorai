"""
Google Calendar and Google Meet for bookings, server side only (OAuth for web server apps + Calendar API v3).

A consultant connects their own Google account once (scope calendar.events, offline access). The refresh token
is sealed by the caller (byok.Vault) and never leaves the backend. With it the server creates, moves and deletes
the event for each confirmed appointment on the consultant's primary calendar, with a Google Meet link
(conferenceData.createRequest, type hangoutsMeet) and the client invited (sendUpdates=all: Google emails them the
invitation and any change). The Calendar API and Meet links cost nothing; no Google Workspace plan is needed.

Nothing clinical is sent: the consultant's display name, the time, the session type (First Session · Follow-up ·
Online) and the client's email. Errors never contain tokens, names or addresses.

Docs: https://developers.google.com/identity/protocols/oauth2/web-server ·
https://developers.google.com/calendar/api/v3/reference/events
"""
from __future__ import annotations

import uuid
from datetime import datetime
from urllib.parse import urlencode

import httpx

AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"
REVOKE_URL = "https://oauth2.googleapis.com/revoke"
USERINFO_URL = "https://openidconnect.googleapis.com/v1/userinfo"
EVENTS_URL = "https://www.googleapis.com/calendar/v3/calendars/primary/events"
SCOPES = "https://www.googleapis.com/auth/calendar.events openid email"


class GoogleError(Exception):
    """Google could not be reached or refused. `revoked`: the consultant's permission is gone (reconnect)."""

    def __init__(self, message: str, revoked: bool = False, status: int | None = None):
        super().__init__(message)
        self.revoked = revoked
        self.status = status


class GoogleCalendar:
    def __init__(self, client_id: str, client_secret: str, timeout: float = 15.0, transport=None):
        self.client_id = client_id
        self._secret = client_secret
        self._http = httpx.Client(timeout=timeout, transport=transport)

    # --- OAuth ---------------------------------------------------------------------------------
    def auth_url(self, state: str, redirect_uri: str, login_hint: str | None = None) -> str:
        """Google's consent page. offline + consent: Google returns a refresh token every time. redirect_uri
        must be registered on the OAuth client (https://app.yourcounselor.in/v1/google/callback)."""
        q = {"client_id": self.client_id, "redirect_uri": redirect_uri, "response_type": "code",
             "scope": SCOPES, "access_type": "offline", "prompt": "consent", "include_granted_scopes": "true",
             "state": state}
        if login_hint:
            q["login_hint"] = login_hint
        return f"{AUTH_URL}?{urlencode(q)}"

    def _token(self, data: dict) -> dict:
        try:
            r = self._http.post(TOKEN_URL, data={**data, "client_id": self.client_id, "client_secret": self._secret})
        except httpx.HTTPError as e:
            raise GoogleError(f"Google unreachable ({type(e).__name__})") from None
        body = _json(r)
        if r.status_code >= 400:
            err = str(body.get("error", ""))
            raise GoogleError(f"Google sign-in {r.status_code}: {err[:60]}", revoked=err == "invalid_grant",
                              status=r.status_code)
        return body

    def exchange(self, code: str, redirect_uri: str) -> dict:
        """The code from the consent page → {refresh_token, access_token, scope, email}."""
        t = self._token({"code": code, "grant_type": "authorization_code", "redirect_uri": redirect_uri})
        if not t.get("refresh_token"):
            raise GoogleError("Google returned no refresh token")
        if "calendar.events" not in (t.get("scope") or ""):
            raise GoogleError("calendar permission not granted")
        t["email"] = self._email(t["access_token"])
        return t

    def access_token(self, refresh_token: str) -> str:
        return self._token({"refresh_token": refresh_token, "grant_type": "refresh_token"})["access_token"]

    def _email(self, access_token: str) -> str:
        info = self._call("GET", USERINFO_URL, access_token)
        if not info.get("email"):
            raise GoogleError("Google account has no email")
        return info["email"]

    def revoke(self, refresh_token: str) -> None:
        """Best effort: the consultant disconnected or deleted their account."""
        try:
            self._http.post(REVOKE_URL, data={"token": refresh_token})
        except httpx.HTTPError:
            pass

    # --- events --------------------------------------------------------------------------------
    def _call(self, method: str, url: str, access_token: str, **kw) -> dict:
        try:
            r = self._http.request(method, url, headers={"Authorization": f"Bearer {access_token}"}, **kw)
        except httpx.HTTPError as e:
            raise GoogleError(f"Google unreachable ({type(e).__name__})") from None
        if r.status_code in (404, 410) and method == "DELETE":
            return {}                                   # already gone (deleted in Google Calendar): fine
        if r.status_code >= 400:
            reason = str(_json(r).get("error", {}).get("status", "")) if isinstance(_json(r).get("error"), dict) else ""
            raise GoogleError(f"Google Calendar {r.status_code} {reason[:40]}".strip(),
                              revoked=r.status_code == 401, status=r.status_code)
        return _json(r) if r.content else {}

    @staticmethod
    def _times(start: datetime, end: datetime, tz: str) -> dict:
        return {"start": {"dateTime": start.isoformat(), "timeZone": tz},
                "end": {"dateTime": end.isoformat(), "timeZone": tz}}

    def create_event(self, access_token: str, *, appointment_id: str, summary: str, description: str,
                     start: datetime, end: datetime, tz: str, attendee: str | None, meet: bool) -> tuple[str, str | None]:
        """The event (and its Meet link). The appointment id makes the Meet request idempotent: a retry after a
        lost reply gets the same conference. Returns (event id, Meet URL or None)."""
        body = {"summary": summary, "description": description, **self._times(start, end, tz),
                "attendees": [{"email": attendee}] if attendee else [],
                "reminders": {"useDefault": True}, "guestsCanModify": False, "guestsCanInviteOthers": False,
                "extendedProperties": {"private": {"yourcounselor_appointment": appointment_id}}}
        if meet:
            body["conferenceData"] = {"createRequest": {
                "requestId": str(uuid.uuid5(uuid.NAMESPACE_URL, f"yourcounselor:{appointment_id}")),
                "conferenceSolutionKey": {"type": "hangoutsMeet"}}}
        ev = self._call("POST", EVENTS_URL, access_token, json=body,
                        params={"conferenceDataVersion": 1 if meet else 0, "sendUpdates": "all" if attendee else "none"})
        return ev["id"], meet_url(ev)

    def move_event(self, access_token: str, event_id: str, *, start: datetime, end: datetime, tz: str) -> str | None:
        """New time; Google tells the client. Returns the Meet URL (it stays the same)."""
        ev = self._call("PATCH", f"{EVENTS_URL}/{event_id}", access_token, json=self._times(start, end, tz),
                        params={"sendUpdates": "all"})
        return meet_url(ev)

    def delete_event(self, access_token: str, event_id: str) -> None:
        """Cancelled, declined or moved away: Google tells the client."""
        self._call("DELETE", f"{EVENTS_URL}/{event_id}", access_token, params={"sendUpdates": "all"})


def meet_url(event: dict) -> str | None:
    if event.get("hangoutLink"):
        return event["hangoutLink"]
    for ep in (event.get("conferenceData") or {}).get("entryPoints", []):
        if ep.get("entryPointType") == "video" and ep.get("uri"):
            return ep["uri"]
    return None


def _json(r: httpx.Response) -> dict:
    try:
        v = r.json()
    except ValueError:
        return {}
    return v if isinstance(v, dict) else {}
