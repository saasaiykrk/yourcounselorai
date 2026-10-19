"""
Education module ("Knowledge" in the app): the owner's teaching pages (app/education_web/), free to read for
every signed-in user.

  GET /v1/education            → the cards: title, short description, section, and a signed link per page
  GET /learn/{slug}?t=…        → the page itself, as supplied, plus a small add-on (see below)
  GET /learn/file/{name}?t=…   → a supplied PDF (e.g. the Case History and MSE handout)

The pages are served exactly as supplied. At serving time an add-on is placed before </head> and
</body>; nothing in the original markup, text or styles is edited:
  * Printing and saving as PDF happen only through each module's own "Print or save as PDF" buttons
    (client handouts and counsellor sheets). There is no page-wide print button, and whole pages
    don't print (the modules block it themselves; the add-on blocks it on the reference pages).
  * Who may use those buttons: everyone while pricing is off; otherwise a running subscription
    (every module) or a single print bought for that module (24 hours by default); see PrintAccess
    and main._print_access. Unlocked inside the app, a button hands the app the handout exactly as
    the module would print it, and the app prints it. Locked inside the app, it asks the app to offer
    the purchase; in a browser the note appears under the button.
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
    "neuro-linguistic-programming": "others",
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
LOCKED_NOTE = ("Printing and saving as PDF come with a YourCounselor subscription, "
               "or buy this module in the app.")
# Whole pages are never printed: the modules block it themselves; this covers the reference pages.
ADDON_CSS = """
<style id="yc-edu-addon">
@media print{
  body *{display:none!important}
  body::after{content:"__NOTE__";display:block!important;
    padding:40px;font:18px/1.5 "Nunito Sans",system-ui,sans-serif;color:#3F0079}
}
</style>""".replace("__NOTE__", LOCKED_NOTE)

ADDON_JS = """
<script id="yc-edu-addon-js">
(function () {
  "use strict";
  var LINKS = __LINKS__;
  var CAN_PRINT = __PRINT__;
  var NOTE = __NOTE__;
  // 1. Links to other pages by file name -> the signed page link.
  function relink(root) {
    (root || document).querySelectorAll("a[href]").forEach(function (a) {
      var name = (a.getAttribute("href") || "").split("#")[0].split("/").pop();
      if (LINKS[name]) { a.setAttribute("href", LINKS[name]); a.removeAttribute("target"); }
    });
  }
  // 2. The modules' own "Print or save as PDF" buttons (client handouts, counsellor sheets) call
  //    YC_CONFIG.onHandoutDownload. Locked: inside the app it asks the app to offer the purchase,
  //    in a browser the note appears under the button. Unlocked inside the app: the app gets the
  //    handout exactly as the module would print it, and prints it (the in-app view can't open the
  //    module's print window). Unlocked in a browser: the module's own print window, as supplied.
  /*PRINT*/
  function handoutHtml(req) {
    var c = window.YC_CONFIG || {}, data = window.DATA || {}, s = data.sections || {}, H = window.YCHandout;
    var sheet = req.kind === "counsellor_sheet";
    var list = (sheet ? s.counsellor_sheets : s.client_handouts) || [];
    var hd = null;
    for (var i = 0; i < list.length; i++) if (list[i].id === req.handoutId) hd = list[i];
    if (!hd || !H || !c.brand) return null;
    var logo = c.brand.logo && (c.brand.logo.src2x || c.brand.logo.src), abs = logo ? new URL(logo, location.href).href : "";
    if (sheet) return H.buildSheetHtml({ sheet: hd, brand: c.brand, crisis: c.crisis, region: c.region, logoUrl: abs,
                                          diagrams: H.sheetDiagrams(data, hd) });
    var parts = H.diagramParts(data, hd);
    return H.buildHtml({ handout: hd, module: data, brand: c.brand, crisis: c.crisis, region: c.region,
                         practitioner: c.viewer && c.viewer.name, logoUrl: abs, diagramSvg: parts.diagramSvg,
                         diagramTitle: parts.diagramTitle, diagramCaption: parts.diagramCaption, diagramType: parts.diagramType });
  }
  /*END PRINT*/
  function hook(req) {
    var app = window.YCApp;
    if (!CAN_PRINT) {
      if (app && app.postMessage) { app.postMessage("yc:buy"); return; }
      return Promise.reject(new Error(NOTE));
    }
    var html = handoutHtml(req);
    if (!html) return Promise.reject(new Error("This handout could not be prepared. Please try again."));
    app.postMessage(html);
  }
  if (window.YC_CONFIG && (!CAN_PRINT || window.YCApp)) window.YC_CONFIG.onHandoutDownload = hook;
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", function () { relink(); });
  else relink();
  window.addEventListener("load", function () { relink(); });
  new MutationObserver(function () { relink(); }).observe(document.documentElement, { childList: true, subtree: true });
})();
</script>"""


def render(page: Page, src: str, links: dict[str, str], app_config: dict | None, can_print: bool = False) -> str:
    """The supplied page with the add-on placed before </head> and </body>.
    can_print: this viewer may print this module's handouts and sheets (see PrintAccess)."""
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
    out = out.replace("</head>", ADDON_CSS + "\n</head>", 1)
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
                      "region": svc.region,
                      # the handout buttons stay on; onHandoutDownload decides (print, or offer the purchase)
                      "subscriptionActive": True,
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
