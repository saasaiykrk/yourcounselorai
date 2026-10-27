"""
The public /delete-account page: the web link Google Play asks for. It explains how to delete an account
in the app, what goes and what stays, and how to ask by email for anyone who can no longer open the app.
Static text only; it reads nothing and shows no account data.
"""
from __future__ import annotations

import html

CONTACT_EMAIL = "saas.ai.yk@gmail.com"   # the same address as kSafetyEmail in the app


def render(email: str = CONTACT_EMAIL) -> str:
    e = html.escape(email)
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Delete your account · YourCounselor</title>
<style>
:root{{--ink:#1E1030;--muted:#5A5068;--deep:#3F0079;--bg:#FAF7FD;--line:#E6DDF0;--card:#fff}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--ink);font:16px/1.55 "Nunito Sans",system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}}
main{{max-width:680px;margin:0 auto;padding:40px 16px 56px}}
.brand{{font:900 22px/1 Nunito,system-ui,sans-serif;color:var(--deep)}}.brand b{{color:#E83C7D}}
h1{{font:800 28px/1.2 Nunito,system-ui,sans-serif;color:var(--deep);margin:28px 0 8px}}
h2{{font:800 19px/1.3 Nunito,system-ui,sans-serif;color:var(--deep);margin:0 0 8px}}
section{{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:18px 20px;margin:16px 0}}
ol,ul{{margin:0;padding-left:22px}}li{{margin:4px 0}}
p{{margin:0 0 8px}}.muted{{color:var(--muted)}}
a{{color:var(--deep);font-weight:700}}
</style></head>
<body><main>
<div class="brand"><b>Your</b>Counselor</div>
<h1>Delete your account</h1>
<p class="muted">YourCounselor by Fabeminds Counselling Private Limited. This page explains how to delete your
account and what happens to your data.</p>

<section><h2>In the app</h2>
<ol>
<li>Open YourCounselor and sign in.</li>
<li>Go to <b>Account</b> → <b>Delete account</b>.</li>
<li>Read what will be deleted, type <b>DELETE</b> and tap <b>Delete my account</b>.</li>
</ol>
<p class="muted" style="margin-top:8px">Deletion happens straight away and can't be undone.</p>
</section>

<section><h2>Can't open the app?</h2>
<p>Email <a href="mailto:{e}?subject=Delete%20my%20YourCounselor%20account">{e}</a> from the email address
you sign in with, and ask us to delete your account.</p>
</section>

<section><h2>What is deleted</h2>
<ul>
<li>Your sign-in and email address.</li>
<li>Your name, mobile number, gender, age, registration number and verification level.</li>
<li>Your own AI key, if you added one.</li>
<li>Your booking page, working hours, time off and appointments, including your clients' names and emails.</li>
<li>Your consult history leaves your account.</li>
</ul>
</section>

<section><h2>What is kept, and for how long</h2>
<ul>
<li><b>Payment records</b> (plan, amount, date): kept for as long as tax law requires.</li>
<li><b>De-identified consult text</b> (identifiers were removed before it was sent) and safety-review records:
kept for the 12-month retention period for safety review (longer only while a safety report is open), then deleted. They no longer carry your name or email.</li>
</ul>
<p class="muted" style="margin-top:8px">Any running plan ends when the account is deleted. Admin accounts must
have admin access removed by another admin first.</p>
</section>
</main></body></html>"""
