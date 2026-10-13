"""
Web admin → AI Model: which approved model writes the replies, and provider API keys.

  GET    /v1/admin/ai                     → active model, approved models, key status (last 4 only), history
  PUT    /v1/admin/ai/model               → switch to an approved model (typed confirmation; audited)
  PUT    /v1/admin/ai/keys/{provider}     → add or replace a key (checked with the provider first; audited)
  DELETE /v1/admin/ai/keys/{provider}     → remove an admin key (the server's own key is used again)

Admins only. A key is never returned, logged or written to the audit log.
"""
from __future__ import annotations

from fastapi import Depends, FastAPI, HTTPException
from pydantic import BaseModel, Field

from . import ai_models
from .ai_settings import AiSettingsError, ModelRouter, _aad, check_key, looks_like_key


class ModelIn(BaseModel):
    model: str = Field(max_length=100)
    confirm: str = Field(max_length=100)          # the model id typed again


class KeyIn(BaseModel):
    api_key: str = Field(min_length=20, max_length=300)


def _iso(d):
    return d.isoformat() if d else None


def install(app: FastAPI, router: ModelRouter, admin, key_checker=check_key) -> None:

    def need_store():
        if router.store is None:
            raise HTTPException(503, {"error": "ai_settings_unavailable",
                                      "message": "AI settings need the database (not available in dev mode)."})

    def fail(e: AiSettingsError):
        return HTTPException(e.status, {"error": e.code, "message": e.message})

    def status(rows: dict) -> dict:
        out = {}
        for p in ai_models.PROVIDERS:
            row = rows.get(p)
            if row and router.admin_key(p, rows):
                out[p] = {"source": "admin", "last4": row["last4"], "updated_at": _iso(row["updated_at"]),
                          "updated_by": row["updated_by_email"]}
            elif router.server_key(p):
                out[p] = {"source": "server", "last4": router.server_key(p)[-4:]}
            else:
                out[p] = {"source": "none"}
        return out

    @app.get("/v1/admin/ai")
    def ai_get(_: dict = Depends(admin)):
        need_store()
        rows = router.store.keys()
        keys = status(rows)
        active = router.active_model_id()
        row = router.store.active_model()
        return {
            "active_model": active,
            "default_model": router.default_model(),
            "changed_at": _iso(row["updated_at"]) if row else None,
            "changed_by": row["updated_by_email"] if row else None,
            "models": [{**m, "active": m["id"] == active, "key_ready": keys[m["provider"]]["source"] != "none"}
                       for m in ai_models.APPROVED],
            "keys": keys,
            "can_store_keys": router.vault is not None,
            "history": [{"at": _iso(h["created_at"]), "action": h["action"], "detail": h["detail"],
                         "by": h["actor_email"]} for h in router.store.history()],
        }

    @app.put("/v1/admin/ai/model")
    def ai_model(body: ModelIn, a: dict = Depends(admin)):
        need_store()
        m = ai_models.find(body.model)
        if m is None:
            raise HTTPException(422, {"error": "not_approved",
                                      "message": "Only approved models can be chosen (app/ai_models.py)."})
        if body.confirm.strip() != m["id"]:
            raise HTTPException(422, {"error": "confirm", "message": f"Type {m['id']} to confirm the switch."})
        if not router.key_for(m["provider"]):
            raise HTTPException(409, {"error": "no_key",
                                      "message": f"Add a {m['provider'].capitalize()} API key before switching to {m['label']}."})
        previous = router.active_model_id()
        if previous != m["id"]:
            router.store.set_model(m["id"], previous, a["id"])
            router.invalidate()
        return {"active_model": m["id"]}

    @app.put("/v1/admin/ai/keys/{provider}")
    def ai_key_set(provider: str, body: KeyIn, a: dict = Depends(admin)):
        need_store()
        if provider not in ai_models.PROVIDERS:
            raise HTTPException(404, "not found")
        if router.vault is None:
            raise HTTPException(503, {"error": "not_configured",
                                      "message": "Keys can't be stored until BYOK_ENCRYPTION_KEY is set on the server."})
        key = body.api_key.strip()
        if not looks_like_key(provider, key):
            raise HTTPException(422, {"error": "invalid_format",
                                      "message": "That doesn't look like an Anthropic key (sk-ant-…)." if provider == "anthropic"
                                      else "That doesn't look like a Gemini API key."})
        try:
            key_checker(provider, key)
        except AiSettingsError as e:
            raise fail(e)
        router.store.save_key(provider, router.vault.seal(_aad(provider), key), a["id"])
        router.invalidate()
        return {"provider": provider, "source": "admin", "last4": key[-4:]}

    @app.delete("/v1/admin/ai/keys/{provider}")
    def ai_key_delete(provider: str, a: dict = Depends(admin)):
        need_store()
        if provider not in ai_models.PROVIDERS:
            raise HTTPException(404, "not found")
        if router.provider_of(router.active_model_id()) == provider and not router.server_key(provider):
            raise HTTPException(409, {"error": "in_use", "message": "This key is in use by the active model and the "
                                      "server has no key of its own. Switch to another model first."})
        if not router.store.delete_key(provider, a["id"]):
            raise HTTPException(404, {"error": "not_found", "message": "No admin key is stored for this provider."})
        router.invalidate()
        return {"provider": provider, "removed": True}
