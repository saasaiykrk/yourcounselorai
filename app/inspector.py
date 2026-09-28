"""
The "inspector": deterministic checks run on every model reply BEFORE the
clinician sees it. Its rulebook is skill/clinical-assist/references/qc-checklist.md
(v2.1 Part G). Each check below cites the checklist item it enforces.

Design rules
  * Deterministic only (regex/structure). No second LLM in week 1. A check that
    can't be done deterministically stays in the clinician-graded eval suite.
  * BLOCK = reply is not shown; the pipeline regenerates once with the failure
    list, then falls back to a safe message. WARN = shown, logged for review.
  * Loosening any BLOCK rule requires clinician sign-off and a CHANGELOG entry
    (see CLAUDE.md). Tightening is always allowed.

The model is told (app/prompt.py, "App contract") to start every reply with a
machine-readable line, e.g.
    <!--yc mode=A gate=none ceiling=Low level=L2-->
which the inspector verifies and the app strips before display.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

from .deid import find_identifiers

DISCLAIMER = (
    "This tool is for professional use only. It does not diagnose or replace therapy. "
    "AI-generated information is intended to support, not replace, the judgment of a "
    "qualified mental-health professional. For emergencies or acute safety concerns, "
    "contact appropriate licensed professionals or emergency services."
)
PRESCRIBER_LINE = "Medication review may warrant discussion with the client's appropriately qualified prescriber."

# From references/crisis-resources.md — the ONLY numbers allowed in output.
ALLOWED_CRISIS_NUMBERS = {"112", "14416", "18008914416", "1098", "181"}
RETIRED_CRISIS_MARKERS = ["KIRAN", "1800-599-0019", "18005990019", "CHILDLINE"]

META_RE = re.compile(r"^\s*<!--\s*yc\s+(?P<body>[^>]*?)\s*-->\s*\n?", re.I)
VALID_MODES = {"A", "A2", "B", "C", "D", "E", "F", "G", "Q"}
VALID_GATES = {"none", "gate1", "gate2"}
VALID_CEILINGS = {"High", "Moderate", "Low", "NA"}

HEADING_RE = re.compile(r"^#{2,4}\s+(?P<title>.+?)\s*$", re.M)
SECTION_NUM_RE = re.compile(r"^(?:.*?·\s*)?(?P<n>\d{1,2})\.\s")

ICD_CODE_RE = re.compile(
    r"\b(?:[1-9A-HJ-NP-Z][A-HJ-NP-Z]\d[0-9A-HJ-NP-Z](?:\.[0-9A-HJ-NP-Z]{1,2})?"   # ICD-11 MMS
    r"|F\d{2}(?:\.[0-9x]{1,2})?)\b"                                               # ICD-10 / DSM F-codes
)

DRUG_TERMS = (
    r"ssris?|snris?|tcas?|maois?|benzodiazepines?|antidepressants?|antipsychotics?|anxiolytics?|"
    r"mood[\s-]stabili[sz]ers?|beta[\s-]blockers?|stimulants?|hypnotics?|sedatives?|"
    r"sertraline|fluoxetine|escitalopram|citalopram|paroxetine|fluvoxamine|venlafaxine|desvenlafaxine|"
    r"duloxetine|mirtazapine|bupropion|amitriptyline|imipramine|clomipramine|trazodone|vortioxetine|"
    r"clonazepam|alprazolam|lorazepam|diazepam|chlordiazepoxide|etizolam|zolpidem|propranolol|"
    r"lithium|valproate|divalproex|lamotrigine|carbamazepine|quetiapine|olanzapine|risperidone|"
    r"aripiprazole|haloperidol|clozapine|methylphenidate|atomoxetine|naltrexone|disulfiram|"
    r"acamprosate|buspirone|pregabalin|gabapentin|hydroxyzine"
)
MED_REC_RE = re.compile(
    rf"\b(?:start|starting|begin|initiate|prescribe|prescribing|increase|decrease|taper|stop|switch(?:ing)?\s+to|"
    rf"add|adding|recommend(?:ed)?|consider(?:ing)?|trial\s+of|take|taking)\b[^.\n]{{0,60}}\b(?:{DRUG_TERMS})\b",
    re.I,
)

# Hard backstop: if the clinician's message matches, the reply must be a Gate 1
# output unless the message also says immediate safety is being managed.
# Deliberately phrase-level; every miss found in evals/beta becomes a vignette
# plus a pattern here (tests/test_vignettes.py).
RISK_INPUT_RE = re.compile(
    # suicide / self-harm intent, plan, means
    r"end (?:it|my life|her life|his life)|kill (?:my|him|her|them)sel(?:f|ves)|\bsuicid|want(?:s|ed)? to die|"
    r"\boverdos|hang(?:ing)? (?:my|him|her)self|\bcut(?:ting|s)? (?:on |her |his )?(?:wrist|arm|thigh)|"
    r"pills at home|\bplan to (?:kill|die)|decided to (?:die|end)|"
    r"\b(?:rat |insect |weed )?poison\b|pesticide|kept (?:pills|tablets|a rope|rope)|"
    # harm to others / psychosis with danger
    r"threaten(?:ed|s)? to kill|\bweapon|\bknife|hears? (?:a )?voices? (?:telling|saying|ordering)|"
    r"must be (?:stopped|killed|punished)|"
    # partner violence with fear / coercion
    r"strangl|chok(?:ed|ing) (?:her|him|me)|press(?:ed|es|ing) (?:her|his|my) neck|"
    r"scared of (?:him|her|husband|wife|partner)|afraid of (?:him|her|husband|wife|partner)|"
    # abuse of a child or vulnerable adult
    r"sexual(?:ly)? abus|being abused|molest|touch(?:es|ed|ing) (?:her|his|my) private|"
    # medical instability / withdrawal
    r"sees? insects|seeing insects|fainted (?:twice|thrice|again|repeatedly|this week|\d+ times)|"
    r"\bdelirium|withdrawal fits?|stopped (?:drinking|alcohol) suddenly|"
    # perinatal
    r"baby (?:was |has been )?swapped|baby is not (?:hers|mine|his)|harm (?:the|her|my) baby",
    re.I,
)
SAFETY_MANAGED_RE = re.compile(
    r"safety (?:plan )?(?:is )?(?:in place|managed|confirmed|addressed)|risk (?:is )?(?:managed|addressed)|"
    r"(?:made|wrote|written|completed|did|have|has) (?:a )?(?:written )?safety plan|"
    r"(?:is|was|has been|got) (?:admitted|hospitali[sz]ed)|emergency (?:team|services) (?:involved|contacted)|"
    r"(?:is|are) safe now",
    re.I,
)
# Softer: safeguarding concerns that need to be ADDRESSED but don't force Gate 1.
SAFEGUARD_SOFT_RE = re.compile(r"\bbeat(?:s|en|ing)? (?:her|him|the child|them)|\bhit(?:s|ting)? (?:her|him|the child)|"
                               r"punish(?:es|ed|ment)? (?:physically|by hitting)", re.I)
MINOR_RE = re.compile(
    r"\b(?:1[0-7]|[2-9])\s*(?:-\s*)?(?:yr|yrs|year|years)(?:\s*-\s*|\s+)old\b|\b(?:1[0-7]|[2-9])\s*(?:yo|y/o)\b|"
    r"\baged? (?:1[0-7]|[2-9])\b|\b(?:1[0-7]|[2-9])\s*[MF]\b|"
    r"\bminor\b|\badolescent\b|\bteen(?:ager)?\b|\bschool ?girl\b|\bschool ?boy\b|\bclass [1-9]\b",
    re.I,
)
SCORE_INPUT_RE = re.compile(r"\b(?:PHQ-?9|GAD-?7|DASS-?21|HAM-?A|RSES|Rosenberg)\b\s*[:=]?\s*\d{1,2}\b", re.I)
CARDIAC_RE = re.compile(r"palpitat|palpatat|chest|cardiac|heart|breathless|dizz|faint|syncop|asthma", re.I)


@dataclass
class Finding:
    code: str
    message: str


@dataclass
class InspectionReport:
    meta: dict = field(default_factory=dict)
    blocks: list[Finding] = field(default_factory=list)
    warns: list[Finding] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return not self.blocks

    def block(self, code: str, msg: str) -> None:
        self.blocks.append(Finding(code, msg))

    def warn(self, code: str, msg: str) -> None:
        self.warns.append(Finding(code, msg))

    def retry_feedback(self) -> str:
        lines = ["Your previous draft failed the app's pre-send checks. Regenerate the COMPLETE reply, fixing:"]
        lines += [f"- [{f.code}] {f.message}" for f in self.blocks]
        return "\n".join(lines)

    def as_dict(self) -> dict:
        return {
            "passed": self.passed,
            "meta": self.meta,
            "blocks": [f.__dict__ for f in self.blocks],
            "warns": [f.__dict__ for f in self.warns],
        }


@dataclass
class InspectionContext:
    level: str                         # server-verified L1/L2/L3 — never from the client
    user_input: str                    # the de-identified clinician message for this turn
    verified_icd_codes: set[str] = field(default_factory=set)  # codes returned by icd11_lookup this turn
    requested_mode: str = "auto"


# ---------------------------------------------------------------------------
def parse_meta(text: str) -> tuple[dict | None, str]:
    m = META_RE.match(text)
    if not m:
        return None, text
    meta = dict(kv.split("=", 1) for kv in m.group("body").split() if "=" in kv)
    return meta, text[m.end():]


def strip_meta(text: str) -> str:
    return parse_meta(text)[1]


def _norm(s: str) -> str:
    s = s.replace("**", "").replace("’", "'")
    s = re.sub(r"^\s*>\s?", "", s, flags=re.M)
    return re.sub(r"\s+", " ", s).strip()


def _sections(body: str) -> dict[int, tuple[str, str]]:
    """Map section number -> (heading title, body text until next heading)."""
    heads = list(HEADING_RE.finditer(body))
    out: dict[int, tuple[str, str]] = {}
    for i, h in enumerate(heads):
        m = SECTION_NUM_RE.match(h.group("title"))
        if not m:
            continue
        end = heads[i + 1].start() if i + 1 < len(heads) else len(body)
        out.setdefault(int(m.group("n")), (h.group("title"), body[h.end():end]))
    return out


def _has_heading(body: str, phrase: str) -> bool:
    return any(phrase.lower() in h.group("title").lower() for h in HEADING_RE.finditer(body))


# ---------------------------------------------------------------------------
def inspect(text: str, ctx: InspectionContext) -> InspectionReport:
    rep = InspectionReport()
    meta, body = parse_meta(text)

    # --- App contract line ---------------------------------------------------
    if meta is None:
        rep.block("META", "First line must be the app contract line, e.g. <!--yc mode=A gate=none ceiling=Low level=L2-->.")
        return rep
    rep.meta = meta
    mode, gate, ceiling, level = meta.get("mode"), meta.get("gate"), meta.get("ceiling"), meta.get("level")
    if mode not in VALID_MODES or gate not in VALID_GATES or ceiling not in VALID_CEILINGS:
        rep.block("META", f"Contract line values invalid (mode={mode}, gate={gate}, ceiling={ceiling}).")
        return rep
    if level != ctx.level:
        rep.block("LEVEL", f"Clinician level is {ctx.level} (verified by the app); reply was written for {level}.")
    if ctx.requested_mode not in ("auto", None) and gate == "none" and mode not in (ctx.requested_mode, "Q") \
            and not (ctx.requested_mode == "A" and mode == "A2"):
        rep.warn("MODE", f"Clinician requested Mode {ctx.requested_mode}; reply used Mode {mode}.")

    flat = _norm(body)
    sections = _sections(body)

    # --- QC close: disclaimer verbatim, last block ---------------------------
    if mode != "Q":
        idx = flat.find(DISCLAIMER)
        if idx < 0:
            rep.block("DISCLAIMER", "The v2.1 mandatory disclaimer must appear verbatim.")
        else:
            tail = flat[idx + len(DISCLAIMER):].strip()
            if len(tail) > 200:
                rep.block("DISCLAIMER", "The disclaimer must be the last block (at most one short offer line after it).")

    # --- Gate 1 (QC 2) -------------------------------------------------------
    risk_in_input = bool(RISK_INPUT_RE.search(ctx.user_input))
    if risk_in_input and gate != "gate1" and not SAFETY_MANAGED_RE.search(ctx.user_input):
        rep.block("GATE1", "The clinician's message contains possible imminent-risk indicators. Apply Gate 1 "
                           "(risk summary, immediate actions, emergency pathway, safeguarding, disclaimer only) "
                           "unless the clinician has stated that immediate safety is being managed.")
    if gate == "gate1":
        if "112" not in flat or "14416" not in flat:
            rep.block("GATE1", "Gate 1 output must give 112 and Tele-MANAS 14416 / 1-800-891-4416.")
        if re.search(r"\|\s*(?:Week|Wk)\s*\|", body) or any(n >= 3 for n in sections):
            rep.block("GATE1", "Gate 1 output must not contain routine planning (no numbered sections 3+, no session table).")
        if "confirm" not in flat.lower():
            rep.block("GATE1", "Gate 1 output must ask the clinician to confirm immediate safety before routine planning.")
        if MINOR_RE.search(ctx.user_input):
            if "1098" not in flat:
                rep.block("SAFEGUARD", "Minor involved: include Child Helpline 1098.")
            if not re.search(r"POCSO|guardian|parent", flat, re.I):
                rep.block("SAFEGUARD", "Minor involved: address safeguarding and guardian involvement (POCSO where relevant).")

    if SAFEGUARD_SOFT_RE.search(ctx.user_input) and MINOR_RE.search(ctx.user_input) and gate != "gate1":
        if not re.search(r"safeguard|physical punishment|corporal|child protection", flat, re.I):
            rep.block("SAFEGUARD", "Physical harm to a child is described: address safeguarding explicitly.")

    # --- Required structure per mode (QC 0a, 1) -----------------------------
    if gate != "gate1":
        req_nums = {"A": range(1, 18), "A2": (1, 2, 3, 4, 16), "C": (1, 2, 3, 4, 6), "E": (1,), "G": (1,)}.get(mode, ())
        missing = [n for n in req_nums if n not in sections]
        if missing:
            rep.block("STRUCTURE", f"Mode {mode} is missing numbered section(s): {', '.join(map(str, missing))}.")
        if mode in ("A", "A2", "C", "E", "G") and 1 in sections and "audit" not in sections[1][0].lower():
            rep.block("AUDIT", "Section 1 must be the Case History & MSE Audit.")
        if mode in ("A", "A2", "B", "C") and not _has_heading(body, "Safety"):
            rep.block("SAFETY", "The Safety & Risk Screen section is missing.")
        if mode in ("B", "D") and not _has_heading(body, "Condensed audit"):
            rep.block("AUDIT", f"Mode {mode} must open with the condensed audit (rating, critical gaps, ceiling).")
        if mode == "A2" and not _has_heading(body, "Priority questions"):
            rep.block("GATE2", "Gate 2 short form must list 3–7 priority questions for the next session.")
        if mode == "B" and not _has_heading(body, "Next steps"):
            rep.block("STRUCTURE", "Mode B must end with Next steps before the disclaimer.")
        if mode == "D" and not re.search(r"\|\s*(?:Week|Wk|Session)", body):
            rep.block("STRUCTURE", "Mode D must include the session plan table.")
        if mode == "E" and not _has_heading(body, "Diagnostic review"):
            rep.block("STRUCTURE", "Mode E must include the Diagnostic review (C2) after the audit.")
        if mode == "F" and "Risk reviewed this session" not in flat:
            rep.block("STRUCTURE", "Documentation must start with the safety line 'Risk reviewed this session: …'.")
        if mode == "Q" and (len(flat) > 1500 or sections):
            rep.block("STRUCTURE", "A clarifying question (mode Q) must be short and contain no plan sections.")

    # --- Audit rating ↔ ceiling (QC 0d) --------------------------------------
    rating = re.search(r"(?:Overall rating|Rating)\s*:?\s*(Complete|Adequate with gaps|Incomplete|Critical omission)", flat, re.I)
    if rating:
        r = rating.group(1).lower()
        if r in ("incomplete", "critical omission") and ceiling != "Low":
            rep.block("CEILING", f"Audit rated '{rating.group(1)}' → confidence ceiling must be Low.")
        if r == "adequate with gaps" and ceiling == "High":
            rep.block("CEILING", "Audit rated 'Adequate with gaps' → ceiling cannot exceed Moderate.")
    elif mode in ("A", "A2", "B", "C", "D", "E", "G") and gate != "gate1":
        rep.block("AUDIT", "No audit rating found (Complete / Adequate with gaps / Incomplete / Critical omission).")

    # --- PROVISIONAL headings when ceiling is Low (QC 0d) ---------------------
    if ceiling == "Low" and gate != "gate1":
        bad = [n for n, (title, _) in sections.items() if n >= 3 and "PROVISIONAL" not in title.upper()]
        if bad:
            rep.block("PROVISIONAL", "Ceiling is Low: every heading from Section 3 onward must carry "
                                     f"'PROVISIONAL — Low confidence' (missing on: {', '.join(map(str, sorted(bad)))}).")

    # --- Confidence labels (QC 15) --------------------------------------------
    for n in ((3, 5) if mode == "A" else (3,) if mode in ("A2", "C") else ()):
        if n in sections and "confidence" not in sections[n][1].lower():
            rep.block("CONFIDENCE", f"Section {n} needs a 'Confidence: High/Moderate/Low — reason' label.")

    # --- Session table 8 columns, decision tree (QC 12, 12b) ------------------
    if mode == "A" and 13 in sections:
        hdr = re.search(r"^\|\s*(?:Week|Wk)\b.*\|\s*$", sections[13][1], re.M | re.I)
        cols = len([c for c in hdr.group(0).strip().strip("|").split("|")]) if hdr else 0
        if cols != 8:
            rep.block("SESSION_TABLE", f"Section 13 table must have 8 columns (found {cols}).")
    if mode in ("A", "D") and gate != "gate1":
        tree_src = (sections.get(15, ("", ""))[1] if mode == "A" else body).lower()
        need = {"improving": "improving", "partial": "partial", "no meaningful": "no meaningful improvement",
                "worsening": "worsening", "new symptom": "new symptoms"}
        miss = [v for k, v in need.items() if k not in tree_src]
        if miss:
            rep.block("DECISION_TREE", f"Decision tree is missing branch(es): {', '.join(miss)}.")

    # --- L1 competence gating (QC 15c) ----------------------------------------
    if ctx.level == "L1" and gate != "gate1":
        if 4 in sections:
            t, b = sections[4]
            if "areas for the supervisor" not in t.lower():
                rep.block("L1", "L1 user: Section 4 must be titled 'Areas for the supervisor or a psychologist to assess'.")
            if ICD_CODE_RE.search(b) or re.search(r"DSM-5|ICD-1[01]", b):
                rep.block("L1", "L1 user: no diagnostic labels or codes in Section 4.")
        if "supervisor" not in flat.lower():
            rep.block("L1", "L1 user: next steps must include discussing with the supervisor.")

    # --- Medication (QC 14) ---------------------------------------------------
    for m in MED_REC_RE.finditer(flat.replace(PRESCRIBER_LINE, "")):
        rep.block("MEDICATION", f"Possible medication recommendation: '{m.group(0)[:90]}'. Only the prescriber-review line is allowed.")
        break

    # --- No-harm contract (QC 15d) --------------------------------------------
    for m in re.finditer(r"no[\s-]harm contract|no[\s-]suicide contract", flat, re.I):
        before = flat[max(0, m.start() - 50):m.start()].lower()
        if not re.search(r"\b(?:never|not|avoid|instead of|rather than|no |don't|do not)\b", before):
            rep.block("NO_HARM_CONTRACT", "Do not suggest a no-harm contract; use a collaborative safety plan.")

    # --- Unsafe homework (QC 14b) ---------------------------------------------
    if re.search(r"interoceptive", flat, re.I) and CARDIAC_RE.search(ctx.user_input + flat):
        if not re.search(r"medical clearance|after clearance|medically cleared|once cleared|if cleared", flat, re.I):
            rep.block("UNSAFE_HOMEWORK", "Interoceptive exposure must be gated behind medical clearance.")

    # --- Crisis numbers match the register (QC 8c) ----------------------------
    for marker in RETIRED_CRISIS_MARKERS:
        if marker in body:
            rep.block("CRISIS_NUMBERS", f"'{marker}' is retired/not in the crisis register — use Tele-MANAS / Child Helpline 1098.")
    for m in re.finditer(r"(?<![\w.])\+?\d[\d\s-]{5,}\d(?!\w)(?!\.\d)", flat):
        digits = re.sub(r"\D", "", m.group(0))
        if len(digits) >= 7 and digits not in ALLOWED_CRISIS_NUMBERS:
            rep.block("CRISIS_NUMBERS", f"Phone-like number '{m.group(0)}' is not in the crisis register.")
    for m in re.finditer(r"(?:helpline|hotline|call|dial|tele-manas|line|number)[^\d\n]{0,15}(\d{3,5})\b", flat, re.I):
        if m.group(1) not in ALLOWED_CRISIS_NUMBERS:
            rep.block("CRISIS_NUMBERS", f"Number '{m.group(1)}' near '{m.group(0)[:20]}' is not in the crisis register.")

    # --- ICD / DSM codes verified or marked (QC 7b) ---------------------------
    for m in ICD_CODE_RE.finditer(flat):
        code = m.group(0)
        if code in ctx.verified_icd_codes or code in ctx.user_input:
            continue
        window = flat[m.end():m.end() + 80].lower()
        if "to confirm" in window or "confirm at" in window:
            continue
        rep.block("ICD_CODE", f"Code '{code}' was not verified with icd11_lookup this turn; verify it or write 'code to confirm at icd.who.int'.")

    # --- Screening ≠ diagnosis (SKILL rule 7) ---------------------------------
    if SCORE_INPUT_RE.search(ctx.user_input) and not re.search(r"screening only\s*[—–-]+\s*not a diagnosis", flat, re.I):
        rep.block("SCREENING", "Scale scores discussed: add 'Screening only — not a diagnosis.'")

    # --- Mode E wording (C2.8) ------------------------------------------------
    if mode == "E":
        if re.search(r"\b(?:incorrect|diagnosis is correct|correct diagnosis)\b", flat, re.I):
            rep.block("MODE_E", "Never call a diagnosis 'correct' or 'incorrect'.")
        if ceiling == "Low" and re.search(r"Rating\s*:?\s*Well supported", flat, re.I):
            rep.block("MODE_E", "Audit ceiling is Low: the diagnosis cannot be rated 'Well supported'.")

    # --- Identifiers echoed (QC 17) -------------------------------------------
    for r in find_identifiers(body):
        if r.type in ("NAME", "ORG", "ADDRESS"):
            rep.warn("IDENTIFIER", f"Possible {r.type} in output at {r.start}.")
        else:
            rep.block("IDENTIFIER", f"Output contains a {r.type}-like identifier; do not repeat identifiers.")

    # de-duplicate
    seen, uniq = set(), []
    for f in rep.blocks:
        if (f.code, f.message) not in seen:
            seen.add((f.code, f.message))
            uniq.append(f)
    rep.blocks = uniq
    return rep
