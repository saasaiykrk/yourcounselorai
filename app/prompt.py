"""
Builds the system prompt from the pinned skill folder, and serves Core cards on
demand through the `get_card` tool.

Why not paste all six Core files into the prompt? They are ~115k tokens. The
operating files (SKILL.md, master prompt, audit, templates, QC, crisis,
referral, documentation, worked example) are ~35k tokens and are needed on
every turn, so they go in the cached system prompt. Core cards are fetched by
ID only when the model needs them — the same "read only the cards the request
needs" rule SKILL.md already gives.

The skill folder is the source of truth. Never edit prompt text here to change
clinical behaviour — edit the skill, bump its version, update CHANGELOG.md,
re-run evals, get clinician sign-off.
"""
from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

ALWAYS_LOADED = [
    "SKILL.md",
    "references/v21-master-prompt.md",
    "references/v21-contract.md",
    "references/case-history-mse-audit.md",
    "assets/mode-templates.md",
    "references/qc-checklist.md",
    "references/crisis-resources.md",
    "references/referral-criteria.md",
    "references/documentation.md",
    "references/example-mode-a-panic.md",
]
CORE_FILES = sorted(["references/core1-foundations-assessment-interventions.md",
                     "references/core2-counselling-skills-child-adolescent.md",
                     "references/core3-personality-treatment-planning.md",
                     "references/core4-couples-therapy.md",
                     "references/core5-cbt-toolkit-grounding-scales.md",
                     "references/core6-assessment-engine.md"])

CARD_ID = r"[A-Z]{2,6}(?:-[A-Z0-9]+)+"
_HEAD_RE = re.compile(rf"^(?P<hashes>#{{2,4}})\s+(?P<id>{CARD_ID})\b[:\s]*(?P<title>.*)$", re.M)
_BOLD_RE = re.compile(rf"^\*\*(?P<id>{CARD_ID})\s+(?P<title>[^*]+)\*\*.*$", re.M)
_PART_RE = re.compile(r"^##\s+PART\s+\d+\s+—\s+(?P<title>.*?)\((?P<id>[A-Z]{2,6})\)\s*$", re.M)
MAX_CARD_CHARS = 14000

APP_CONTRACT = """\
# APP CONTRACT — YourCounselor Android app
These rules adapt the skill below to the app. They override only the chat-specific mechanics of SKILL.md (question rounds, grep/view, tappable questions). Every clinical rule in the skill still applies in full.

1. **Contract line.** The very first line of EVERY reply is exactly:
   `<!--yc mode=<A|A2|B|C|D|E|F|G|Q> gate=<none|gate1|gate2> ceiling=<High|Moderate|Low|NA> level=<L1|L2|L3>-->`
   - mode A2 = "Mode A when Gate 2 triggers and a full plan was not explicitly requested" (mode-templates.md).
   - mode Q = one short clarifying question, only when the message contains no case details at all.
   - ceiling NA only for gate1 or mode Q. level = the clinician level in the app header.
2. **Level and mode come from the app header.** The clinician's level is verified by the app — never ask for the role and never change it. If the header says `Requested mode: auto`, choose the mode per Part B (default A). Do not run a question round; proceed with the defaults and state assumptions in 1f. If risk status is not stated, treat it as not yet asked.
3. **No shell.** Wherever SKILL.md says to grep or view a Core file, call `get_card` with the card ID from the index at the end of this prompt. Fetch only the cards the request needs.
4. **ICD-11 codes.** Call `icd11_lookup` to verify. Show a code only if the tool returned it in this turn; otherwise write "code to confirm at icd.who.int". Never quote criteria text.
5. **Headings.** Use `### N. Title` exactly as in mode-templates.md; with a Low ceiling write `### N. PROVISIONAL — Low confidence · Title`.
6. **De-identified input.** The message has been cleaned on the phone. Tags such as [NAME], [PHONE], [ORG] are redactions — never guess or reconstruct them, and never write any identifier.
7. **Numbers.** Never write a phone or helpline number that is not in crisis-resources.md.
8. **Pre-send inspection.** An automated inspector enforces qc-checklist.md before the clinician sees your reply. A failed reply is sent back to you once with the failures listed.
"""


@dataclass(frozen=True)
class Skill:
    root: Path
    version: str
    system_prompt: str
    prompt_hash: str
    card_index: dict  # id -> (file, title)


