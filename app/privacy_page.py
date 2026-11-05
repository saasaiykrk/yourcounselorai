"""
The public /privacy page: YourCounselor's privacy policy (app/privacy_policy.md), the URL given to Google Play
and to Google's OAuth verification. The policy is kept as Markdown in one place; this turns the small subset it
uses (headings, paragraphs, lists, tables, **bold**, `code`, links) into a page in the site's style. Static text
only; it reads nothing and shows no account data.
"""
from __future__ import annotations

import html
import pathlib
import re

POLICY = pathlib.Path(__file__).parent / "privacy_policy.md"


def _inline(text: str) -> str:
    """Escape, then **bold**, `code`, [label](https://…) and bare https:// links."""
    t = html.escape(text, quote=False)
    t = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", t)
    t = re.sub(r"`([^`]+)`", r"<code>\1</code>", t)
    t = re.sub(r"\[([^\]]+)\]\((https://[^)\s]+)\)", r'<a href="\2" rel="noopener">\1</a>', t)
    t = re.sub(r'(?<![">])(https://[^\s<)]+[^\s<).,;])', r'<a href="\1" rel="noopener">\1</a>', t)
    return t


def to_html(md: str) -> str:
    out: list[str] = []
    lines = md.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i].rstrip()
        if not line:
            i += 1
        elif line.startswith("# "):
            out.append(f"<h1>{_inline(line[2:])}</h1>")
            i += 1
        elif line.startswith("## "):
            out.append(f"<h2>{_inline(line[3:])}</h2>")
            i += 1
        elif line.startswith("- "):
            items = []
            while i < len(lines) and lines[i].startswith("- "):
                items.append(f"<li>{_inline(lines[i][2:].strip())}</li>")
                i += 1
            out.append("<ul>" + "".join(items) + "</ul>")
        elif line.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                cells = [c.strip() for c in lines[i].strip().strip("|").split("|")]
                if not all(re.fullmatch(r":?-{3,}:?", c) for c in cells):
                    rows.append(cells)
                i += 1
            head, body = rows[0], rows[1:]
            out.append('<div class="table"><table><thead><tr>' + "".join(f"<th>{_inline(c)}</th>" for c in head)
                       + "</tr></thead><tbody>" + "".join(
                           "<tr>" + "".join(f"<td>{_inline(c)}</td>" for c in r) + "</tr>" for r in body)
                       + "</tbody></table></div>")
        else:
            para = []
            while i < len(lines) and lines[i].strip() and not lines[i].startswith(("#", "- ", "|")):
                para.append(lines[i].strip())
                i += 1
            out.append(f"<p>{_inline(' '.join(para))}</p>")
    return "\n".join(out)


def render() -> str:
    body = to_html(POLICY.read_text(encoding="utf-8"))
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Privacy Policy · YourCounselor</title>
<meta name="description" content="How YourCounselor collects, uses and protects personal data, including Google user data.">
<style>
:root{{--ink:#1E1030;--muted:#5A5068;--deep:#3F0079;--bg:#FAF7FD;--line:#E6DDF0;--card:#fff}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--ink);font:16px/1.6 "Nunito Sans",system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}}
main{{max-width:760px;margin:0 auto;padding:40px 16px 56px}}
.brand{{font:900 22px/1 Nunito,system-ui,sans-serif;color:var(--deep)}}.brand b{{color:#E83C7D}}
h1{{font:800 30px/1.2 Nunito,system-ui,sans-serif;color:var(--deep);margin:28px 0 8px}}
h2{{font:800 20px/1.3 Nunito,system-ui,sans-serif;color:var(--deep);margin:28px 0 8px}}
p{{margin:0 0 10px}}ul{{margin:0 0 12px;padding-left:22px}}li{{margin:5px 0}}
a{{color:var(--deep);font-weight:700;overflow-wrap:anywhere}}
code{{background:#F1E7FB;border-radius:6px;padding:1px 6px;font-size:.92em}}
.table{{overflow-x:auto;margin:8px 0 14px}}
table{{border-collapse:collapse;width:100%;background:var(--card);font-size:15px}}
th,td{{border:1px solid var(--line);padding:8px 10px;text-align:left;vertical-align:top}}
th{{background:#F1E7FB;color:var(--deep)}}
</style></head>
<body><main>
<div class="brand"><b>Your</b>Counselor</div>
{body}
</main></body></html>"""
