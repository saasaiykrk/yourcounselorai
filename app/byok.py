"""
"Use my Anthropic API key" (BYOK): storing, checking and using a clinician's own key.

  * The key is encrypted with AES-256-GCM before it is stored. The encryption key comes from
    Secret Manager (BYOK_ENCRYPTION_KEY, 32 bytes, base64) and is versioned so it can be rotated;
    the clinician's id is bound in as associated data, so a stored key cannot be moved to
    another account.
  * No endpoint ever returns the key: only its last 4 characters and whether it works.
  * The key is checked with a cheap call (reading the pinned model's details: no tokens used)
    before it is saved, and the report call uses the same pinned model as the platform.
  * If the clinician's key fails, the error says why; the platform key is never used instead.
"""
from __future__ import annotations

import base64
import os
from dataclasses import dataclass

KEY_PREFIX = "sk-ant-"


class ByokError(Exception):
    """code: invalid_key · no_access · rate_limited · insufficient_balance · provider_error · not_configured"""
    MESSAGES = {
        "invalid_key": "Anthropic did not accept this API key. Check it, or create a new key at console.anthropic.com.",
        "no_access": "This API key cannot use the model the app needs. Check the key's workspace and permissions.",
        "rate_limited": "Your Anthropic account is at its rate limit. Wait a minute and try again.",
        "insufficient_balance": "Your Anthropic account has too little credit. Add credit at console.anthropic.com, then try again.",
        "provider_error": "Anthropic is not responding right now. Try again in a few minutes.",
        "not_configured": "Your own API key is not set up. Add it under Pricing → Use My Anthropic API Key.",
    }

    def __init__(self, code: str):
        super().__init__(code)
        self.code = code
        self.message = self.MESSAGES[code]


@dataclass(frozen=True)
class Sealed:
    ciphertext: bytes
    nonce: bytes
    key_version: int
    last4: str


class Vault:
    """AES-256-GCM with versioned keys: BYOK_ENCRYPTION_KEY (current) and optional
    BYOK_ENCRYPTION_KEY_PREVIOUS for reading keys stored before a rotation."""

    def __init__(self, keys: dict[int, bytes], current: int):
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
        self._aes = {v: AESGCM(k) for v, k in keys.items()}
        self.current = current

    @classmethod
    def from_secrets(cls, current_b64: str, previous_b64: str = "", version: int = 1) -> "Vault | None":
        if not current_b64:
            return None
        keys = {version: _key(current_b64)}
        if previous_b64:
            keys[version - 1] = _key(previous_b64)
        return cls(keys, version)

    def seal(self, clinician_id: str, api_key: str) -> Sealed:
        nonce = os.urandom(12)
        ct = self._aes[self.current].encrypt(nonce, api_key.encode(), str(clinician_id).encode())
        return Sealed(ct, nonce, self.current, api_key[-4:])

    def open(self, clinician_id: str, ciphertext: bytes, nonce: bytes, key_version: int) -> str:
        aes = self._aes.get(key_version)
        if aes is None:
            raise ByokError("not_configured")
        return aes.decrypt(bytes(nonce), bytes(ciphertext), str(clinician_id).encode()).decode()


def _key(b64: str) -> bytes:
    raw = base64.b64decode(b64)
    if len(raw) != 32:
        raise ValueError("BYOK_ENCRYPTION_KEY must be 32 bytes, base64-encoded")
    return raw


def looks_like_key(api_key: str) -> bool:
    k = (api_key or "").strip()
    return k.startswith(KEY_PREFIX) and 40 <= len(k) <= 300 and k.isascii() and " " not in k


def map_error(exc: Exception) -> ByokError:
    """An Anthropic SDK exception → the clinician-facing reason. Never includes the key."""
    import anthropic
    if isinstance(exc, ByokError):
        return exc
    if isinstance(exc, anthropic.AuthenticationError):
        return ByokError("invalid_key")
    if isinstance(exc, (anthropic.PermissionDeniedError, anthropic.NotFoundError)):
        return ByokError("no_access")
    if isinstance(exc, anthropic.RateLimitError):
        return ByokError("rate_limited")
    if isinstance(exc, anthropic.BadRequestError) and "credit balance" in str(getattr(exc, "message", "")).lower():
        return ByokError("insufficient_balance")
    if isinstance(exc, anthropic.APIStatusError) and exc.status_code == 402:
        return ByokError("insufficient_balance")
    return ByokError("provider_error")


def check_key(api_key: str, model: str) -> None:
    """Raises ByokError if Anthropic does not accept the key for the pinned model. No tokens are used."""
    import anthropic
    client = anthropic.Anthropic(api_key=api_key, max_retries=1, timeout=20)
    try:
        client.models.retrieve(model)
    except Exception as e:  # noqa: BLE001 - every failure maps to a reason; the key is never logged
        raise map_error(e) from None