def _skill_version(skill_md: str) -> str:
    m = re.search(r"\|\s*\*\*(\d+\.\d+\.\d+)\*\*\s*\|", skill_md)
    return m.group(1) if m else "unknown"


def _build_card_index(root: Path) -> dict:
    idx: dict[str, tuple[str, str]] = {}
    for rel in CORE_FILES:
        text = (root / rel).read_text(encoding="utf-8")
        for rx in (_HEAD_RE, _BOLD_RE, _PART_RE):
            for m in rx.finditer(text):
                cid = m.group("id")
                idx.setdefault(cid, (rel, m.group("title").strip()[:90]))
    return idx


@lru_cache(maxsize=4)
def load_skill(root: str) -> Skill:
    r = Path(root)
    parts = [APP_CONTRACT]
    for rel in ALWAYS_LOADED:
        parts.append(f"\n\n<file path=\"{rel}\">\n{(r / rel).read_text(encoding='utf-8')}\n</file>")
    index = _build_card_index(r)
    lines = [f"- {cid} — {title} ({Path(f).stem.split('-')[0]})" for cid, (f, title) in index.items()]
    parts.append("\n\n# CORE CARD INDEX (fetch with get_card)\n" + "\n".join(lines))
    system = "".join(parts)
    version = _skill_version((r / "SKILL.md").read_text(encoding="utf-8"))
    return Skill(r, version, system, hashlib.sha256(system.encode()).hexdigest()[:16], index)


def get_card(skill: Skill, card_id: str) -> str:
    """Return the text of one Core card, or a short 'not found' message."""
    card_id = card_id.strip().upper()
    if not re.fullmatch(CARD_ID + r"|[A-Z]{2,6}", card_id):
        return f"Invalid card id '{card_id}'."
    for rel in CORE_FILES:
        text = (skill.root / rel).read_text(encoding="utf-8")
        # 1) heading card: from the heading to the next heading of the same or higher level
        for m in _HEAD_RE.finditer(text):
            if m.group("id") == card_id:
                level = len(m.group("hashes"))
                nxt = re.compile(rf"^#{{2,{level}}}\s", re.M).search(text, m.end())
                return _cap(rel, text[m.start(): nxt.start() if nxt else len(text)])
        # 2) bold-line card (Core 4 problem modules): to the next bold card or heading
        for m in _BOLD_RE.finditer(text):
            if m.group("id") == card_id:
                nxt = re.compile(rf"^(?:\*\*{CARD_ID}\s|#{{2,4}}\s)", re.M).search(text, m.end())
                return _cap(rel, text[m.start(): nxt.start() if nxt else len(text)])
        # 3) a whole PART by prefix, e.g. BRF, TXM, FID
        for m in _PART_RE.finditer(text):
            if m.group("id") == card_id:
                nxt = re.compile(r"^##\s", re.M).search(text, m.end())
                return _cap(rel, text[m.start(): nxt.start() if nxt else len(text)])
    # 4) table-row ids (e.g. GRD-01, SR-07): return matching rows with their table header
    hits = []
    for rel in CORE_FILES:
        lines = (skill.root / rel).read_text(encoding="utf-8").splitlines()
        for i, line in enumerate(lines):
            if re.search(rf"\b{re.escape(card_id)}\b", line) and line.lstrip().startswith("|"):
                j = i
                while j > 0 and lines[j - 1].lstrip().startswith("|"):
                    j -= 1
                hits.append(f"[{rel}]\n" + "\n".join(lines[j:j + 2] + [line]))
    if hits:
        return _cap("", "\n\n".join(hits[:6]))
    return f"No card '{card_id}' in the knowledge base. Do not invent one; answer from general clinical knowledge and say so."


def _cap(rel: str, s: str) -> str:
    s = s.strip()
    if len(s) > MAX_CARD_CHARS:
        s = s[:MAX_CARD_CHARS] + "\n…[card truncated — ask for a narrower card ID if more is needed]"
    return (f"[{rel}]\n" if rel else "") + s


def app_header(level: str, requested_mode: str, today: str) -> str:
    return (f"[App header] Clinician level: {level} (verified) · Requested mode: {requested_mode} · Date: {today}\n\n"
            f"[Clinician message]\n")


# --- Guided consultation (intake questions, then the fixed Consultation Report) ---------------
# App mechanics only. What to ask, when to stop and the report structure live in the skill:
# references/intake-questioning.md, assets/consult-report-template.md and the worked example.
INTAKE_FILE = "references/intake-questioning.md"
REPORT_FILES = ["assets/consult-report-template.md", "references/example-consult-report-ocd.md"]

