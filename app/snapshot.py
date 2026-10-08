"""
Case Snapshot (CR-001): every Case Snapshot field THIS CASE needs is collected before a guided-
consultation report — a value, or a status the clinician chose — and the app, not the model,
writes the snapshot table into the report. The case is checked first: a few fields are asked for
every case ("always" in the field list); the extraction call names the other fields that would
change the plan for this case, and the rest are optional (not required, left out of the report
when empty, never listed as gaps).

  case text ─► extraction call (fills only what the text clearly states) ─► snapshot form
  (clinician completes every field) ─► at most 4 case-specific questions, never about a
  snapshot field ─► report: <case_snapshot> JSON + the case text; the table the model wrote
  under "Case Snapshot" is replaced with the app's table before the inspector runs.

The field list and the words live in shared/snapshot_fields.json and shared/ui_copy.json.
No web or database code: tests/test_snapshot.py.
"""
from __future__ import annotations

import json
import re
from functools import lru_cache
from pathlib import Path

from . import deid
from .pipeline import DeidRejected

SHARED = Path(__file__).resolve().parent.parent / "shared"
STATUSES = ("not_known", "not_yet_asked", "not_applicable", "skipped")
CHOSEN_STATUSES = ("not_known", "not_yet_asked", "not_applicable")   # "skipped" only via skip remaining
TEXT_MAX = 200
RISK_FIELD, RISK_PRESENT, RISK_ABSENT = "risk_screening", "Risk present", "Asked and absent"
RISK_MANAGED_NOTE = "immediate safety is being managed"   # set by the server after the safety step
MAX_CASE_QUESTIONS = 4


class SnapshotError(Exception):
    def __init__(self, status: int, detail: str):
        super().__init__(detail)
        self.status, self.detail = status, detail


@lru_cache(maxsize=1)
def definitions() -> tuple[dict, ...]:
    data = json.loads((SHARED / "snapshot_fields.json").read_text(encoding="utf-8"))
    out = []
    for f in data["fields"]:
        f = {"chips": [], "multi": False, "text": "none", "statuses": list(CHOSEN_STATUSES), "aliases": [],
             "helper": "", "always": False, **f}
        out.append(f)
    return tuple(out)


@lru_cache(maxsize=1)
def ui_copy() -> dict:
    data = json.loads((SHARED / "ui_copy.json").read_text(encoding="utf-8"))
    return {k: v for k, v in data.items() if not k.startswith("_")}


def by_key() -> dict[str, dict]:
    return {f["key"]: f for f in definitions()}


def keys() -> list[str]:
    return [f["key"] for f in definitions()]


@lru_cache(maxsize=1)
def _alias_map() -> dict[str, str]:
    m = {}
    for f in definitions():
        m[f["key"]] = f["key"]
        for a in f["aliases"]:
            m.setdefault(a, f["key"])
    return m


def covers(field: str) -> str | None:
    """The snapshot field a question key asks about (by key or alias), or None."""
    field = re.sub(r"[^a-z0-9_]+", "_", str(field or "").strip().lower()).strip("_")
    return _alias_map().get(field)


# --- entries ---------------------------------------------------------------------------
def empty() -> dict:
    return {k: {"chips": [], "text": "", "status": None, "prefilled": False} for k in keys()}


def mark_needed(snapshot: dict, relevant: list[str]) -> None:
    """After the case check: fields that are neither always asked, nor relevant to this case, nor
    already answered become optional."""
    relevant = set(relevant)
    for f in definitions():
        e = snapshot[f["key"]]
        if not f["always"] and f["key"] not in relevant and not resolved(e, f):
            e["optional"] = True


def _out(entry: dict | None, f: dict) -> bool:
    """An optional field nobody filled: not asked, not reported, not a gap."""
    return bool((entry or {}).get("optional")) and not resolved(entry, f)


def resolved(entry: dict | None, f: dict) -> bool:
    if not entry:
        return False
    if entry.get("status"):
        return True
    if f["text"] in ("required", "number"):
        return bool(entry.get("text"))
    return bool(entry.get("chips") or entry.get("text"))


def unresolved(snapshot: dict) -> list[str]:
    """Required fields still without a value or status (optional ones never count)."""
    return [f["key"] for f in definitions()
            if not resolved(snapshot.get(f["key"]), f) and not _out(snapshot.get(f["key"]), f)]


def display_value(entry: dict) -> str:
    chips, text = ", ".join(entry.get("chips") or []), (entry.get("text") or "").strip()
    return f"{chips} — {text}" if chips and text else chips or text


