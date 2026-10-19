"""
The /health page for people: what /health reports, as a readable status page. Scripts (curl, the deploy
smoke test) keep getting the JSON; a browser, which asks for text/html, gets this page.

Shows only what /health already reports, plus whether the database answers. Never shows hosts, keys or
any clinician or client data.
"""
from __future__ import annotations

import html
from datetime import datetime, timedelta, timezone

IST = timezone(timedelta(hours=5, minutes=30))


def wants_html(accept: str, fmt: str | None) -> bool:
    """A browser asks for text/html first; curl sends */*. ?format=json always gets JSON."""
    if fmt == "json":
        return False
    if fmt == "html":
        return True
    return "text/html" in (accept or "").split(",")[0]


def checks(info: dict, database: bool | None) -> list[tuple[str, str, str]]:
    """(name, state, detail); state is ok · warn · bad · off."""
    provider = "Google Gemini" if info.get("model_provider") == "gemini" else "Anthropic Claude"
    rows = [
        ("Server", "ok", "Running"),
        ("Database", "off" if database is None else "ok" if database else "bad",
         "Not used in development mode" if database is None else "Answering" if database else "Not answering"),
        ("AI model", "ok" if info.get("model") else "bad", f"{info.get('model') or 'Not set'} ({provider})"),
        ("Knowledge base", "ok", f"Version {info.get('skill_version', '?')}"),
        ("WHO ICD-11 codes", "ok" if info.get("icd_enabled") else "warn",
         f"Connected (release {info.get('icd_release', '?')})" if info.get("icd_enabled") else "Keys not set"),
        ("Payments (Razorpay)", "ok" if info.get("payments_configured") else "off",
         "Set up" if info.get("payments_configured") else "Not set up"),
        ("Booking emails", "ok" if info.get("email_configured") else "off",
         "Set up" if info.get("email_configured") else "Not set up"),
        ("Mode", "warn" if info.get("dev_mode") else "ok",
         "Development (DEV_MODE is on: never on the live server)" if info.get("dev_mode") else "Live"),
    ]
    return rows


def render(info: dict, database: bool | None, now: datetime | None = None) -> str:
    rows = checks(info, database)
    worst = "bad" if any(s == "bad" for _, s, _ in rows) else "warn" if any(s == "warn" for _, s, _ in rows) else "ok"
    headline = {"ok": "All systems working", "warn": "Working, with warnings", "bad": "Something is not working"}[worst]
    when = (now or datetime.now(timezone.utc)).astimezone(IST).strftime("%d %b %Y, %I:%M %p IST")
    label = {"ok": "OK", "warn": "Check", "bad": "Problem", "off": "Off"}
    items = "".join(
        f'<li><span class="name">{html.escape(n)}</span><span class="detail">{html.escape(d)}</span>'
        f'<span class="pill {s}">{label[s]}</span></li>' for n, s, d in rows)
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="60"><meta name="robots" content="noindex">
<title>Service status · YourCounselor</title>
<style>
:root{{--ink:#1E1030;--muted:#5A5068;--deep:#3F0079;--bg:#FAF7FD;--line:#E6DDF0;--card:#fff;
  --ok:#1E7A46;--okbg:#E3F4EA;--warn:#7F440A;--warnbg:#FAEBD8;--bad:#8E2A2A;--badbg:#F7E2DF;--off:#5A5068;--offbg:#EFEAF4}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--ink);font:16px/1.5 "Nunito Sans",system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}}
main{{max-width:640px;margin:0 auto;padding:40px 16px 56px}}
.brand{{font:900 22px/1 Nunito,system-ui,sans-serif;color:var(--deep)}}.brand b{{color:#E83C7D}}
h1{{font:800 28px/1.2 Nunito,system-ui,sans-serif;color:var(--deep);margin:28px 0 6px}}
.sub{{color:var(--muted);margin:0 0 22px}}
.banner{{display:flex;align-items:center;gap:12px;padding:16px 18px;border-radius:16px;font-weight:700;margin-bottom:18px}}
.banner.ok{{background:var(--okbg);color:var(--ok)}}.banner.warn{{background:var(--warnbg);color:var(--warn)}}
.banner.bad{{background:var(--badbg);color:var(--bad)}}
.dot{{width:12px;height:12px;border-radius:50%;background:currentColor;flex:none}}
ul{{list-style:none;margin:0;padding:0;background:var(--card);border:1px solid var(--line);border-radius:16px}}
li{{display:grid;grid-template-columns:1fr auto;gap:2px 12px;padding:14px 18px;border-top:1px solid var(--line)}}
li:first-child{{border-top:0}}
.name{{font-weight:700}}.detail{{grid-column:1;color:var(--muted);font-size:14px}}
.pill{{grid-column:2;grid-row:1/span 2;align-self:center;padding:4px 12px;border-radius:999px;font-size:13px;font-weight:700}}
.pill.ok{{background:var(--okbg);color:var(--ok)}}.pill.warn{{background:var(--warnbg);color:var(--warn)}}
.pill.bad{{background:var(--badbg);color:var(--bad)}}.pill.off{{background:var(--offbg);color:var(--off)}}
footer{{margin-top:18px;color:var(--muted);font-size:13px}}
footer a{{color:var(--deep)}}
</style></head>
<body><main>
<div class="brand"><b>Your</b>Counselor</div>
<h1>Service status</h1>
<p class="sub">Checked {html.escape(when)}. This page refreshes every minute.</p>
<div class="banner {worst}" role="status"><span class="dot"></span>{headline}</div>
<ul>{items}</ul>
<footer>For scripts: <a href="?format=json">the same status as JSON</a>.</footer>
</main></body></html>"""
