"""
De-identification "cleaner".

Product rule (hard, not a hope): no names, phone numbers, emails, addresses,
ID numbers, employer/school names, or rare identifying details may leave the
clinician's phone. Age, sex, symptoms, history and scores are fine.

This module is the *reference implementation*. The Android app ports the same
rules to Kotlin and must pass the same fixture file
(fixtures/deid_vectors.json). The server runs it again on every request as a
second line of defence: if the server finds anything, the request is rejected.

Two outputs:
  * redactions — things we are confident are identifiers; replaced by a tag.
  * warnings   — capitalised words that *might* be a person's name. Regex can't
                 reliably find bare names ("Priya came with her mother"), so the
                 app shows these to the clinician and asks them to confirm or
                 edit before sending. Warnings never block on the server.

Nothing in this module logs or returns the original identifier values except
inside the CleanResult given back to the caller on the device (the server
discards them — see app/main.py).
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

# ---------------------------------------------------------------------------
# Patterns. Order matters: earlier categories win overlapping spans.
# ---------------------------------------------------------------------------

_HONORIFICS = r"(?:Mr|Mrs|Ms|Miss|Mx|Dr|Prof|Shri|Shrimati|Smt|Sri|Sh|Kumari|Km|Master|Baby|Late)"
_CAP = r"[A-Z][a-z]+"
_NAME_TAIL = rf"{_CAP}(?:\s+{_CAP}){{0,2}}"

PATTERNS: list[tuple[str, re.Pattern]] = [
    ("EMAIL", re.compile(r"\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b")),
    ("URL", re.compile(r"\b(?:https?://|www\.)\S+", re.I)),
    ("HANDLE", re.compile(r"(?<![\w@])@[A-Za-z0-9_.]{3,}")),
    # Labelled identifiers: "Aadhaar: 1234 5678 9012", "UHID 44321", "MRN-9981"
    ("ID", re.compile(
        r"\b(?:aadhaa?r|uid|uhid|mrn|ipd|opd|reg(?:istration)?\.?\s*no|roll\s*no|"
        r"employee\s*id|emp\s*id|pan\s*(?:card|no)|passport|voter\s*id|abha|ration\s*card|"
        r"policy\s*no|account\s*no)\b\.?\s*(?:no\.?|number|#)?\s*[:\-]?\s*(?=[A-Z0-9\-/ ]*\d)[A-Z0-9][A-Z0-9\-/ ]{3,20}[A-Z0-9]",
        re.I)),
    ("DOB", re.compile(
        r"\b(?:d\.?o\.?b\.?|date\s+of\s+birth|born\s+on)\s*[:\-]?\s*"
        r"(?:\d{1,2}[\-/. ]\d{1,2}[\-/. ]\d{2,4}|\d{1,2}\s+[A-Za-z]{3,9}\s+\d{4}|[A-Za-z]{3,9}\s+\d{1,2},?\s+\d{4})",
        re.I)),
    ("ID", re.compile(r"\b[A-Z]{5}\d{4}[A-Z]\b")),            # PAN
    ("ID", re.compile(r"\b[A-Z]{3}\d{7}\b")),                  # Voter ID (EPIC)
    ("ID", re.compile(r"\b[A-PR-WY][1-9]\d\s?\d{4}[1-9]\b")),  # Passport
    ("ID", re.compile(r"\b[2-9]\d{3}[\s-]\d{4}[\s-]\d{4}\b")), # Aadhaar, spaced
    # Indian mobile: optional +91 / 91 / 0, then 10 digits starting 6-9
    ("PHONE", re.compile(r"(?<!\d)(?:\+?91[\s-]?|0)?[6-9]\d{4}[\s-]?\d{5}(?!\d)")),
    # Landline with STD code: 020-2345 6789, 022 23456789
    ("PHONE", re.compile(r"(?<!\d)0\d{2,4}[\s-]\d{3,4}[\s-]?\d{4}(?!\d)")),
    ("ADDRESS", re.compile(
        r"\b(?:resides?\s+at|residing\s+at|lives\s+at|living\s+at|address\s*[:\-]|"
        r"r/o|staying\s+at)\s*[^.\n]{3,120}", re.I)),
    ("ADDRESS", re.compile(
        r"\b(?:flat|house|h\.?\s?no|plot|room|door|bldg|building|wing|block)\s*(?:no\.?|number|#)?\s*[:\-]?\s*"
        r"[A-Z]?\d{1,5}[A-Z]?\b[^.\n]{0,80}", re.I)),
    ("PINCODE", re.compile(r"\b(?:pin(?:\s*code)?|pincode|postal\s*code)\s*[:\-]?\s*[1-9]\d{2}\s?\d{3}\b", re.I)),
    # Honorific + capitalised name
    ("NAME", re.compile(rf"\b{_HONORIFICS}\.?\s+{_NAME_TAIL}")),
    # "name is X", "named X", "Name: X", "called X" (capitalised only)
    ("NAME", re.compile(rf"\b(?:[Nn]ame\s*(?:is|:|-)|[Nn]amed|goes\s+by|[Cc]alled)\s+{_NAME_TAIL}")),
    # Employer / school / college with a capitalised proper name
    ("ORG", re.compile(
        rf"\b(?:works?\s+(?:at|in|for|with)|working\s+(?:at|in|for|with)|employed\s+(?:at|in|by|with)|"
        rf"job\s+at|studies\s+at|studying\s+(?:at|in)|student\s+(?:at|of)|enrolled\s+(?:at|in)|"
        rf"school\s*[:\-]|college\s*[:\-]|company\s*[:\-]|employer\s*[:\-])\s+(?:the\s+)?"
        rf"(?!(?:IT|BPO|KPO|MNC|PSU|ITES|Govt|Government|Private|Pvt|Sales|Marketing|HR|Finance|Accounts|Education|Healthcare|Hospitality|Retail|Construction|Agriculture)\b)"
        rf"[A-Z][\w&.'-]*(?:\s+[A-Z][\w&.'-]*){{0,4}}")),
    # Any other long digit run (≥7 digits, spaces/hyphens allowed): account, MRN…
    ("ID", re.compile(r"(?<![\d/.-])\d(?:[\s-]?\d){6,}(?![\d/.-])")),
]

# Numbers that must never be redacted (crisis lines from crisis-resources.md).
PROTECTED_LITERALS = ["1-800-891-4416", "1800-891-4416", "18008914416"]

# Dates are kept (session dates, onset dates) unless labelled as DOB.
_DATE = re.compile(r"\b\d{1,4}[\-/.]\d{1,2}[\-/.]\d{1,4}\b")

# ---------------------------------------------------------------------------
# "Possible name" warnings
# ---------------------------------------------------------------------------
_COMMON_TITLECASE = {
    # calendar
    *"monday tuesday wednesday thursday friday saturday sunday".split(),
    *"january february march april may june july august september october november december".split(),
    # languages, religions, regions (coarse location is allowed)
    *"hindi marathi english gujarati tamil telugu kannada malayalam bengali punjabi urdu odia assamese konkani".split(),
    *"hindu muslim christian sikh jain buddhist parsi islam christianity god allah bhagwan diwali eid holi christmas navratri ramadan".split(),
    *"india indian maharashtra mumbai pune delhi bangalore bengaluru chennai hyderabad kolkata nagpur nashik thane goa gujarat karnataka kerala".split(),
    # clinical / system words that commonly appear capitalised mid-sentence
    *"client patient mother father sister brother wife husband son daughter grandmother grandfather aunt uncle".split(),
    *"cbt erp dbt act emdr mse gad phq dass ham rses icd dsm who ayurvedic homeopathic unani yoga pranayama".split(),
    *"tele tele-manas manas child women helpline emergency section mode week session".split(),
    *"i ok no yes not he she they his her their".split(),
}


@dataclass
class Redaction:
    type: str
    start: int
    end: int
    replacement: str


@dataclass
class CleanResult:
    text: str                                   # cleaned text (safe to send)
    redactions: list[Redaction] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)   # possible names, for the clinician to review

    @property
    def counts(self) -> dict[str, int]:
        out: dict[str, int] = {}
        for r in self.redactions:
            out[r.type] = out.get(r.type, 0) + 1
        return out

    @property
    def is_clean(self) -> bool:
        return not self.redactions


def _protected_spans(text: str) -> list[tuple[int, int]]:
    spans = []
    for lit in PROTECTED_LITERALS:
        for m in re.finditer(re.escape(lit), text):
            spans.append((m.start(), m.end()))
    for m in _DATE.finditer(text):
        spans.append((m.start(), m.end()))
    return spans


def _overlaps(a: tuple[int, int], spans: list[tuple[int, int]]) -> bool:
    return any(a[0] < e and s < a[1] for s, e in spans)


def find_identifiers(text: str) -> list[Redaction]:
    protected = _protected_spans(text)
    taken: list[tuple[int, int]] = []
    found: list[Redaction] = []
    for kind, pat in PATTERNS:
        for m in pat.finditer(text):
            span = (m.start(), m.end())
            # Labelled DOB overrides date protection; everything else respects it.
            if kind != "DOB" and _overlaps(span, protected):
                continue
            if _overlaps(span, taken):
                continue
            taken.append(span)
            found.append(Redaction(kind, span[0], span[1], f"[{kind}]"))
    found.sort(key=lambda r: r.start)
    return found


def possible_names(text: str) -> list[str]:
    """Title-case words that are not at a sentence start and not common words."""
    hits: list[str] = []
    for m in re.finditer(r"(?<=[a-z0-9,;:)]\s)([A-Z][a-z]{2,})\b", text):
        w = m.group(1)
        if w.lower() in _COMMON_TITLECASE:
            continue
        if w not in hits:
            hits.append(w)
    return hits


def clean(text: str) -> CleanResult:
    reds = find_identifiers(text)
    out, last = [], 0
    for r in reds:
        out.append(text[last:r.start])
        out.append(r.replacement)
        last = r.end
    out.append(text[last:])
    cleaned = "".join(out)
    return CleanResult(text=cleaned, redactions=reds, warnings=possible_names(cleaned))