def _norm_text(f: dict, text: str) -> str:
    text = re.sub(r"\s+", " ", str(text or "")).strip()[:TEXT_MAX]
    if not text:
        return ""
    if f["text"] == "number":
        m = re.fullmatch(r"(\d{1,3})(?:\s*(?:years?|yrs?|y))?", text, re.I)
        if not m or not 0 < int(m.group(1)) <= 120:
            raise SnapshotError(422, f"{f['key']}: a number of years")
        return m.group(1)
    if f["text"] == "none":
        raise SnapshotError(422, f"{f['key']}: choose one of the options")
    check = deid.clean(text)
    if not check.is_clean:
        raise DeidRejected(check.counts)
    return text


def validate(key: str, raw: dict | None) -> dict:
    """One entry from the app: {chips, text, status}. Raises SnapshotError / DeidRejected."""
    f = by_key().get(key)
    if f is None:
        raise SnapshotError(422, f"unknown snapshot field '{key}'")
    raw = raw or {}
    status = raw.get("status") or None
    if status is not None:
        if status not in f["statuses"]:
            raise SnapshotError(422, f"{key}: status '{status}' is not offered for this field")
        return {"chips": [], "text": "", "status": status, "prefilled": False}
    chips = [str(c) for c in (raw.get("chips") or [])]
    if any(c not in f["chips"] for c in chips):
        raise SnapshotError(422, f"{key}: unknown option")
    chips = list(dict.fromkeys(chips))
    if not f["multi"] and len(chips) > 1:
        raise SnapshotError(422, f"{key}: choose one option")
    text = str(raw.get("text") or "").strip()
    if key == RISK_FIELD and chips == [RISK_PRESENT] and text == RISK_MANAGED_NOTE:
        # The app sends back the note the server set when the clinician confirmed safety.
        return {"chips": chips, "text": text, "status": None, "prefilled": False}
    return {"chips": chips, "text": _norm_text(f, text), "status": None, "prefilled": False}


def from_extraction(key: str, value: str) -> dict | None:
    """Turns one extracted value into an entry, or None when it does not fit the field."""
    f = by_key().get(key)
    value = re.sub(r"\s+", " ", str(value or "")).strip()
    if f is None or not value or value.lower() in ("unknown", "not known", "not stated", "none stated", "n/a"):
        return None
    lower = {c.lower(): c for c in f["chips"]}
    if key == RISK_FIELD:
        # Only an explicit "asked and absent" is prefilled; the clinician chooses anything else.
        return ({"chips": [RISK_ABSENT], "text": "", "status": None, "prefilled": True}
                if value.lower() == RISK_ABSENT.lower() else None)
    parts = [p.strip() for p in re.split(r"[;,]", value) if p.strip()] if f["multi"] else [value]
    chips = [lower[p.lower()] for p in parts if p.lower() in lower]
    rest = [p for p in parts if p.lower() not in lower]
    if not f["multi"] and not chips:
        head, _, tail = value.partition(" — ")
        if head.lower() in lower:
            chips, rest = [lower[head.lower()]], [tail] if tail else []
    text = ", ".join(rest)
    try:
        if f["text"] == "none" and text:
            if not chips:
                return None
            text = ""
        text = _norm_text(f, text) if text else ""
    except Exception:
        return None
    if not chips and not text:
        return None
    return {"chips": chips[:1] if not f["multi"] else chips, "text": text, "status": None, "prefilled": True}


# --- what the model and the phone see ----------------------------------------------------
def as_json(snapshot: dict) -> dict:
    """The snapshot for the report request: value, or {"status": …}."""
    out = {}
    for f in definitions():
        e = snapshot.get(f["key"]) or {}
        if _out(e, f):
            continue
        out[f["key"]] = {"status": e["status"]} if e.get("status") else (
            display_value(e) if resolved(e, f) else {"status": "skipped"})
    return out


def public(snapshot: dict) -> dict:
    fields = []
    for f in definitions():
        e = snapshot.get(f["key"]) or {}
        fields.append({**{k: f[k] for k in ("key", "group", "label", "question", "chips", "multi", "text",
                                             "statuses", "helper")},
                       "chips_selected": list(e.get("chips") or []), "value_text": e.get("text", ""),
                       "status": e.get("status"), "prefilled": bool(e.get("prefilled")),
                       "resolved": resolved(e, f), "optional": bool(e.get("optional"))})
    return {"fields": fields, "copy": ui_copy(), "ask_next": ask_next(snapshot)}


def ask_next(snapshot: dict) -> list[str]:
    """Not yet asked or skipped fields: the next session's checklist."""
    return [f["label"] for f in definitions()
            if not _out(snapshot.get(f["key"]), f)
            and ((snapshot.get(f["key"]) or {}).get("status") in ("not_yet_asked", "skipped")
                 or not resolved(snapshot.get(f["key"]), f))]


