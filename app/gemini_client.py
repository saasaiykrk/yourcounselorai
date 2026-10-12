"""
Google Gemini client, an OPTIONAL alternative to app/claude_client.py with the same interface
(run with a tool loop; run_structured for JSON). Chosen with MODEL_PROVIDER=gemini; the default
stays Anthropic.

* Everything around the model is unchanged: the same skill prompt, the same tools (knowledge cards
  and WHO ICD-11), the cleaner before, and the inspector after every reply. Nothing reaches the
  phone without passing inspect().
* Using it for clinicians is a model change (CLAUDE.md rule 3): evals, the clinician grading pack,
  a CHANGELOG entry and the clinician-reviewed label first. Until then it is for side-by-side evals.
* Plain REST (httpx) against the Gemini API's generateContent; no extra SDK.

⚠ Written against the documented REST shapes but not yet run against the live API from this repo
(no key in the build environment). Smoke-test with a real key before relying on it. The tool loop,
refusals and the cut-off handling are covered by tests/test_gemini_client.py against a fake server.
"""
from __future__ import annotations

import json

import httpx

from .claude_client import MAX_TOOL_ROUNDS, REPLY_MAX_TOKENS
from .pipeline import ModelResult

BASE_URL = "https://generativelanguage.googleapis.com/v1beta"
# Reasons Gemini gives for producing nothing usable; treated like a Claude refusal (held back).
_BLOCKED = {"SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII", "IMAGE_SAFETY", "OTHER"}
# JSON Schema keywords the Gemini schema subset does not take; dropped before sending.
_UNSUPPORTED = {"additionalProperties", "$schema", "$id", "default", "examples"}


class GeminiError(RuntimeError):
    """The Gemini API refused the request (bad key, quota, outage). Never carries the key."""

    def __init__(self, status: int, reason: str):
        super().__init__(f"Gemini {status}: {reason}"[:300])
        self.status = status


class GeminiClient:
    def __init__(self, api_key: str, model: str, max_tokens: int = REPLY_MAX_TOKENS,
                 transport: httpx.BaseTransport | None = None, timeout: float = 300):
        self.model, self.max_tokens = model, max_tokens
        # The key goes in a header, never in the URL, so it can't end up in an access log.
        self._http = httpx.Client(base_url=BASE_URL, timeout=timeout, transport=transport,
                                  headers={"x-goog-api-key": api_key, "Content-Type": "application/json"})

    def _generate(self, body: dict) -> dict:
        for attempt in range(3):
            try:
                r = self._http.post(f"/models/{self.model}:generateContent", json=body)
            except httpx.TransportError:
                if attempt == 2:
                    raise
                continue
            if r.status_code in (429, 500, 503) and attempt < 2:
                continue
            if r.status_code != 200:
                try:
                    reason = r.json().get("error", {}).get("message", "")
                except ValueError:
                    reason = ""
                raise GeminiError(r.status_code, reason or "request failed")
            return r.json()
        raise GeminiError(503, "unavailable")

    def run(self, system: str | list[str], messages: list[dict], tools: list[dict], tool_handler) -> ModelResult:
        contents = [_content(m) for m in messages]
        decls = [{"name": t["name"], "description": t.get("description", ""),
                  "parameters": _schema(t.get("input_schema", {"type": "object"}))} for t in tools]
        texts: list[str] = []
        usage_total: dict[str, int] = {}
        calls: list[dict] = []
        for _ in range(MAX_TOOL_ROUNDS):
            body = {"systemInstruction": {"parts": [{"text": p} for p in _parts(system)]},
                    "contents": contents,
                    "generationConfig": {"maxOutputTokens": self.max_tokens}}
            if decls:
                body["tools"] = [{"functionDeclarations": decls}]
            resp = self._generate(body)
            _add_usage(usage_total, resp)
            cand = (resp.get("candidates") or [{}])[0]
            reason = cand.get("finishReason", "")
            if reason == "MAX_TOKENS":
                usage_total["max_tokens_stops"] = usage_total.get("max_tokens_stops", 0) + 1
            parts = (cand.get("content") or {}).get("parts") or []
            if reason in _BLOCKED or resp.get("promptFeedback", {}).get("blockReason") or not cand:
                texts.append("")                 # deliver nothing: the inspector fails it, retry, then held back
                break
            fcalls = [p["functionCall"] for p in parts if "functionCall" in p]
            round_text = "".join(p.get("text", "") for p in parts if not p.get("thought"))
            if not fcalls:
                texts.append(round_text)
                break
            # Send the model turn back exactly as received (it may carry thought signatures).
            contents.append({"role": "model", "parts": parts})
            results = []
            for fc in fcalls:
                args = fc.get("args") or {}
                out = tool_handler(fc.get("name", ""), args)
                calls.append({"name": fc.get("name"), "input": args})
                results.append({"functionResponse": {"name": fc.get("name", ""), "response": {"result": out}}})
            contents.append({"role": "user", "parts": results})
        # As with Claude, only the final round's text is the reply (the contract line comes first).
        return ModelResult(text=texts[-1] if texts else "", model=self.model, usage=usage_total, tool_calls=calls)

    def run_structured(self, system: str, user: str, schema: dict, max_tokens: int = 2000) -> tuple[dict | None, dict]:
        """One short call that must return JSON matching `schema`. (None, usage) if declined or unusable."""
        resp = self._generate({
            "systemInstruction": {"parts": [{"text": p} for p in _parts(system)]},
            "contents": [{"role": "user", "parts": [{"text": user}]}],
            "generationConfig": {"maxOutputTokens": max_tokens, "responseMimeType": "application/json",
                                 "responseSchema": _schema(schema)},
        })
        usage: dict[str, int] = {}
        _add_usage(usage, resp)
        cand = (resp.get("candidates") or [{}])[0]
        if cand.get("finishReason") in _BLOCKED | {"MAX_TOKENS"} or not cand:
            return None, usage
        text = "".join(p.get("text", "") for p in (cand.get("content") or {}).get("parts") or [] if not p.get("thought"))
        try:
            out = json.loads(text)
        except ValueError:
            return None, usage
        return (out if isinstance(out, dict) else None), usage


def _parts(system: str | list[str]) -> list[str]:
    return [system] if isinstance(system, str) else list(system)


def _content(m: dict) -> dict:
    """{"role": "user"|"assistant", "content": str} → a Gemini content entry."""
    return {"role": "model" if m["role"] == "assistant" else "user", "parts": [{"text": str(m["content"])}]}


def _schema(s):
    """JSON Schema → the subset Gemini takes (drops keywords it rejects, recursively)."""
    if isinstance(s, dict):
        return {k: _schema(v) for k, v in s.items() if k not in _UNSUPPORTED}
    if isinstance(s, list):
        return [_schema(x) for x in s]
    return s


def _add_usage(total: dict[str, int], resp: dict) -> None:
    """Gemini's counts under the same names the Claude client uses, so cost figures line up."""
    u = resp.get("usageMetadata") or {}
    cached = int(u.get("cachedContentTokenCount") or 0)
    pairs = {"input_tokens": int(u.get("promptTokenCount") or 0) - cached,
             "cache_read_input_tokens": cached,
             "output_tokens": int(u.get("candidatesTokenCount") or 0) + int(u.get("thoughtsTokenCount") or 0)}
    for k, v in pairs.items():
        total[k] = total.get(k, 0) + v
