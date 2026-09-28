"""
One consult turn, end to end:

  clinician text (already cleaned on the phone)
    → server-side cleaner re-check (reject if anything found)
    → Claude with the pinned skill + tools (get_card, icd11_lookup)
    → inspector → [regenerate once with the failure list] → inspector
    → deliver, or hold back with a safe fallback message
    → everything returned for logging (turns table)

This module has no web or database code so it can be unit-tested with a fake
model (tests/test_pipeline.py).
"""
from __future__ import annotations

import time
from dataclasses import dataclass, field
from datetime import date
from typing import Protocol

from . import deid
from .inspector import DISCLAIMER, InspectionContext, InspectionReport, inspect, strip_meta
from .prompt import Skill, app_header, get_card

TOOLS = [
    {
        "name": "get_card",
        "description": "Fetch one card from the YourCounselor Core 1–6 knowledge base by its ID "
                       "(e.g. ASM-06, INS-PHQ9, CP-ALC, GRD-01, TPE-02, NPS-00, or a PART prefix such as BRF). "
                       "Use the CORE CARD INDEX in the system prompt. Fetch only cards the request needs.",
        "input_schema": {"type": "object", "properties": {"card_id": {"type": "string"}}, "required": ["card_id"]},
    },
    {
        "name": "icd11_lookup",
        "description": "Search the WHO ICD-11 MMS (pinned release) for an entity by name. Returns official codes and "
                       "titles. Only codes returned here in this turn may be shown to the clinician.",
        "input_schema": {"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]},
    },
]

FALLBACK = (
    "This reply was held back because it did not pass the app's clinical safety checks. It has been logged "
    "for review. Please try again, or rephrase the request.\n\n"
    "If there is any immediate risk to your client: **112** · **Tele-MANAS 14416 / 1-800-891-4416** · "
    "**Child Helpline 1098** · **Women Helpline 181**.\n\n> **" + DISCLAIMER + "**"
)


class ModelClient(Protocol):
    def run(self, system: str, messages: list[dict], tools: list[dict], tool_handler) -> "ModelResult": ...


@dataclass
class ModelResult:
    text: str
    model: str
    usage: dict = field(default_factory=dict)
    tool_calls: list[dict] = field(default_factory=list)


class DeidRejected(Exception):
    def __init__(self, counts: dict[str, int]):
        super().__init__(f"identifiers found: {counts}")
        self.counts = counts


@dataclass
class TurnResult:
    status: str                    # delivered | blocked
    display_text: str              # what the clinician sees (contract line stripped)
    raw_text: str                  # final model text incl. contract line (for logs)
    reports: list[dict]            # inspector report per attempt
    attempts: int
    model: str
    skill_version: str
    prompt_hash: str
    tool_calls: list[dict]
    usage: list[dict]
    latency_ms: int
    verified_icd_codes: list[str]


class Pipeline:
    def __init__(self, skill: Skill, model: ModelClient, icd, max_attempts: int = 2):
        self.skill, self.model, self.icd, self.max_attempts = skill, model, icd, max_attempts

    def run(self, text: str, level: str, requested_mode: str = "auto", history: list[dict] | None = None,
            today: str | None = None) -> TurnResult:
        t0 = time.monotonic()
        # Second line of defence: the phone should already have cleaned this.
        check = deid.clean(text)
        if not check.is_clean:
            raise DeidRejected(check.counts)

        verified: set[str] = set()
        tool_log: list[dict] = []

        def handle_tool(name: str, args: dict) -> str:
            if name == "get_card":
                out = get_card(self.skill, str(args.get("card_id", "")))
                tool_log.append({"tool": name, "card_id": args.get("card_id"), "chars": len(out)})
                return out
            if name == "icd11_lookup":
                try:
                    hits = self.icd.search(str(args.get("query", "")))
                except Exception as e:  # never let the WHO API take down a consult
                    tool_log.append({"tool": name, "query": args.get("query"), "error": type(e).__name__})
                    return "ICD-11 lookup unavailable. Write 'code to confirm at icd.who.int'."
                verified.update(h["code"] for h in hits)
                tool_log.append({"tool": name, "query": args.get("query"), "codes": [h["code"] for h in hits]})
                if not hits:
                    return "No match. Write 'code to confirm at icd.who.int'."
                return "\n".join(f"{h['code']} — {h['title']} (ICD-11 MMS {h['release']})" for h in hits)
            return f"Unknown tool {name}."

        user_msg = app_header(level, requested_mode, today or date.today().isoformat()) + text
        messages = list(history or []) + [{"role": "user", "content": user_msg}]
        ctx = InspectionContext(level=level, user_input=text, verified_icd_codes=verified,
                                requested_mode=requested_mode)

        reports: list[InspectionReport] = []
        usage: list[dict] = []
        result: ModelResult | None = None
        for attempt in range(1, self.max_attempts + 1):
            result = self.model.run(self.skill.system_prompt, messages, TOOLS, handle_tool)
            usage.append(result.usage)
            rep = inspect(result.text, ctx)
            reports.append(rep)
            if rep.passed:
                break
            messages = messages + [
                {"role": "assistant", "content": result.text},
                {"role": "user", "content": rep.retry_feedback()},
            ]

        assert result is not None
        passed = reports[-1].passed
        return TurnResult(
            status="delivered" if passed else "blocked",
            display_text=strip_meta(result.text).strip() if passed else FALLBACK,
            raw_text=result.text,
            reports=[r.as_dict() for r in reports],
            attempts=len(reports),
            model=result.model,
            skill_version=self.skill.version,
            prompt_hash=self.skill.prompt_hash,
            tool_calls=tool_log,
            usage=usage,
            latency_ms=int((time.monotonic() - t0) * 1000),
            verified_icd_codes=sorted(verified),
        )
