"""
WHO ICD-11 API client (ICD-11 MMS linearization), used by the `icd11_lookup` tool.

Register at https://icd.who.int/icdapi to get a client id/secret.
Auth: OAuth2 client-credentials → https://icdaccessmanagement.who.int/connect/token (scope icdapi_access)
Search: GET https://id.who.int/icd/release/11/{release}/mms/search?q=...
Headers: Authorization: Bearer …, Accept: application/json, Accept-Language: en, API-Version: v2

The release is PINNED (ICD_RELEASE) so codes don't shift under you; bump it
deliberately, like a model version, and re-run evals.

⚠ Written against WHO's published API documentation but NOT yet run against the
live API from this repo — verify response field names in staging (Day 3 task).
"""
from __future__ import annotations

import re
import time

import httpx

TOKEN_URL = "https://icdaccessmanagement.who.int/connect/token"
BASE = "https://id.who.int/icd/release/11/{release}/mms"


class ICD11Client:
    def __init__(self, client_id: str, client_secret: str, release: str, timeout: float = 10.0):
        self.client_id, self.client_secret, self.release = client_id, client_secret, release
        self._token: str | None = None
        self._token_exp = 0.0
        self._http = httpx.Client(timeout=timeout)

    def _auth(self) -> str:
        if self._token and time.time() < self._token_exp - 60:
            return self._token
        r = self._http.post(TOKEN_URL, data={
            "client_id": self.client_id, "client_secret": self.client_secret,
            "scope": "icdapi_access", "grant_type": "client_credentials"})
        r.raise_for_status()
        body = r.json()
        self._token = body["access_token"]
        self._token_exp = time.time() + int(body.get("expires_in", 3600))
        return self._token

    def _headers(self) -> dict:
        return {"Authorization": f"Bearer {self._auth()}", "Accept": "application/json",
                "Accept-Language": "en", "API-Version": "v2"}

    def search(self, query: str, limit: int = 8) -> list[dict]:
        r = self._http.get(BASE.format(release=self.release) + "/search", headers=self._headers(), params={
            "q": query, "flatResults": "true", "highlightingEnabled": "false", "useFlexisearch": "true"})
        r.raise_for_status()
        out = []
        for e in r.json().get("destinationEntities", [])[:limit]:
            code = e.get("theCode") or ""
            title = re.sub(r"<[^>]+>", "", e.get("title", ""))
            if code:
                out.append({"code": code, "title": title, "release": self.release})
        return out


class OfflineICD11:
    """Used in tests and when ICD credentials are absent: returns nothing, so the
    model must write 'code to confirm at icd.who.int'. Never fabricates."""
    release = "offline"

    def search(self, query: str, limit: int = 8) -> list[dict]:
        return []
