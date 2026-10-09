"""
WHO ICD-11 API client (ICD-11 MMS linearization), used by the `icd11_lookup` tool.

Register at https://icd.who.int/icdapi to get a client id/secret.
Auth: OAuth2 client-credentials → https://icdaccessmanagement.who.int/connect/token (scope icdapi_access)
Search: GET https://id.who.int/icd/release/11/{release}/mms/search?q=...
Code:   GET https://id.who.int/icd/release/11/{release}/mms/codeinfo/{code} → stemId → GET it for the title
Headers: Authorization: Bearer …, Accept: application/json, Accept-Language: en, API-Version: v2

The release is PINNED (ICD_RELEASE) so codes don't shift under you; bump it
deliberately, like a model version, and re-run evals.

⚠ Written against WHO's published API documentation but NOT yet run against the
live API from this repo — verify response field names in staging (Day 3 task).
"""
from __future__ import annotations

import re
import time

TOKEN_URL = "https://icdaccessmanagement.who.int/connect/token"
BASE = "https://id.who.int/icd/release/11/{release}/mms"


class ICD11Client:
    def __init__(self, client_id: str, client_secret: str, release: str, timeout: float = 10.0, transport=None):
        import httpx  # imported lazily so the stdlib-only unit tests don't need it
        self.client_id, self.client_secret, self.release = client_id, client_secret, release
        self._token: str | None = None
        self._token_exp = 0.0
        self._http = httpx.Client(timeout=timeout, transport=transport)

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
        # Search often returns only sub-codes (6B23.0, 6B23.1) while a report names the category
        # (6B23). Add each missing parent with WHO's own title, so the model sees it and it is verified.
        have = {h["code"] for h in out}
        for parent in dict.fromkeys(h["code"].split(".")[0] for h in out if "." in h["code"]):
            if parent not in have:
                info = self.code_info(parent)
                if info:
                    out.append(info)
                    have.add(parent)
        return out

    def code_info(self, code: str) -> dict | None:
        """WHO's own record of one exact code in the pinned release, or None if WHO has no such code."""
        r = self._http.get(BASE.format(release=self.release) + f"/codeinfo/{code}", headers=self._headers(),
                           params={"flexiblemode": "false"})
        if r.status_code == 404:
            return None
        r.raise_for_status()
        stem = (r.json().get("stemId") or "").replace("http://", "https://", 1)
        if not stem:
            return None
        e = self._http.get(stem, headers=self._headers())
        e.raise_for_status()
        body = e.json()
        title = body.get("title")
        title = title.get("@value", "") if isinstance(title, dict) else str(title or "")
        return {"code": body.get("code") or code, "title": re.sub(r"<[^>]+>", "", title), "release": self.release}


class OfflineICD11:
    """Used in tests and when ICD credentials are absent: returns nothing, so the
    model must write 'code to confirm at icd.who.int'. Never fabricates."""
    release = "offline"

    def search(self, query: str, limit: int = 8) -> list[dict]:
        return []

    def code_info(self, code: str) -> dict | None:
        return None
