"""
Education module: the owner's teaching pages (app/education_web/), free to read for every signed-in user.
Printing and saving as PDF: free while pricing is off; otherwise with a running subscription (every
page) or a single print bought for one page (24 hours by default). The button shows for everyone;
locked, it offers the single print in the app (see PrintAccess and main._print_access).

  GET /v1/education            → the cards: title, short description, kind, and a signed link per page
  GET /learn/{slug}?t=…        → the page itself, as supplied, plus a small add-on (see below)
  GET /learn/file/{name}?t=…   → a supplied PDF (e.g. the Case History and MSE handout)

The pages are served exactly as supplied. At serving time an add-on is placed before </head> and
</body>; nothing in the original markup, text or styles is edited:
  * a "Print / Save as PDF" button on every page. Unlocked, inside the app it hands the app the page
    as it looks now, which the app prints through the phone's print / save-as-PDF dialog; with
    unlocked printing comes the
  * print layout: every section expanded, menus and buttons hidden, A4 margins, no breaks inside
    boxes, rows or figures. The reader modules ship a print block ("Printing is disabled") and a
    beforeprint handler that hides the page; the add-on removes that one print rule from the
    stylesheet and undoes the handler, so the page prints. Copy protection and the viewer
    watermark stay on;
  * locked: the button asks the app to offer the single print (in a browser it shows a note), and
    printing stays blocked (the browser's own Print shows the note); the modules get
    subscriptionActive false, which locks their handout downloads, since those would otherwise
    open a print window;
  * reader modules get the live config the README asks for (viewer name and email for the
    watermark, the published module list, navigation between modules), merged into the
    supplied sample config, so brand, crisis and legal text stay exactly as supplied;
  * links to other pages by file name (the Therapy Comparison Chart's "Open" links) go to the
    signed page link.

Links are signed with an HMAC (user id + expiry, LINK_HOURS), because the page opens in the
phone's browser, which cannot send the app's sign-in token.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import html as htmllib
import json
import pathlib
import re
import time
from dataclasses import dataclass, field

try:  # the catalog, renderer and signer are stdlib-only; the routes need FastAPI
    from fastapi import Depends, FastAPI, HTTPException, Request
    from fastapi.responses import FileResponse, HTMLResponse
except ImportError:  # stdlib-only test run
    pass

WEB = pathlib.Path(__file__).parent / "education_web"
LINK_HOURS = 12
# Card order: the starting points first, then the reference pages, then the modules (A–Z).
FIRST = ["YourCounselor_Foundations_for_Counsellors_and_Psychologists.html",
         "YourCounselor_The_Core_Eight_Practical_Guide.html",
         "YourCounselor_Therapy_Comparison_Chart.html",
         "YourCounselor_Adult_Psychotherapy_Protocol_Matrix_and_Glossary.html"]
# The Knowledge tab's sections, in tab order (the app adds "All" in front). A page's section comes from
# SECTION_OF by its slug; a page not listed goes to "others", and a PDF to "handouts". Moving a page
# between sections is a change here only; the app shows whatever the server says.
SECTIONS = ("basics", "therapies", "practice", "others", "handouts")
SECTION_OF = {
    "foundations": "basics",
    "the-core-eight-practical-guide": "basics",
    "acceptance-commitment-therapy": "therapies",
    "behavioural-activation": "therapies",
    "cbt": "therapies",
    "dbt": "therapies",
    "exposure-therapy": "therapies",
    "motivational-interviewing": "therapies",
    "neuro-linguistic-programming": "therapies",
    "person-centred-therapy": "therapies",
    "solution-focused-brief-therapy": "therapies",
    "therapy-comparison-chart": "practice",
    "adult-psychotherapy-protocol-matrix-and-glossary": "practice",
    "case-history-and-mse-practice-handout": "handouts",
}
BRAND_RE = re.compile(r"^\s*YourCounselor\s*\|\s*|\s*\|\s*YourCounselor\s*$")


@dataclass(frozen=True)
class Page:
    slug: str
    file: str
    title: str
    summary: str
    kind: str                 # module · reference · handout
    reader: bool              # a YCReader module (takes YC_CONFIG)

    @property
    def section(self) -> str:
        return SECTION_OF.get(self.slug, "handouts" if self.kind == "handout" else "others")


def _slugify(name: str) -> str:
    stem = re.sub(r"^YourCounselor_", "", pathlib.Path(name).stem)
    return re.sub(r"[^a-z0-9]+", "-", stem.lower()).strip("-")


def _text(s: str) -> str:
    return re.sub(r"\s+", " ", htmllib.unescape(re.sub(r"<[^>]+>", " ", s))).strip()


def load_catalog(folder: pathlib.Path = WEB) -> list[Page]:
    """Every .html page (and .pdf handout) in the folder, read once at start-up."""
    pages: list[Page] = []
    files = sorted(p.name for p in folder.glob("*.html"))
    ordered = [f for f in FIRST if f in files] + [f for f in files if f not in FIRST]
    for name in ordered:
        src = (folder / name).read_text(encoding="utf-8")
        m = re.search(r"<title>(.*?)</title>", src, re.S)
        title = BRAND_RE.sub("", _text(m.group(1))) if m else _slugify(name).replace("-", " ").title()
        data = re.search(r'var DATA = \{"slug": "([^"]+)", "title": "[^"]*", "summary": "((?:[^"\\]|\\.)*)"', src)
        if data:
            slug, summary, reader = data.group(1), json.loads('"' + data.group(2) + '"'), True
        else:
            meta = re.search(r'<meta\s+name="description"\s+content="([^"]*)"', src)
            slug, summary, reader = _slugify(name), _text(meta.group(1)) if meta else "", False
        pages.append(Page(slug, name, title, summary, "module" if reader else "reference", reader))
    for pdf in sorted(folder.glob("*.pdf")):
        title = re.sub(r"\bMSE\b", "MSE", _slugify(pdf.name).replace("-", " ").capitalize())
        title = title.replace("Case history and mse", "Case History and MSE").replace("practice handout", "Practice Handout")
        pages.append(Page(_slugify(pdf.name), pdf.name, title, "Printable practice handout (PDF).", "handout", False))
    return pages


# --- signed links -----------------------------------------------------------------------------------
class Signer:
    def __init__(self, secret: bytes, hours: int = LINK_HOURS, clock=time.time):
        self.key = hashlib.sha256(b"yourcounselor-education-link:" + secret).digest()
        self.hours, self.clock = hours, clock

    def token(self, user_id: str) -> str:
        exp = int(self.clock()) + self.hours * 3600
        body = f"{user_id}.{exp}"
        sig = hmac.new(self.key, body.encode(), hashlib.sha256).digest()[:18]
        return base64.urlsafe_b64encode(body.encode()).decode().rstrip("=") + "." + \
            base64.urlsafe_b64encode(sig).decode().rstrip("=")

    def user(self, token: str) -> str | None:
        try:
            b64, s64 = token.split(".", 1)
            body = base64.urlsafe_b64decode(b64 + "=" * (-len(b64) % 4)).decode()
            sig = base64.urlsafe_b64decode(s64 + "=" * (-len(s64) % 4))
            user_id, exp = body.rsplit(".", 1)
        except (ValueError, UnicodeDecodeError):
            return None
        good = hmac.new(self.key, body.encode(), hashlib.sha256).digest()[:18]
        if not hmac.compare_digest(sig, good) or int(exp) < self.clock():
            return None
        return user_id


# --- the add-on ---------------------------------------------------------------------------------------
ADDON_CSS = """
<style id="yc-edu-addon">
.yc-edu-print{position:fixed;left:16px;bottom:16px;z-index:2147483000;display:inline-flex;align-items:center;gap:8px;
  padding:11px 16px;border:0;border-radius:999px;background:#6A11BA;color:#fff;font:700 14px/1 "Nunito Sans",system-ui,
  -apple-system,"Segoe UI",Roboto,sans-serif;box-shadow:0 4px 14px rgba(63,0,121,.28);cursor:pointer;min-height:44px}
