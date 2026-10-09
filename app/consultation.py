"""
Guided consultation: a short, case-specific intake (one question at a time), then the
fixed Consultation Report (Mode R).

  start(case) ─► identify the case type and what the report still needs (info_needed)
              ─► next question │ clarifying question │ ready │ safety stop
  answer │ don't know │ skip ─► intake call ─► …   (an unclear or contradictory answer gets
                                                    one clarifying question per field)
  report ─► the existing Pipeline with "Requested mode: R" (cleaner, inspector, retry, hold-back)

Token rules
  * An intake call sends only the small intake prompt, the COMPACT STATE (summary, facts,
    unknowns, question count) and the latest question + reply. Never the raw conversation,
    never the skill or the report template.
  * The report is one call: the cached skill prompt + the report template part + the compact
    case built from the state (case type, summary, facts, and the short questions and answers).
  * Stage changes, "don't know", fact edits, the question cap and the mandatory-field
    questions (taken from the intake guide) need no model call.

Safety
  * Every clinician text is re-checked by the cleaner; risk phrases stop the intake and the
    app shows the crisis pathway until the clinician confirms safety.
  * Every intake response passes inspect_intake() before any of it is stored or shown;
    the report passes the full inspector.

Case Snapshot mode (CR-001, when the app asks for it at start)
  start(case) ─► extraction call pre-fills the snapshot ─► INITIAL_CASE: the clinician completes
  every snapshot field (value or status) ─► at most 4 case-specific questions, never about a
  snapshot field ─► report with the snapshot JSON; the app's snapshot table replaces the model's.

No web or database code: tests/test_consultation.py runs it with a fake model.
"""
from __future__ import annotations

import json
import re
from typing import Protocol

from . import deid
from . import snapshot as snap
from .inspector import SAFETY_MANAGED_RE, inspect_intake, risk_indicated
from .pipeline import DeidRejected, Pipeline, TurnResult
from .prompt import INTAKE_SCHEMA, ConsultPrompts

