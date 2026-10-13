"""
Which AI model writes the replies, and the provider keys an admin adds in the web admin.

  * The model is one of app/ai_models.APPROVED (rule 3 is enforced there); the default is the
    server's configured model (CLAUDE_MODEL / MODEL_PROVIDER).
  * A key added by an admin is encrypted (AES-256-GCM, BYOK_ENCRYPTION_KEY, the provider name bound
    in) before it is stored; it is never returned, logged or put in an audit row (last 4 only).
    It takes priority over the server's own key for that provider; removing it falls back to that.
  * ModelRouter is what the pipeline calls. It re-reads the choice at most every TTL seconds, so a
    switch reaches every server instance within that time, and it builds a client only when the
    model or key actually changed. Every reply still goes through the cleaner and the inspector.
"""
from __future__ import annotations

import hashlib
import json
import threading
import time

from . import ai_models


class AiSettingsError(Exception):
    def __init__(self, code: str, message: str, status: int = 422):
        super().__init__(message)
        self.code, self.message, self.status = code, message, status


# --- database -------------------------------------------------------------------------------------
class AiStore:
    """Rows of migration 008. Never touches key values in clear."""

    def __init__(self, conn_factory):
        self._conn = conn_factory

    def active_model(self) -> dict | None:
        with self._conn() as c:
            return c.execute("select s.active_model, s.updated_at, u.email as updated_by_email from ai_settings s "
                             "left join auth.users u on u.id = s.updated_by where s.id = 1").fetchone()

    def set_model(self, model: str, previous: str, actor) -> None:
        with self._conn() as c, c.transaction():
            c.execute("""insert into ai_settings (id, active_model, updated_by) values (1, %s, %s)
                         on conflict (id) do update set active_model = excluded.active_model,
                           updated_by = excluded.updated_by, updated_at = now()""", (model, str(actor)))
            self._audit(c, actor, "ai_model", {"from": previous, "to": model})

    def keys(self) -> dict[str, dict]:
        with self._conn() as c:
            rows = c.execute("select k.provider, k.ciphertext, k.nonce, k.key_version, k.last4, k.updated_at, "
                             "u.email as updated_by_email from ai_provider_keys k "
                             "left join auth.users u on u.id = k.updated_by").fetchall()
        return {r["provider"]: r for r in rows}

    def save_key(self, provider: str, sealed, actor) -> None:
        with self._conn() as c, c.transaction():
            c.execute("""insert into ai_provider_keys (provider, ciphertext, nonce, key_version, last4, updated_by)
                         values (%s, %s, %s, %s, %s, %s)
                         on conflict (provider) do update set ciphertext = excluded.ciphertext, nonce = excluded.nonce,
                           key_version = excluded.key_version, last4 = excluded.last4,
                           updated_by = excluded.updated_by, updated_at = now()""",
                      (provider, sealed.ciphertext, sealed.nonce, sealed.key_version, sealed.last4, str(actor)))
            self._audit(c, actor, "ai_key_set", {"provider": provider, "last4": sealed.last4})

    def delete_key(self, provider: str, actor) -> bool:
        with self._conn() as c, c.transaction():
            gone = c.execute("delete from ai_provider_keys where provider = %s", (provider,)).rowcount > 0
            if gone:
                self._audit(c, actor, "ai_key_removed", {"provider": provider})
            return gone

    def history(self, limit: int = 20) -> list[dict]:
        with self._conn() as c:
            return c.execute("""select a.created_at, a.action, a.detail, u.email as actor_email from admin_audit a
                                left join auth.users u on u.id = a.actor_id
                                where a.action in ('ai_model', 'ai_key_set', 'ai_key_removed')
                                order by a.created_at desc limit %s""", (limit,)).fetchall()

    @staticmethod
    def _audit(c, actor, action: str, detail: dict) -> None:
        c.execute("insert into admin_audit (actor_id, action, target_id, detail) values (%s, %s, null, %s)",
                  (str(actor), action, json.dumps(detail)))


def _aad(provider: str) -> str:
    return f"platform-ai-key:{provider}"          # binds a stored key to its provider


def default_client_factory(provider: str, api_key: str, model: str):
    if provider == "gemini":
        from .gemini_client import GeminiClient
        return GeminiClient(api_key, model)
    from .claude_client import AnthropicClient
    return AnthropicClient(api_key, model)