def _cell(s: str) -> str:
    return s.replace("|", "/").replace("\n", " ").strip()


def render_table(snapshot: dict) -> str:
    """Only what was answered for this case goes in the table. Not known, N/A and unasked fields are
    left out; not-yet-asked and skipped ones become one "Ask in the next session" line."""
    rows = ["| Field | Details |", "| --- | --- |"]
    for f in definitions():
        e = snapshot.get(f["key"]) or {}
        if e.get("status") or not resolved(e, f):
            continue
        shown = display_value(e) + (" years" if f["text"] == "number" else "")
        rows.append(f"| {_cell(f['label'])} | {_cell(shown)} |")
    block = "\n".join(rows) if len(rows) > 2 else ""
    gaps = ask_next(snapshot)
    if gaps:
        block += ("\n\n" if block else "") + f"**{ui_copy()['ask_next_heading']}:** " + ", ".join(gaps) + "."
    return block


_SNAP_HEAD = re.compile(r"^#{2,4}\s+Case Snapshot\s*$", re.M)
_NEXT_HEAD = re.compile(r"^#{2,4}\s", re.M)
_TABLE = re.compile(r"(?:^\|.*\|[ \t]*\n?)+", re.M)


def apply_table(text: str, snapshot: dict) -> str:
    """Puts the app's snapshot table in place of the one the model wrote under "Case Snapshot"
    (or at the start of that section). Everything else is left exactly as written, and the
    result still goes through the inspector."""
    head = _SNAP_HEAD.search(text)
    if not head:
        return text
    nxt = _NEXT_HEAD.search(text, head.end())
    end = nxt.start() if nxt else len(text)
    body = text[head.end():end]
    table = _TABLE.search(body)
    rendered = render_table(snapshot)
    if table:
        new_body = body[:table.start()] + rendered + "\n" + body[table.end():]
    else:
        new_body = "\n" + rendered + "\n" + body
    return text[:head.end()] + new_body + text[end:]


# --- extraction call ---------------------------------------------------------------------
def extraction_schema() -> dict:
    return {
        "type": "object", "additionalProperties": False,
        "properties": {
            "fields": {"type": "array", "items": {
                "type": "object", "additionalProperties": False,
                "properties": {"key": {"type": "string", "enum": keys()}, "value": {"type": "string"}},
                "required": ["key", "value"]}},
            "relevant": {"type": "array", "items": {"type": "string", "enum": keys()}},
            "case_type": {"type": "string"},
            "case_summary": {"type": "string"},
        },
        "required": ["fields", "relevant", "case_type", "case_summary"],
    }


EXTRACT_CONTRACT = """\
# APP CONTRACT — guided consultation, Case Snapshot extraction
You read a clinician's de-identified case description and pre-fill the app's Case Snapshot form. You never write a
report or ask questions here. Reply with JSON only, matching the response schema:
- fields: one {key, value} for each field below that the text clearly states. Never guess or infer; leave out
  anything the text does not state. One phrase can fill several fields ("4 weeks, started suddenly, no incident"
  fills duration, onset and precipitant).
- value: where a field has options, the matching option word for word (several, comma-separated, where the field
  allows several); otherwise the clinician's words in at most 40 words. age is a number only. Never include an
  identifier (names, places, employers, schools, contact details).
- relevant: the fields below (other than the ones marked "always asked") whose answer would change the plan for THIS
  case and that the text does not answer. The clinician is asked these; the rest are optional. Leave out fields that
  do not apply to this case (e.g. occupation or marital status for a young child, school for a retired adult).
- case_type: the kind of case in at most 8 words, a working label for planning, not a diagnosis; no codes.
- case_summary: the case in at most 120 words, facts only.
"""


@lru_cache(maxsize=1)
def extraction_system() -> str:
    lines = [EXTRACT_CONTRACT, "Fields:"]
    for f in definitions():
        opts = f" Options: {' / '.join(f['chips'])}." if f["chips"] else ""
        many = " Several allowed." if f["multi"] else ""
        always = " (always asked)" if f["always"] else ""
        lines.append(f"- {f['key']}{always}: {f['question']}.{opts}{many}")
    return "\n".join(lines)


REPORT_NOTE = """\
[App note] <case_snapshot> holds the Case Snapshot the clinician completed in the app; treat it as the clinician's
information. The app shows the snapshot table in the report and replaces the table under "Case Snapshot" with its
own, so do not describe the snapshot fields one by one; keep the risk-screening line. A field missing from
<case_snapshot> was not needed for this case: do not list it as a gap. Fields with status
not_yet_asked or skipped are gaps: list them as questions for the next session. Status not_known: the clinician
does not know; ask again only if the answer would change the plan. Status not_applicable: does not apply."""