INITIAL_CASE = "INITIAL_CASE"
QUESTIONING = "QUESTIONING"
INFORMATION_SUFFICIENT = "INFORMATION_SUFFICIENT"
REPORT_GENERATION = "REPORT_GENERATION"
COMPLETED = "COMPLETED"
SAFETY_STOP = "SAFETY_STOP"
# Case Snapshot mode: the case is in and the clinician is completing the snapshot form. It keeps the
# INITIAL_CASE name, which the database already allows.
SNAPSHOT = INITIAL_CASE
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
    return {"stage": INITIAL_CASE, "case_type": "", "case_summary": "", "facts": {}, "unknown": [],
            "info_needed": [], "clarified": [], "pending": None,
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


def _prune_needed(state: dict) -> None:
    """The plan lists only what is still missing: no known or unknown fields, no repeats."""
    seen, out = set(state["facts"]) | set(state["unknown"]), []
    for key in state.get("info_needed", []):
        if key and key not in seen:
            seen.add(key)
            out.append(key)
    state["info_needed"] = out[:12]


def _risky(text: str) -> bool:
    return risk_indicated(text) and not SAFETY_MANAGED_RE.search(text)


class ConsultationEngine:
    def __init__(self, prompts: ConsultPrompts, model: IntakeModel, pipeline: Pipeline,
                 max_questions: int = MAX_QUESTIONS):
        self.prompts, self.model, self.pipeline, self.max_questions = prompts, model, pipeline, max_questions

    # --- public steps ---------------------------------------------------------------
    def start(self, text: str, snapshot: bool = False) -> dict:
        state = new_state()
        text = _clean_or_raise(text)
        state["case_text"] = text
        if snapshot:
            state["snapshot"], state["max_questions"] = snap.empty(), snap.MAX_CASE_QUESTIONS
        if _risky(text):
            return self._safety_stop(state, text)
        if snapshot:
            self._extract(state)
            return state
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
            _prune_needed(state)
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

    def update_snapshot(self, state: dict, patch: dict[str, dict | None], done: bool = False,
                        skip_remaining: bool = False) -> dict:
        """The clinician fills or corrects Case Snapshot fields. No model call, except the first
        case-specific question once the form is complete. Editing after the report reopens the
        consultation so the report can be updated."""
        if "snapshot" not in state:
            raise ConsultationError(409, "this consultation has no case snapshot")
        stage = state["stage"]
        if stage not in (SNAPSHOT, QUESTIONING, INFORMATION_SUFFICIENT, COMPLETED):
            raise ConsultationError(409, f"consultation is {stage.lower()}")
        try:
            entries = {key: snap.validate(key, raw) for key, raw in patch.items()}
        except snap.SnapshotError as e:
            raise ConsultationError(e.status, e.detail)
        risk_before = state["snapshot"][snap.RISK_FIELD].get("chips")
        for key, entry in entries.items():
            old = state["snapshot"].get(key) or {}
            if old.get("optional"):
                entry["optional"] = True                  # filled or emptied, it stays an optional field
            if old.get("prefilled") and old.get("chips") == entry["chips"] and old.get("text") == entry["text"] \
                    and not entry["status"]:
                entry["prefilled"] = True                 # unchanged prefill keeps its tick
            state["snapshot"][key] = entry
        risk = state["snapshot"][snap.RISK_FIELD]
        if snap.RISK_PRESENT in risk["chips"] and (risk_before != risk["chips"] or not state["safety_confirmed"]):
            # Gate 1 straight away: the emergency guidance comes before the rest of the form.
            state["safety_confirmed"], state["safety_return"] = False, stage
            return self._safety_stop(state, "")
        if stage == COMPLETED and entries:
            state["stage"] = INFORMATION_SUFFICIENT          # the report can now be updated
        if skip_remaining:
            for key in snap.unresolved(state["snapshot"]):
                state["snapshot"][key] = {"chips": [], "text": "", "status": "skipped", "prefilled": False}
        if (done or skip_remaining) and state["stage"] == SNAPSHOT:
            missing = snap.unresolved(state["snapshot"])
            if missing:
                raise ConsultationError(409, "every snapshot field needs a value or a status: " + ", ".join(missing))
            if skip_remaining:
                state["stage"], state["pending"] = INFORMATION_SUFFICIENT, None
            else:
                self._intake(state, "The clinician has completed the Case Snapshot.",
                             header="[Case Snapshot completed]")
        return state

    def _extract(self, state: dict) -> None:
        """Pre-fills the snapshot from the case text (never shown as a report). Every value is
        inspected before it is stored; an unusable response leaves the form empty."""
        for _ in range(2):
            raw, usage = self.model.run_structured(snap.extraction_system(), state["case_text"],
                                                   snap.extraction_schema())
            self._add_usage(state, usage)
            if not isinstance(raw, dict):
                continue
            entries = {}
            for f in raw.get("fields") or []:
                if isinstance(f, dict) and f.get("key") not in entries:
                    e = snap.from_extraction(str(f.get("key", "")), str(f.get("value", "")))
                    if e:
                        entries[f["key"]] = e
            out = {"case_type": str(raw.get("case_type") or ""), "case_summary": str(raw.get("case_summary") or ""),
                   "facts": {k: snap.display_value(e) for k, e in entries.items()}}
            if not inspect_intake(out, user_input=state["case_text"]).passed:
                continue
            state["snapshot"].update(entries)
            # The case check: ask only what this case needs (an unusable response asks everything).
            snap.mark_needed(state["snapshot"], [str(k) for k in raw.get("relevant") or []])
            state["case_type"] = out["case_type"].strip()[:80]
            state["case_summary"] = out["case_summary"].strip()
            break
        state["stage"], state["pending"] = SNAPSHOT, None

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
        _prune_needed(state)
        return state

    def case_text(self, state: dict) -> str:
        """The compact case the report is written from (no raw conversation)."""
        if "snapshot" in state:
            return self._snapshot_case_text(state)
        lines = ["[Guided consultation — case collected by the app]"]
        if state.get("case_type"):
            lines.append(f"Case type (as identified): {state['case_type']}")
        lines += [f"Case summary: {state['case_summary'] or '(not provided)'}", "",
                  "Facts provided by the clinician:"]
        lines += [f"- {k}: {v}" for k, v in state["facts"].items()] or ["- (none)"]
        answered = [t for t in state["transcript"] if t["answer"] is not None]
        if answered:
            lines += ["", "Consultation questions and answers:"]
            for t in answered:
                lines += ([f"Q: {t['question']}", f"A: {t['answer']}"] if t["question"]
                          else [f"Additional information: {t['answer']}"])
        if state["unknown"]:
            lines += ["", "Not known to the clinician: " + ", ".join(state["unknown"])]
        missing = [m["field"] for m in self.prompts.mandatory
                   if m["field"] not in state["facts"] and m["field"] not in state["unknown"]]
        if missing:
            lines += ["", "Not asked (report as not provided): " + ", ".join(missing)]
        return "\n".join(lines)

    def _snapshot_case_text(self, state: dict) -> str:
        lines = ["[Guided consultation — case collected by the app]"]
        if state.get("case_type"):
            lines.append(f"Case type (as identified): {state['case_type']}")
        lines += ["<case_snapshot>", json.dumps(snap.as_json(state["snapshot"]), ensure_ascii=False), "</case_snapshot>",
                  "<case_text>", state.get("case_text", ""), "</case_text>"]
        if state["facts"]:
            lines += ["", "Further facts from the case-specific questions:"]
            lines += [f"- {k}: {v}" for k, v in state["facts"].items()]
        answered = [t for t in state["transcript"] if t["answer"] is not None]
        if answered:
            lines += ["", "Case-specific questions and answers:"]
            for t in answered:
                lines += ([f"Q: {t['question']}", f"A: {t['answer']}"] if t["question"]
                          else [f"Additional information: {t['answer']}"])
        if state["unknown"]:
            lines += ["", "Not known to the clinician: " + ", ".join(state["unknown"])]
        lines += ["", snap.REPORT_NOTE]
        return "\n".join(lines)

    def report(self, state: dict, level: str, force: bool = False, today: str | None = None,
               pipeline=None) -> TurnResult:
        """pipeline: a different model's pipeline for this one report (the clinician's own key)."""
        stage = state["stage"]
        if "snapshot" in state and stage == SNAPSHOT:
            raise ConsultationError(409, "complete the Case Snapshot first")
        if stage == QUESTIONING and force and (state["facts"] or state["case_summary"]):
            state["stage"] = stage = INFORMATION_SUFFICIENT
        if stage != INFORMATION_SUFFICIENT:
            raise ConsultationError(409, "more information is needed before the report" if stage == QUESTIONING
                                    else f"consultation is {stage.lower()}")
        state["stage"], state["pending"] = REPORT_GENERATION, None
        try:
            snapshot = state.get("snapshot")
            r = (pipeline or self.pipeline).run(self.case_text(state), level=level, requested_mode="R", today=today,
                                  extra_system=self.prompts.report_addendum,
                                  prompt_hash=f"{self.pipeline.skill.prompt_hash}+{self.prompts.prompt_hash}",
                                  postprocess=(lambda text: snap.apply_table(text, snapshot)) if snapshot else None)
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
        if "snapshot" in state:
            return self._confirm_safety_snapshot(state, action)
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

    def _confirm_safety_snapshot(self, state: dict, action: str) -> dict:
        """Snapshot mode: the clinician's confirmation is the risk-screening field. Back to where
        the safety stop came from — the form, or the case-specific questions."""
        managed = action == "safety_managed"
        risk = {"chips": [snap.RISK_PRESENT if managed else snap.RISK_ABSENT],
                "text": snap.RISK_MANAGED_NOTE if managed else "", "status": None, "prefilled": False}
        state["safety_confirmed"] = True
        back = state.pop("safety_return", None)
        pending_input, state["pending_input"] = state["pending_input"], ""
        if back is None and not state["case_summary"] and not state["transcript"]:
            self._extract(state)                      # the case itself stopped at Gate 1: now pre-fill the form
            state["snapshot"][snap.RISK_FIELD] = risk
            return state
        state["snapshot"][snap.RISK_FIELD] = risk
        if back in (SNAPSHOT, INFORMATION_SUFFICIENT, COMPLETED):
            state["stage"] = INFORMATION_SUFFICIENT if back == COMPLETED else back
            return state
        # From a case-specific answer: carry on with the questions.
        state["stage"] = QUESTIONING
        note = ("[App note] The clinician has confirmed: " + (RISK_MANAGED if managed else RISK_ABSENT) +
                ". Record the other facts; do not return risk_stop for this message.")
        self._intake(state, f"{pending_input}\n\n{note}", header="[Clinician's message]")
        return state

    def _record_answer(self, state: dict, answer: str) -> None:
        if state["transcript"] and state["transcript"][-1]["answer"] is None:
            state["transcript"][-1]["answer"] = answer

    def _payload(self, state: dict, latest: str, header: str, final: bool, feedback: str = "") -> str:
        compact = {"case_type": state.get("case_type", ""), "case_summary": state["case_summary"],
                   "facts": state["facts"], "unknown": state["unknown"], "info_needed": state.get("info_needed", []),
                   "clarified": state.get("clarified", []), "questions_asked": state["questions_asked"],
                   "max_questions": self._max(state)}
        if "snapshot" in state:
            compact["case_snapshot"] = snap.as_json(state["snapshot"])
        parts = ["[Consultation state]", json.dumps(compact, ensure_ascii=False, separators=(",", ":")), "",
                 header, "[Clinician's message]", latest]
        if "snapshot" in state and not final:
            parts += ["", "[App note] The clinician has completed the Case Snapshot (case_snapshot in the state). Ask only "
                          "case-specific questions it does not cover — never about a snapshot field or anything already "
                          "answered — most decision-changing first, at most " + str(self._max(state)) + " in all. "
                          "Return \"ready\" when nothing else would change the plan."]
        if final:
            parts += ["", "[App note] The question limit is reached: record the facts and return status \"ready\"."]
        if feedback:
            parts += ["", "[App note] Your previous response failed the app's checks. Return corrected JSON:", feedback]
        return "\n".join(parts)

    def _max(self, state: dict) -> int:
        return state.get("max_questions") or self.max_questions

    def _duplicate(self, state: dict, raw: dict) -> str:
        """Snapshot mode: a question about a snapshot field (or one already answered) is dropped."""
        if "snapshot" not in state or raw.get("status") not in ("ask", "clarify") or not (raw.get("question") or "").strip():
            return ""
        key = _field(raw.get("field") or "")
        covered = snap.covers(key)
        if covered:
            return f"- [DUPLICATE] '{key}' is in the Case Snapshot ({covered}); ask something else or return \"ready\"."
        if raw.get("status") == "ask" and (key in state["facts"] or key in state["unknown"]
                                           or any(t["field"] == key for t in state["transcript"])):
            return f"- [DUPLICATE] '{key}' was already asked or answered; ask something else or return \"ready\"."
        return ""

    def _intake(self, state: dict, latest: str, header: str) -> None:
        final = state["questions_asked"] >= self._max(state)
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
            duplicate = self._duplicate(state, raw)
            if rep.passed and not duplicate:
                out = raw
                break
            feedback = "\n".join([f"- [{f.code}] {f.message}" for f in rep.blocks] + ([duplicate] if duplicate else []))
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
            if "snapshot" in state and snap.covers(key):
                continue  # the snapshot the clinician completed is the record for these fields
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
            if "snapshot" in state and snap.covers(key):
                continue
            if key and key not in state["facts"] and key not in state["unknown"]:
                state["unknown"].append(key)
        if (out.get("case_summary") or "").strip():
            state["case_summary"] = out["case_summary"].strip()
        if (out.get("case_type") or "").strip():
            state["case_type"] = out["case_type"].strip()[:80]
        if "info_needed" in out:
            state["info_needed"] = [_field(n) for n in out.get("info_needed") or []]
        _prune_needed(state)
        state["brief_answer"] = (out.get("brief_answer") or "").strip()

        status = out.get("status")
        if status == "risk_stop" and not state["safety_confirmed"]:
            self._safety_stop(state, "\n".join(t["answer"] or "" for t in state["transcript"][-1:]) or
                              state.get("case_text", ""))
            return
        question, key = (out.get("question") or "").strip(), _field(out.get("field") or "")
        asks_known = key in state["facts"] or key in state["unknown"]
        clarified = state.setdefault("clarified", [])          # absent in states saved before clarify existed
        clarify = status == "clarify" and key and key not in clarified
        if question and not final and ((status == "ask" and not asks_known) or clarify):
            if clarify:
                clarified.append(key)
            self._ask(state, {"field": key or "detail", "question": question, "why": (out.get("why") or "").strip(),
                              "options": [str(o).strip() for o in (out.get("options") or []) if str(o).strip()][:4],
                              "clarify": bool(clarify)})
            return
        if not self._next_mandatory(state):
            state["stage"], state["pending"] = INFORMATION_SUFFICIENT, None

    def _next_mandatory(self, state: dict) -> bool:
        """Ask the first missing mandatory field with the intake guide's own question. No model call.
        In snapshot mode the completed snapshot already holds every mandatory field."""
        if "snapshot" in state:
            return False
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
        "question": ({"clarify": False, **pending, "number": state["questions_asked"]} if pending else None),
        "brief_answer": state.get("brief_answer", ""),
        "case_type": state.get("case_type", ""),
        "case_summary": state["case_summary"],
        "facts": state["facts"],
        "unknown": state["unknown"],
        "info_needed": state.get("info_needed", []),
        "questions_asked": state["questions_asked"],
        "max_questions": state.get("max_questions") or MAX_QUESTIONS,
        "transcript": [t for t in state["transcript"] if t["answer"] is not None],
        "report": state.get("report"),
        "snapshot": snap.public(state["snapshot"]) if "snapshot" in state else None,
    }