INTAKE_CONTRACT = """\
# APP CONTRACT — guided consultation, intake step
You are the intake step of a guided consultation in the YourCounselor app. Follow the intake guide below; you never
write the report here. Each turn you receive the consultation state (JSON) and the clinician's latest message.
Reply with JSON only, matching the response schema:
- status: "ask" (one next question), "ready" (enough for the report) or "risk_stop".
- facts_patch: facts learned or changed in the latest message only, as {field, value}. field is a short snake_case
  key; use presenting_concern, age_gender, duration_onset and risk_screening where they fit, otherwise keys such as
  education_occupation, functioning, triggers, family, prior_therapy, medications, medical, help_requested.
  value is the clinician's information in at most 40 words. risk_screening is exactly "asked and absent",
  "risk present — {what was done}" or "not yet asked".
- unknown_fields: fields the clinician said they do not know or chose to skip.
- case_summary: the whole case so far in at most 120 words, facts only.
- question, why, field, options: the next question when status is "ask"; otherwise empty strings and [].
- brief_answer: a short reply when the clinician asked you something; otherwise "".
Never ask again about a field that is in facts or unknown. Never put an identifier in any field.
"""

CONSULT_REPORT_CONTRACT = """\
# APP CONTRACT — guided consultation report (Mode R)
When the app header says `Requested mode: R`, the message is a case summary collected by the app's guided intake.
Write the Consultation Report exactly as in consult-report-template.md below: contract line with mode=R, every
heading in the template's order with its title unchanged, built only from the facts given — mark gaps
"(not provided)" or "(unknown — clinician did not know)". For this request this replaces the mode choice in rule 2;
every other app contract rule above still applies.
"""

INTAKE_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "status": {"type": "string", "enum": ["ask", "ready", "risk_stop"]},
        "facts_patch": {"type": "array", "items": {
            "type": "object", "additionalProperties": False,
            "properties": {"field": {"type": "string"}, "value": {"type": "string"}},
            "required": ["field", "value"]}},
        "unknown_fields": {"type": "array", "items": {"type": "string"}},
        "case_summary": {"type": "string"},
        "question": {"type": "string"},
        "why": {"type": "string"},
        "field": {"type": "string"},
        "options": {"type": "array", "items": {"type": "string"}},
        "brief_answer": {"type": "string"},
    },
    "required": ["status", "facts_patch", "unknown_fields", "case_summary", "question", "why", "field", "options",
                 "brief_answer"],
}


@dataclass(frozen=True)
class ConsultPrompts:
    intake_system: str                 # small; sent on every question turn
    report_addendum: str               # sent after the cached skill prompt, for the report call only
    mandatory: tuple[dict, ...]        # [{field, question, why, options}] from the intake guide
    prompt_hash: str


_MANDATORY_ROW = re.compile(r"^\|\s*(?P<field>[a-z_]+)\s*\|\s*(?P<q>[^|]+?)\s*\|\s*(?P<why>[^|]+?)\s*\|\s*(?P<opts>[^|]*?)\s*\|\s*$",
                            re.M)


@lru_cache(maxsize=4)
def load_consult_prompts(root: str) -> ConsultPrompts:
    r = Path(root)
    guide = (r / INTAKE_FILE).read_text(encoding="utf-8")
    table = guide[guide.index("## Mandatory before the report"):]
    table = table[:table.index("\n## ", 5)]
    mandatory = tuple(
        {"field": m["field"], "question": m["q"], "why": m["why"],
         "options": [o.strip() for o in m["opts"].split(" / ") if o.strip()]}
        for m in _MANDATORY_ROW.finditer(table) if m["field"] != "field")
    if not mandatory:
        raise ValueError(f"{INTAKE_FILE}: no mandatory-field rows found")
    intake = f"{INTAKE_CONTRACT}\n\n<file path=\"{INTAKE_FILE}\">\n{guide}\n</file>"
    report = CONSULT_REPORT_CONTRACT + "".join(
        f"\n\n<file path=\"{rel}\">\n{(r / rel).read_text(encoding='utf-8')}\n</file>" for rel in REPORT_FILES)
    digest = hashlib.sha256((intake + report).encode()).hexdigest()[:16]
    return ConsultPrompts(intake, report, mandatory, digest)
