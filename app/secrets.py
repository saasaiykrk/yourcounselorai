"""
Keyvault — the ONE place secrets are read.

Maps the example handover's `keyvault.js` onto the Python backend. No secret is
ever read anywhere else in the code, and no secret is ever logged or returned in
a response. In production these come from Google Secret Manager (mounted as env
vars by Cloud Run); in local dev they come from a .env file (see .env.example).

If a required secret is missing, the app fails fast at startup with a clear
message rather than limping on and leaking a 500 later.
"""
from __future__ import annotations

import os
from dataclasses import dataclass

REQUIRED = ["ANTHROPIC_API_KEY", "CLAUDE_MODEL", "DATABASE_URL", "SUPABASE_JWKS_URL"]
OPTIONAL = {
    "SKILL_DIR": "skill/clinical-assist",
    "ICD_RELEASE": "2025-01",
    "WHO_ICD_CLIENT_ID": "",
    "WHO_ICD_CLIENT_SECRET": "",
    "DAILY_TURN_LIMIT": "40",
    "DEV_MODE": "0",
}
_MASK = 4  # show only the last N chars of any secret when describing config


@dataclass(frozen=True)
class Config:
    anthropic_api_key: str
    claude_model: str
    database_url: str
    supabase_jwks_url: str
    skill_dir: str
    icd_release: str
    who_icd_client_id: str
    who_icd_client_secret: str
    daily_turn_limit: int
    dev_mode: bool

    @property
    def icd_enabled(self) -> bool:
        return bool(self.who_icd_client_id and self.who_icd_client_secret)

    def public(self) -> dict:
        """Safe to log or return from /healthz — never contains secret values."""
        return {
            "claude_model": self.claude_model,
            "skill_dir": self.skill_dir,
            "icd_release": self.icd_release,
            "icd_enabled": self.icd_enabled,
            "dev_mode": self.dev_mode,
            "database": _host_only(self.database_url),
        }


def _host_only(dsn: str) -> str:
    # postgresql://user:pw@host:5432/db  ->  host:5432/db  (no credentials)
    try:
        return dsn.split("@", 1)[1] if "@" in dsn else "configured"
    except Exception:
        return "configured"


def load_config() -> Config:
    missing = [k for k in REQUIRED if not os.environ.get(k)]
    dev = os.environ.get("DEV_MODE", "0") == "1"
    if missing and not dev:
        raise RuntimeError(
            "Missing required secrets: " + ", ".join(missing) +
            ". Set them (Secret Manager in prod, .env in dev) — see .env.example. "
            "For a keyless local smoke test set DEV_MODE=1 (uses a fake model)."
        )
    g = lambda k: os.environ.get(k, OPTIONAL.get(k, ""))
    return Config(
        anthropic_api_key=g("ANTHROPIC_API_KEY"),
        claude_model=g("CLAUDE_MODEL") or "claude-opus-5-5",
        database_url=g("DATABASE_URL"),
        supabase_jwks_url=g("SUPABASE_JWKS_URL"),
        skill_dir=g("SKILL_DIR"),
        icd_release=g("ICD_RELEASE"),
        who_icd_client_id=g("WHO_ICD_CLIENT_ID"),
        who_icd_client_secret=g("WHO_ICD_CLIENT_SECRET"),
        daily_turn_limit=int(g("DAILY_TURN_LIMIT") or "40"),
        dev_mode=dev,
    )