.yc-edu-print:hover{background:#3F0079}.yc-edu-print:focus-visible{outline:3px solid #E83C7D;outline-offset:2px}
.yc-edu-print svg{width:18px;height:18px;fill:currentColor;flex:none}
@media (max-width:600px){.yc-edu-print{left:12px;bottom:12px;padding:10px 14px;font-size:13px}.yc-edu-print .long{display:none}}
@media (min-width:601px){.yc-edu-print .short{display:none}}
@page{size:A4;margin:14mm 13mm 16mm}
@media print{
  html,body{background:#fff!important;-webkit-print-color-adjust:exact;print-color-adjust:exact}
  .yc-edu-print,.yc-home-fab,.home-fab,.yc-skip,.yc-sidebar,.yc-topbar,.yc-sticky,.yc-toolbar,.yc-mobile-toc,.yc-jump,
  .yc-filter-status,.yc-seg,.site-header,.toc,.contents,.toolbar,.site-footer-nav{display:none!important}
  .yc-app{display:block!important}.yc-main,.yc-content{max-width:none!important;margin:0!important;padding:0!important}
  .yc-sidebar+*{margin:0!important}
  details>summary{list-style:none}details>summary::-webkit-details-marker{display:none}
  summary::after,details.section>summary::after{content:none!important;display:none!important}
  h1,h2,h3,h4,summary{break-after:avoid;page-break-after:avoid}
  .box,figure,.dg-slot,svg,tr,img,.card,blockquote{break-inside:avoid;page-break-inside:avoid}
  table{break-inside:auto;min-width:0!important;width:100%!important;table-layout:auto!important}
  thead{display:table-header-group}th,td{overflow-wrap:break-word;min-width:0!important}
  p,li{orphans:3;widows:3}
  .table-wrap,.table-scroll{overflow:visible!important}
  a[href^="http"]::after{content:""}
}
</style>"""
LOCKED_NOTE = "Printing and saving as PDF come with a YourCounselor subscription, or buy this page in the app."
# Not unlocked: printing stays blocked on every page (the modules block it already; this covers the rest).
NO_PRINT_CSS = """@media print{
  body *{display:none!important}
  body::after{content:"__NOTE__";display:block!important;
    padding:40px;font:18px/1.5 "Nunito Sans",system-ui,sans-serif;color:#3F0079}
}
.yc-edu-note{position:fixed;left:16px;right:16px;bottom:72px;z-index:2147483000;max-width:420px;padding:12px 14px;
  border-radius:12px;background:#1E1030;color:#fff;font:600 14px/1.4 "Nunito Sans",system-ui,sans-serif}
""".replace("__NOTE__", LOCKED_NOTE)

ADDON_JS = """
<script id="yc-edu-addon-js">
(function () {
  "use strict";
  var LINKS = __LINKS__;
  var CAN_PRINT = __PRINT__;
  // 1. Printing on: drop only the "Printing is disabled" print rule, and undo the hide-on-print handler.
  function allowPrint() {
    for (var i = 0; i < document.styleSheets.length; i++) {
      var sheet = document.styleSheets[i], rules;
      try { rules = sheet.cssRules; } catch (e) { continue; }          // cross-origin (fonts): skip
      for (var j = rules.length - 1; j >= 0; j--) {
        var r = rules[j];
        if (r.media && /print/.test(r.media.mediaText) && /Printing is disabled/.test(r.cssText)) sheet.deleteRule(j);
      }
    }
  }
  var reopen = [];
  function expandAll() {
    reopen = [];
    document.querySelectorAll("details:not([open])").forEach(function (d) { d.open = true; reopen.push(d); });
  }
  if (CAN_PRINT) {
    window.addEventListener("beforeprint", function () { document.body.style.visibility = ""; expandAll(); });
    window.addEventListener("afterprint", function () { reopen.forEach(function (d) { d.open = false; }); reopen = []; });
  }
  // 2. Links to other pages by file name → the signed page link.
  function relink(root) {
    (root || document).querySelectorAll("a[href]").forEach(function (a) {
      var name = (a.getAttribute("href") || "").split("#")[0].split("/").pop();
      if (LINKS[name]) { a.setAttribute("href", LINKS[name]); a.removeAttribute("target"); }
    });
  }
  // 3. The button. Unlocked, it prints; otherwise inside the app it offers the purchase (the app asks the
  //    server again afterwards), and in a browser it explains.
  function locked() {
    var app = window.YCApp;
    if (app && app.postMessage) { app.postMessage("yc:buy"); return; }
    var n = document.querySelector(".yc-edu-note");
    if (!n) {
      n = document.createElement("div"); n.className = "yc-edu-note"; n.setAttribute("role", "status");
      n.textContent = __NOTE__; document.body.appendChild(n);
    }
    clearTimeout(n._t); n.hidden = false; n._t = setTimeout(function () { n.hidden = true; }, 6000);
  }
  /*PRINT*/
  // Inside the YourCounselor app the page's print call does nothing. The app gets the page as it looks now
  // (every section open, the print block removed, no scripts) and prints that.
  function snapshot() {
    var clone = document.documentElement.cloneNode(true);
    var live = document.querySelectorAll("style"), copy = clone.querySelectorAll("style");
    for (var i = 0; i < live.length && i < copy.length; i++) {
      try {
        var rules = live[i].sheet && live[i].sheet.cssRules;
        if (rules) copy[i].textContent = Array.prototype.map.call(rules, function (r) { return r.cssText; }).join("\\n");
      } catch (e) {}
    }
    clone.querySelectorAll("script,noscript,.yc-edu-print").forEach(function (n) { n.remove(); });
    return "<!doctype html>\\n" + clone.outerHTML;
  }
  /*END PRINT*/
  function button() {
    if (document.querySelector(".yc-edu-print")) return;
    var b = document.createElement("button");
    b.type = "button"; b.className = "yc-edu-print";
    b.setAttribute("aria-label", "Print or save this page as a PDF");
    b.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M19 8H5c-1.66 0-3 1.34-3 3v6h4v4h12v-4h4v-6c0-1.66-1.34-3-3-3zm-3 11H8v-5h8v5zm3-7c-.55 0-1-.45-1-1s.45-1 1-1 1 .45 1 1-.45 1-1 1zm-1-9H6v4h12V3z"/></svg>' +
      '<span class="long">Print / Save as PDF</span><span class="short">Print / PDF</span>';
    b.addEventListener("click", function () {
      if (!CAN_PRINT) { locked(); return; }
      allowPrint(); document.body.style.visibility = ""; expandAll();
      var app = window.YCApp;
      if (app && app.postMessage) app.postMessage(snapshot()); else window.print();
    });
    document.body.appendChild(b);
  }
  function ready() { relink(); button(); if (CAN_PRINT) allowPrint(); }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", ready); else ready();
  window.addEventListener("load", function () { relink(); if (CAN_PRINT) allowPrint(); });
  new MutationObserver(function () { relink(); }).observe(document.documentElement, { childList: true, subtree: true });
})();
</script>"""


def render(page: Page, src: str, links: dict[str, str], app_config: dict | None, can_print: bool = False) -> str:
    """The supplied page with the add-on placed before </head> and </body>.
    can_print: this viewer may print this page (see PrintAccess)."""
    out = src
    if page.reader and app_config is not None:
        # The supplied sample config stays; the live values are merged in just before mount.
        cfg = "<script>window.__YC_APP__ = " + _js(app_config) + ";</script>"
        out = out.replace("</head>", cfg + "\n</head>", 1)
        i = out.rfind("YCReader.mount(")
        if i < 0:
            raise ValueError(f"{page.file}: YCReader.mount not found")
        nav = ("Object.assign(window.YC_CONFIG, window.__YC_APP__, { onNavigate: function (slug) {"
               " var u = (window.__YC_APP__.links || {})[slug]; if (u) location.href = u; } });\n")
        out = out[:i] + nav + out[i:]
    css = ADDON_CSS if can_print else ADDON_CSS.replace("</style>", NO_PRINT_CSS + "</style>")
    out = out.replace("</head>", css + "\n</head>", 1)
    j = out.rfind("</body>")
    addon = (ADDON_JS.replace("__LINKS__", _js(links)).replace("__PRINT__", "true" if can_print else "false")
             .replace("__NOTE__", _js(LOCKED_NOTE)))
    if not can_print:
        addon = re.sub(r"/\*PRINT\*/.*?/\*END PRINT\*/", "", addon, flags=re.S)
    return out[:j] + addon + "\n" + out[j:] if j >= 0 else out + addon


def _js(value) -> str:
    """JSON safe inside a <script> element."""
    return json.dumps(value).replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")


# --- endpoints ----------------------------------------------------------------------------------------
PAGE_HEADERS = {
    "Cache-Control": "private, no-store",
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff",
    "X-Robots-Tag": "noindex, nofollow",
    # The supplied pages use inline scripts and styles, Google Fonts and data: images; nothing else.
    "Content-Security-Policy": ("default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline' "
                                "https://fonts.googleapis.com; font-src https://fonts.gstatic.com data:; "
                                "img-src 'self' data: blob:; connect-src 'none'; base-uri 'none'; form-action 'none'; "
                                "frame-ancestors 'none'"),
}


@dataclass(frozen=True)
class PrintAccess:
    """Who may print which page. everything: pricing is off, or a running subscription. pages: single
    prints still running, {slug: ends at}. offer: a single print for sale ({price, currency, hours}), or None."""
    everything: bool = False
    pages: dict = field(default_factory=dict)
    offer: dict | None = None

    def allows(self, slug: str) -> bool:
        return self.everything or slug in self.pages


class EducationService:
    def __init__(self, signer: Signer, viewer_lookup, catalog: list[Page] | None = None, region: str = "IN",
                 access=None):
        """access(user_id) → PrintAccess (main.py: pricing, subscriptions and single prints)."""
        self.signer, self.viewer_lookup, self.region, self.access = signer, viewer_lookup, region, access
        self.catalog = catalog if catalog is not None else load_catalog()
        self.by_slug = {p.slug: p for p in self.catalog}
        self._src: dict[str, str] = {}

    def source(self, page: Page) -> str:
        if page.file not in self._src:
            self._src[page.file] = (WEB / page.file).read_text(encoding="utf-8")
        return self._src[page.file]

    def print_access(self, user_id: str) -> PrintAccess:
        """Fails closed: no lookup, or any error, means no printing (and nothing on offer)."""
        if self.access is None:
            return PrintAccess()
        try:
            a = self.access(user_id)
            return a if isinstance(a, PrintAccess) else PrintAccess()
        except Exception:
            return PrintAccess()

    def url(self, base: str, page: Page, token: str) -> str:
        path = f"/learn/file/{page.file}" if page.kind == "handout" else f"/learn/{page.slug}"
        return f"{base}{path}?t={token}"


def install(app: FastAPI, svc: EducationService, current_user, base_url) -> None:

    def signed(t: str) -> str:
        user = svc.signer.user(t or "")
        if user is None:
            raise HTTPException(403, "expired")
        return user

    @app.get("/v1/education")
    def education_list(request: Request, user: dict = Depends(current_user)):
        token, base = svc.signer.token(user["id"]), base_url(request)
        access = svc.print_access(user["id"])
        until = lambda p: access.pages[p.slug].isoformat() if p.slug in access.pages else None  # noqa: E731
        return {"pages": [{"slug": p.slug, "title": p.title, "summary": p.summary, "kind": p.kind, "section": p.section,
                           "url": svc.url(base, p, token), "can_print": access.allows(p.slug),
                           "print_until": None if access.everything else until(p)} for p in svc.catalog],
                "link_hours": svc.signer.hours, "can_print": access.everything,
                "print_offer": None if access.everything else access.offer}

    @app.get("/learn/file/{name}")
    def education_file(name: str, t: str = ""):
        page = next((p for p in svc.catalog if p.kind == "handout" and p.file == name), None)
        if page is None:
            raise HTTPException(404, "not found")
        try:
            signed(t)
        except HTTPException:
            return _expired()
        return FileResponse(WEB / page.file, media_type="application/pdf",
                            headers={**{k: v for k, v in PAGE_HEADERS.items() if k != "Content-Security-Policy"},
                                     "Content-Disposition": f'inline; filename="{page.file}"'})

    @app.get("/learn/{slug}", response_class=HTMLResponse)
    def education_page(slug: str, request: Request, t: str = ""):
        page = svc.by_slug.get(slug)
        if page is None or page.kind == "handout":
            raise HTTPException(404, "not found")
        try:
            user_id = signed(t)
        except HTTPException:
            return _expired()
        base = base_url(request)
        links = {p.file: svc.url(base, p, t) for p in svc.catalog}
        config, can_print = None, svc.print_access(user_id).allows(page.slug)
        if page.reader:
            viewer = svc.viewer_lookup(user_id) or {}
            readers = [p for p in svc.catalog if p.reader]
            config = {"viewer": {"name": viewer.get("name") or "", "email": viewer.get("email") or ""},
                      "region": svc.region, "subscriptionActive": can_print,
                      "modules": [{"slug": p.slug, "title": p.title} for p in readers],
                      "links": {p.slug: svc.url(base, p, t) for p in readers}}
        return HTMLResponse(render(page, svc.source(page), links, config, can_print), headers=PAGE_HEADERS)


def _expired() -> HTMLResponse:
    body = ("<!doctype html><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"
            "<title>Link expired · YourCounselor</title><body style=\"font:16px/1.5 system-ui,sans-serif;max-width:520px;"
            "margin:15vh auto;padding:0 20px;color:#1E1030\"><h1 style='color:#3F0079'>This link has expired</h1>"
            "<p>For your security, education links work for a few hours. Open the page again from "
            "<b>Education</b> in the YourCounselor app.</p></body>")
    return HTMLResponse(body, status_code=403, headers={"Cache-Control": "no-store", "Referrer-Policy": "no-referrer"})
