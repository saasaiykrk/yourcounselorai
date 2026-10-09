"""
Razorpay, server side only: orders, payment checks, refunds and webhook signatures.

The key secret and webhook secret come from Secret Manager (app/secrets.py) and never leave the
backend; the app only ever sees the public key id. A payment counts only after BOTH the checkout
signature (HMAC of "order_id|payment_id" with the key secret) is valid AND Razorpay itself reports
the payment as captured for that order and amount — the app's "success" callback is never proof.

Docs: https://razorpay.com/docs/payments/server-integration/ (orders, payments, refunds, webhooks).
"""
from __future__ import annotations

import hashlib
import hmac

import httpx

API = "https://api.razorpay.com/v1"


class RazorpayError(Exception):
    """Razorpay could not be reached or refused the request. Never contains secrets."""


def _hmac(secret: str, message: bytes) -> str:
    return hmac.new(secret.encode(), message, hashlib.sha256).hexdigest()


def checkout_signature_ok(key_secret: str, order_id: str, payment_id: str, signature: str) -> bool:
    expected = _hmac(key_secret, f"{order_id}|{payment_id}".encode())
    return hmac.compare_digest(expected, signature or "")


def webhook_signature_ok(webhook_secret: str, raw_body: bytes, signature: str) -> bool:
    return hmac.compare_digest(_hmac(webhook_secret, raw_body), signature or "")


class Razorpay:
    def __init__(self, key_id: str, key_secret: str, timeout: float = 20.0, transport=None):
        self.key_id = key_id
        self._client = httpx.Client(base_url=API, auth=(key_id, key_secret), timeout=timeout, transport=transport)
        self._secret = key_secret

    def signature_ok(self, order_id: str, payment_id: str, signature: str) -> bool:
        return checkout_signature_ok(self._secret, order_id, payment_id, signature)

    def _call(self, method: str, path: str, **kw) -> dict:
        try:
            r = self._client.request(method, path, **kw)
        except httpx.HTTPError as e:
            raise RazorpayError(f"Razorpay unreachable ({type(e).__name__})") from None
        if r.status_code >= 400:
            try:
                desc = r.json().get("error", {}).get("description", "")
            except ValueError:
                desc = ""
            raise RazorpayError(f"Razorpay {r.status_code}: {desc[:200]}")
        return r.json()

    def create_order(self, amount: int, currency: str, receipt: str, notes: dict) -> dict:
        """payment_capture=1: Razorpay captures the payment itself once it is authorised."""
        return self._call("POST", "/orders", json={"amount": amount, "currency": currency, "receipt": receipt[:40],
                                                   "payment_capture": 1, "notes": notes})

    def payment(self, payment_id: str) -> dict:
        return self._call("GET", f"/payments/{payment_id}")

    def order_payments(self, order_id: str) -> list[dict]:
        return self._call("GET", f"/orders/{order_id}/payments").get("items", [])

    def refund(self, payment_id: str, amount: int, notes: dict) -> dict:
        return self._call("POST", f"/payments/{payment_id}/refund", json={"amount": amount, "notes": notes})
