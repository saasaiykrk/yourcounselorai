"""
Guided consultation: a short, case-specific intake (one question at a time), then the
fixed Consultation Report (Mode R).

  start(case) ─► intake call ─► next question │ ready │ safety stop
  answer │ don't know │ skip ─► intake call ─► …
  report ─► the existing Pipeline with "Requested mode: R" (cleaner, inspector, retry, hold-back)

Token rules
  * An intake call sends only the small intake prompt, the COMPACT STATE (summary, facts,
    unknowns, question count) and the latest question + reply. Never the raw conversation,
    never the skill or the report template.
  * The report is one call: the cached skill prompt + the report template part + a compact
    case summary built from the state.
  * Stage changes, "don't know", fact edits, the question cap and the mandatory-field
    questions (taken from the intake guide) need no model call.

Safety
  * Every clinician text is re-checked by the cleaner; risk phrases stop the intake and the
    app shows the crisis pathway until the clinician confirms safety.
  * Every intake response passes inspect_intake() before any of it is stored or shown;
    the report passes the full inspector.

No web or database code: tests/test_consultation.py runs it with a fake model.
"""
from __future__ import annotations

import json
import re
from typing import Protocol

from . import deid
from .inspector import RISK_INPUT_RE, SAFETY_MANAGED_RE, inspect_intake
from .pipeline import DeidRejected, Pipeline, TurnResult
from .prompt import INTAKE_SCHEMA, ConsultPrompts

INITIAL_CASE = "INITIAL_CASE"
QUESTIONING = "QUESTIONING"
INFORMATION_SUFFICIENT = "INFORMATION_SUFFICIENT"
REPORT_GENERATION = "REPORT_GENERATION"
COMPLETED = "COMPLETED"
SAFETY_STOP = "SAFETY_STOP"
STAGES = (INITIAL_CASE, QUESTIONING, INFORMATION_SUFFICIENT, REPORT_GENERATION, COMPLETED, SAFETY_STOP)

MAX_QUESTIONS = 8          # model-chosen questions; mandatory-field questions may follow
MAX_FACTS = 30
MAX_TRANSCRIPT = 24
ACTIONS = ("answer", "dont_know", "skip", "finish", "safety_managed", "safety_absent")

RISK_MANAGED = "risk present — clinician confirmed immediate safety is managed"
RISK_ABSENT = "asked and absent — clinician confirmed after the safety prompt (safety is managed)"


class IntakeModel(Protocol):
    def run_structured(self, system: str, user: str, schema: dict) -> tuple[dict | None, dict]: ...


class ConsultationError(Exception):
    def __init__(self, status: int, detail: str):
        super().__init__(detail)
        self.status, self.detail = status, detail


def new_state() -> dict:
    return {"stage": INITIAL_CASE, "case_summary": "", "facts": {}, "unknown": [], "pending": None,
            "questions_asked": 0, "transcript": [], "brief_answer": "", "pending_input": "",
            "safety_confirmed": False, "usage": {"calls": 0}, "report": None}


def _field(name: str) -> str:
    return re.sub(r"[^a-z0-9_]+", "_", str(name).strip().lower()).strip("_")[:40]


def _clean_or_raise(text: str) -> str:
    text = (text or "").strip()
    check = deid.clean(text)
    if not check.is_clean:
        raise DeidRejected(check.counts)
    return text


def _risky(text: str) -> bool:
    return bool(RISK_INPUT_RE.search(text)) and not SAFETY_MANAGED_RE.search(text)