# --- the model the pipeline uses -----------------------------------------------------------------
class ModelRouter:
    """Looks like a model client (run, run_structured, .model) and forwards to the active one."""

    def __init__(self, cfg, store: AiStore | None, vault, factory=default_client_factory, ttl: float = 30,
                 clock=time.monotonic):
        self.cfg, self.store, self.vault, self.factory, self.ttl, self.clock = cfg, store, vault, factory, ttl, clock
        self._lock = threading.Lock()
        self._client, self._sig, self._checked = None, None, float("-inf")

    # what is configured -------------------------------------------------------------------------
    def server_key(self, provider: str) -> str:
        return self.cfg.gemini_api_key if provider == "gemini" else self.cfg.anthropic_api_key

    def default_model(self) -> str:
        return self.cfg.platform_model

    def provider_of(self, model: str) -> str:
        m = ai_models.find(model)
        if m:
            return m["provider"]
        return "gemini" if model.startswith("gemini") else "anthropic"

    def admin_key(self, provider: str, rows: dict | None = None) -> str | None:
        if self.store is None or self.vault is None:
            return None
        row = (rows if rows is not None else self.store.keys()).get(provider)
        if not row:
            return None
        try:
            return self.vault.open(_aad(provider), row["ciphertext"], row["nonce"], row["key_version"])
        except Exception:      # noqa: BLE001 - e.g. sealed under a rotated-away key: treat as not set
            return None

    def key_for(self, provider: str, rows: dict | None = None) -> str:
        return self.admin_key(provider, rows) or self.server_key(provider)

    def active_model_id(self) -> str:
        if self.store is not None:
            try:
                row = self.store.active_model()
            except Exception:  # noqa: BLE001 - the database being down must not stop consults
                row = None
            if row and ai_models.find(row["active_model"]):
                return row["active_model"]
        return self.default_model()

    # the client ---------------------------------------------------------------------------------
    def current(self):
        with self._lock:
            now = self.clock()
            if self._client is not None and now - self._checked < self.ttl:
                return self._client
            model = self.active_model_id()
            provider = self.provider_of(model)
            key = self.key_for(provider)
            if not key:            # chosen provider has no key any more: stay on the server's default model
                model = self.default_model()
                provider = self.provider_of(model)
                key = self.key_for(provider)
            sig = (model, provider, hashlib.sha256(key.encode()).hexdigest())
            if sig != self._sig:
                self._client, self._sig = self.factory(provider, key, model), sig
            self._checked = now
            return self._client

    def invalidate(self) -> None:
        with self._lock:
            self._checked = float("-inf")

    @property
    def model(self) -> str:
        return self.current().model

    def run(self, system, messages, tools, tool_handler):
        return self.current().run(system, messages, tools, tool_handler)

    def run_structured(self, system, user, schema, max_tokens: int = 2000):
        return self.current().run_structured(system, user, schema, max_tokens=max_tokens)


# --- admin actions --------------------------------------------------------------------------------
def looks_like_key(provider: str, api_key: str) -> bool:
    k = (api_key or "").strip()
    if not (20 <= len(k) <= 300 and k.isascii() and " " not in k):
        return False
    return k.startswith("sk-ant-") if provider == "anthropic" else not k.startswith("sk-ant-")


def check_key(provider: str, api_key: str, transport=None) -> None:
    """Raises AiSettingsError if the provider does not accept the key. No tokens are used."""
    model = next((m["id"] for m in ai_models.APPROVED if m["provider"] == provider), None)
    if provider == "anthropic":
        from . import byok
        try:
            byok.check_key(api_key, model)
        except byok.ByokError as e:
            raise AiSettingsError("key_rejected", e.message.replace("Your Anthropic", "The Anthropic")) from None
        return
    from .gemini_client import GeminiClient, GeminiError
    try:
        GeminiClient(api_key, model, transport=transport).check()
    except GeminiError as e:
        if e.status in (400, 401, 403):
            raise AiSettingsError("key_rejected", "Google did not accept this Gemini API key, or it cannot use "
                                                  f"{model}. Check the key in Google AI Studio.") from None
        raise AiSettingsError("provider_error", "Google is not responding right now. Try again in a few minutes.",
                              503) from None