class ConsultationEngine:
    def __init__(self, prompts: ConsultPrompts, model: IntakeModel, pipeline: Pipeline,
                 max_questions: int = MAX_QUESTIONS):
        self.prompts, self.model, self.pipeline, self.max_questions = prompts, model, pipeline, max_questions

    # --- public steps ---------------------------------------------------------------
    def start(self, text: str) -> dict:
        state = new_state()
        text = _clean_or_raise(text)
        state["case_text"] = text
        if _risky(text):
            return self._safety_stop(state, text)
        self._intake(state, text, header="[Initial case]")
        return state

    def reply(self, state: dict, action: str, text: str = "") -> dict:
        if action not in ACTIONS:
            raise ConsultationError(422, f"unknown action '{action}'")
        stage = state["stage"]
        state["brief_answer"] = ""
        if stage == SAFETY_STOP:
            if action not in ("safety_managed", "safety_absent"):
                raise ConsultationError(409, "confirm the client's safety first")
            return self._confirm_safety(state, action)
        if stage not in (QUESTIONING, INFORMATION_SUFFICIENT):
            raise ConsultationError(409, f"consultation is {stage.lower()}")

        if action == "finish":
            if not (state["facts"] or state["case_summary"]):
                raise ConsultationError(409, "describe the case first")
            state["pending"], state["stage"] = None, INFORMATION_SUFFICIENT
            return state

        pending = state["pending"]
        if action in ("dont_know", "skip"):
            if not pending:
                raise ConsultationError(409, "there is no open question")
            self._record_answer(state, "(don't know)" if action == "dont_know" else "(skipped)")
            if pending["field"] not in state["unknown"]:
                state["unknown"].append(pending["field"])
            state["pending"] = None
            if self._next_mandatory(state):
                return state                                   # fixed question, no model call
            note = "The clinician does not know this." if action == "dont_know" else "The clinician skipped this."
            self._intake(state, note, header=f"[Question just answered] ({pending['field']}) {pending['question']}")
            return state

        # action == "answer" (also used to add information once the case is ready)
        text = _clean_or_raise(text)
        if not text:
            raise ConsultationError(422, "answer is empty")
        if pending:
            self._record_answer(state, text)
        else:
            state["transcript"].append({"field": "", "question": "", "why": "", "answer": text})
        if _risky(text):
            return self._safety_stop(state, text)
        header = (f"[Question just answered] ({pending['field']}) {pending['question']}" if pending
                  else "[Additional information from the clinician]")
        self._intake(state, text, header=header)
        return state

    def edit_facts(self, state: dict, patch: dict[str, str | None]) -> dict:
        """The clinician corrects the summary directly. Deterministic: no model call."""
        if state["stage"] not in (QUESTIONING, INFORMATION_SUFFICIENT):
            raise ConsultationError(409, f"consultation is {state['stage'].lower()}")
        for name, value in patch.items():
            key = _field(name)
            if not key:
                continue
            if value is None or not str(value).strip():
                state["facts"].pop(key, None)
                continue
            value = _clean_or_raise(str(value))[:300]
            state["facts"][key] = value
            if key in state["unknown"]:
                state["unknown"].remove(key)
            if key == "risk_screening" and _risky(value):
                return self._safety_stop(state, value)
        if len(state["facts"]) > MAX_FACTS:
            raise ConsultationError(422, "too many facts")
        return state

    def case_text(self, state: dict) -> str:
        """The compact case the report is written from (no raw conversation)."""
        lines = ["[Guided consultation — case collected by the app]",
                 f"Case summary: {state['case_summary'] or '(not provided)'}", "",
                 "Facts provided by the clinician:"]
        lines += [f"- {k}: {v}" for k, v in state["facts"].items()] or ["- (none)"]
        if state["unknown"]:
            lines += ["", "Not known to the clinician: " + ", ".join(state["unknown"])]
        missing = [m["field"] for m in self.prompts.mandatory
                   if m["field"] not in state["facts"] and m["field"] not in state["unknown"]]
        if missing:
            lines += ["", "Not asked (report as not provided): " + ", ".join(missing)]
        return "\n".join(lines)

    def report(self, state: dict, level: str, force: bool = False, today: str | None = None) -> TurnResult:
        stage = state["stage"]
        if stage == QUESTIONING and force and (state["facts"] or state["case_summary"]):
            state["stage"] = stage = INFORMATION_SUFFICIENT
        if stage != INFORMATION_SUFFICIENT:
            raise ConsultationError(409, "more information is needed before the report" if stage == QUESTIONING
                                    else f"consultation is {stage.lower()}")
        state["stage"], state["pending"] = REPORT_GENERATION, None
        try:
            r = self.pipeline.run(self.case_text(state), level=level, requested_mode="R", today=today,
                                  extra_system=self.prompts.report_addendum,
                                  prompt_hash=f"{self.pipeline.skill.prompt_hash}+{self.prompts.prompt_hash}")
        except Exception:
            state["stage"] = INFORMATION_SUFFICIENT
            raise
        # A held-back report leaves the case ready, so the clinician can try again.
        state["stage"] = COMPLETED if r.status == "delivered" else INFORMATION_SUFFICIENT
        return r

    # --- internals ------------------------------------------------------------------
    def _safety_stop(self, state: dict, text: str) -> dict:
        state["stage"], state["pending"], state["pending_input"] = SAFETY_STOP, None, text
        return state

    def _confirm_safety(self, state: dict, action: str) -> dict:
        state["facts"]["risk_screening"] = RISK_MANAGED if action == "safety_managed" else RISK_ABSENT
        if "risk_screening" in state["unknown"]:
            state["unknown"].remove("risk_screening")
        state["safety_confirmed"], state["stage"] = True, QUESTIONING
        pending_input, state["pending_input"] = state["pending_input"], ""
        note = ("[App note] The clinician has confirmed: " + state["facts"]["risk_screening"] +
                ". Record the other facts; do not return risk_stop for this message.")
        self._intake(state, f"{pending_input}\n\n{note}",
                     header="[Initial case]" if not state["case_summary"] else "[Clinician's message]")
        return state

    def _record_answer(self, state: dict, answer: str) -> None:
        if state["transcript"] and state["transcript"][-1]["answer"] is None:
            state["transcript"][-1]["answer"] = answer

    def _payload(self, state: dict, latest: str, header: str, final: bool, feedback: str = "") -> str:
        compact = {"case_summary": state["case_summary"], "facts": state["facts"], "unknown": state["unknown"],
                   "questions_asked": state["questions_asked"], "max_questions": self.max_questions}
        parts = ["[Consultation state]", json.dumps(compact, ensure_ascii=False, separators=(",", ":")), "",
                 header, "[Clinician's message]", latest]
        if final:
            parts += ["", "[App note] The question limit is reached: record the facts and return status \"ready\"."]
        if feedback:
            parts += ["", "[App note] Your previous response failed the app's checks. Return corrected JSON:", feedback]
        return "\n".join(parts)

    def _intake(self, state: dict, latest: str, header: str) -> None:
        final = state["questions_asked"] >= self.max_questions
        clinician_text = state.get("case_text", "") + "\n" + "\n".join(t["answer"] or "" for t in state["transcript"])
        feedback, out = "", None
        for _ in range(2):
            raw, usage = self.model.run_structured(self.prompts.intake_system,
                                                   self._payload(state, latest, header, final, feedback), INTAKE_SCHEMA)
            self._add_usage(state, usage)
            if raw is None:
                feedback = "- The response was empty or not valid JSON."
                continue
            facts = {_field(f.get("field", "")): str(f.get("value", "")) for f in raw.get("facts_patch") or []
                     if isinstance(f, dict)}
            rep = inspect_intake({**raw, "facts": facts}, user_input=clinician_text)
            if rep.passed:
                out = raw
                break
            feedback = "\n".join(f"- [{f.code}] {f.message}" for f in rep.blocks)
        if out is None:
            # Two unusable responses: keep the state, ask a mandatory question or move to ready.
            if not self._next_mandatory(state):
                state["stage"], state["pending"] = INFORMATION_SUFFICIENT, None
            return
        self._apply(state, out, final)

    def _apply(self, state: dict, out: dict, final: bool) -> None:
        for f in out.get("facts_patch") or []:
            key, value = _field(f.get("field", "")), str(f.get("value", "")).strip()
            if not key or (key == "risk_screening" and state["safety_confirmed"]):
                continue  # the clinician's own safety confirmation is never overwritten by the model
            if not value or value.lower() in ("unknown", "don't know", "not known"):
                if key not in state["unknown"]:
                    state["unknown"].append(key)
                continue
            if key not in state["facts"] and len(state["facts"]) >= MAX_FACTS:
                continue
            state["facts"][key] = value[:300]
            if key in state["unknown"]:
                state["unknown"].remove(key)
        for name in out.get("unknown_fields") or []:
            key = _field(name)
            if key and key not in state["facts"] and key not in state["unknown"]:
                state["unknown"].append(key)
        if (out.get("case_summary") or "").strip():
            state["case_summary"] = out["case_summary"].strip()
        state["brief_answer"] = (out.get("brief_answer") or "").strip()

        status = out.get("status")
        if status == "risk_stop" and not state["safety_confirmed"]:
            self._safety_stop(state, "\n".join(t["answer"] or "" for t in state["transcript"][-1:]) or
                              state.get("case_text", ""))
            return
        question, key = (out.get("question") or "").strip(), _field(out.get("field") or "")
        asks_known = key in state["facts"] or key in state["unknown"]
        if status == "ask" and question and not final and not asks_known:
            self._ask(state, {"field": key or "detail", "question": question, "why": (out.get("why") or "").strip(),
                              "options": [str(o).strip() for o in (out.get("options") or []) if str(o).strip()][:4]})
            return
        if not self._next_mandatory(state):
            state["stage"], state["pending"] = INFORMATION_SUFFICIENT, None

    def _next_mandatory(self, state: dict) -> bool:
        """Ask the first missing mandatory field with the intake guide's own question. No model call."""
        for m in self.prompts.mandatory:
            if m["field"] not in state["facts"] and m["field"] not in state["unknown"]:
                self._ask(state, dict(m))
                return True
        return False

    def _ask(self, state: dict, q: dict) -> None:
        state["questions_asked"] += 1
        state["pending"], state["stage"] = q, QUESTIONING
        state["transcript"].append({**{k: q[k] for k in ("field", "question", "why")}, "answer": None})
        del state["transcript"][:-MAX_TRANSCRIPT]

    @staticmethod
    def _add_usage(state: dict, usage: dict) -> None:
        u = state["usage"]
        u["calls"] = u.get("calls", 0) + 1
        for k, v in (usage or {}).items():
            if isinstance(v, int):
                u[k] = u.get(k, 0) + v


def public_view(state: dict, conv_id: str) -> dict:
    """What the phone receives: small, no usage figures, no raw model output."""
    pending = state["pending"]
    return {
        "id": conv_id,
        "stage": state["stage"],
        "question": ({**pending, "number": state["questions_asked"]} if pending else None),
        "brief_answer": state.get("brief_answer", ""),
        "case_summary": state["case_summary"],
        "facts": state["facts"],
        "unknown": state["unknown"],
        "questions_asked": state["questions_asked"],
        "max_questions": MAX_QUESTIONS,
        "transcript": [t for t in state["transcript"] if t["answer"] is not None],
        "report": state.get("report"),
    }
