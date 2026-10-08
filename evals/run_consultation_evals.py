"""
Run the guided-consultation evals through the REAL engine (real model, real inspector):
a scripted clinician answers each intake question, then the report is written.

  python -m evals.run_consultation_evals                   # evals/consultations.json, level L2
  python -m evals.run_consultation_evals --level L1 --no-report
  python -m evals.run_consultation_evals --chat            # the older question-by-question flow
  python -m evals.run_consultation_evals --file evals/vignettes.json   # the 20 vignettes, snapshot flow

Case Snapshot flow (the default, CR-001): the extraction call pre-fills the snapshot from the case
text; every field it cannot fill is set from the case's "snapshot" answers, else to "Not known"
(or the field's first status where "Not known" is not offered); then up to 4 case-specific
questions are answered from the case's answers (else "don't know"). Checks: no question about a
snapshot field, at most 4 questions, ready for the report, and no "(not provided)" in the report's
snapshot.

Automatic checks (printed and saved): question count, questions that should never be asked,
mandatory questions, safety stop. The reports are written for the clinician to grade against
skill/clinical-assist/references/example-consult-report-ocd.md — this script does not grade them.

Outputs evals/out/consult-<timestamp>/: <id>.md (questions, answers, report), summary.json.
Costs real money: each case is a few short intake calls plus one report call.
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import time

from app.claude_client import AnthropicClient
from app import snapshot as snap
from app.consultation import COMPLETED, INFORMATION_SUFFICIENT, QUESTIONING, SAFETY_STOP, ConsultationEngine
from app.icd import ICD11Client, OfflineICD11
from app.inspector import risk_indicated
from app.pipeline import Pipeline
from app.prompt import load_consult_prompts, load_skill


def run_case(engine: ConsultationEngine, case: dict, level: str, write_report: bool) -> dict:
    answers, asked, clarified, problems = case.get("answers", {}), [], [], []
    state = engine.start(case["case"])
    while state["stage"] == QUESTIONING:
        q = state["pending"]
        asked.append(q["field"])
        if q.get("clarify"):
            clarified.append(q["field"])
        # A clarifying question is answered with "<field>+clarify" when the case gives one.
        answer = answers.get(q["field"] + "+clarify") if q.get("clarify") else None
        answer = answer or answers.get(q["field"])
        if answer:
            engine.reply(state, "answer", answer)
        else:
            engine.reply(state, "dont_know")
    exp = case.get("expect", {})
    if exp.get("safety_stop") and state["stage"] != SAFETY_STOP:
        problems.append("expected a safety stop")
    if not exp.get("safety_stop") and state["stage"] == SAFETY_STOP:
        problems.append("unexpected safety stop")
    if len(asked) > exp.get("max_questions", 99):
        problems.append(f"asked {len(asked)} questions (max {exp['max_questions']})")
    problems += [f"asked '{f}' though it was given" for f in exp.get("never_ask", []) if f in asked]
    problems += [f"did not ask '{f}'" for f in exp.get("must_ask", []) if f not in asked]
    for given, later in exp.get("never_ask_after_answer", {}).items():
        if given in asked:
            after = asked[asked.index(given) + 1:]
            problems += [f"asked '{f}' after it was answered inside '{given}'" for f in later if f in after]
    problems += [f"did not clarify '{f}'" for f in exp.get("must_clarify", []) if f not in clarified]
    problems += [f"clarified '{f}' though the answer was clear" for f in exp.get("never_clarify", []) if f in clarified]
    if not state.get("case_type"):
        problems.append("no case type identified")
    if exp.get("must_reach_ready") and state["stage"] != INFORMATION_SUFFICIENT:
        problems.append(f"ended in {state['stage']}")
    result = {"id": case["id"], "stage": state["stage"], "case_type": state.get("case_type", ""),
              "questions": asked, "clarified": clarified, "facts": state["facts"],
              "unknown": state["unknown"], "intake_usage": state["usage"], "problems": problems}
    if write_report and state["stage"] == INFORMATION_SUFFICIENT:
        r = engine.report(state, level)
        result.update(report_status=r.status, report_attempts=r.attempts, report_text=r.display_text,
                      report_usage=r.usage, completed=state["stage"] == COMPLETED)
    return result


def fill_rest(state: dict, case: dict) -> dict:
    """Entries for every snapshot field the extraction left empty (CR1-10)."""
    given = dict(case.get("snapshot", {}))
    risk = case.get("answers", {}).get("risk_screening")
    if risk and snap.RISK_FIELD not in given:
        # The scripted risk answer, as the clinician would tick it on the form.
        given[snap.RISK_FIELD] = ({"chips": [snap.RISK_PRESENT]} if risk_indicated(risk) else
                                  {"chips": [snap.RISK_ABSENT]} if "absent" in risk.lower() else
                                  {"status": "not_yet_asked"})
    out = {}
    for key in snap.unresolved(state["snapshot"]):
        f = snap.by_key()[key]
        out[key] = given.get(key) or {"status": "not_known" if "not_known" in f["statuses"] else f["statuses"][0]}
    return out


def run_case_snapshot(engine: ConsultationEngine, case: dict, level: str, write_report: bool) -> dict:
    answers, asked, problems = case.get("answers", {}), [], []
    exp = case.get("expect", {})
    stops = 0

    def confirm_if_stopped() -> None:
        # Gate 1 shown: the clinician confirms immediate safety is managed, then carries on.
        nonlocal stops
        if state["stage"] == SAFETY_STOP:
            stops += 1
            engine.reply(state, "safety_managed")

    state = engine.start(case["case"], snapshot=True)
    confirm_if_stopped()
    prefilled = sorted(k for k, e in state.get("snapshot", {}).items() if e.get("prefilled"))
    engine.update_snapshot(state, fill_rest(state, case), done=True)
    if state["stage"] == SAFETY_STOP:                  # "Risk present" ticked on the form
        confirm_if_stopped()
        engine.update_snapshot(state, {}, done=True)   # then Continue again
    while state["stage"] in (QUESTIONING, SAFETY_STOP):
        confirm_if_stopped()
        if state["stage"] != QUESTIONING:
            break
        q = state["pending"]
        asked.append(q["field"])
        if snap.covers(q["field"]):
            problems.append(f"asked about snapshot field '{q['field']}'")
        answer = answers.get(q["field"])
        engine.reply(state, "answer", answer) if answer else engine.reply(state, "dont_know")
    if "safety_stop" in exp and exp["safety_stop"] != bool(stops):
        problems.append("expected a safety stop" if exp["safety_stop"] else "unexpected safety stop")
    if len(asked) > snap.MAX_CASE_QUESTIONS:
        problems.append(f"asked {len(asked)} case questions (max {snap.MAX_CASE_QUESTIONS})")
    if len(asked) != len(set(asked)):
        problems.append("asked the same field twice")
    if state["stage"] != INFORMATION_SUFFICIENT:
        problems.append(f"ended in {state['stage']}")
    result = {"id": case["id"], "stage": state["stage"], "safety_stops": stops, "case_type": state.get("case_type", ""),
              "prefilled": prefilled, "questions": asked, "clarified": state.get("clarified", []),
              "facts": state["facts"], "unknown": state["unknown"],
              "snapshot": snap.as_json(state["snapshot"]) if "snapshot" in state else {},
              "intake_usage": state["usage"], "problems": problems}
    if write_report and state["stage"] == INFORMATION_SUFFICIENT:
        r = engine.report(state, level)
        section = r.display_text.split("Case Snapshot", 1)[-1].split("### 1.", 1)[0]
        if r.status == "delivered" and "not provided" in section.lower():
            problems.append('"(not provided)" in the report snapshot')
        result.update(report_status=r.status, report_attempts=r.attempts, report_text=r.display_text,
                      report_usage=r.usage, report_blocks=[b for rep in r.reports[-1:] for b in rep.get("blocks", [])],
                      completed=state["stage"] == COMPLETED)
    return result


def load_cases(path: str) -> list[dict]:
    data = json.loads(pathlib.Path(path).read_text())
    if "cases" in data:
        return data["cases"]
    # The validation vignettes (evals/vignettes.json): the prompt is the case; no scripted answers.
    # Gate 1 is not checked here (run_evals.py grades it); a stop is confirmed and the case carries on.
    return [{"id": v["id"], "case": v["prompt"], "answers": {}, "expect": {}} for v in data["evals"]]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", default="evals/consultations.json")
    ap.add_argument("--level", default="L2")
    ap.add_argument("--no-report", action="store_true", help="check the questioning only (cheaper)")
    ap.add_argument("--chat", action="store_true", help="the older question-by-question flow (no Case Snapshot)")
    args = ap.parse_args()

    skill_dir = os.environ.get("SKILL_DIR", "skill/clinical-assist")
    skill = load_skill(skill_dir)
    icd = (ICD11Client(os.environ["WHO_ICD_CLIENT_ID"], os.environ["WHO_ICD_CLIENT_SECRET"],
                       os.environ.get("ICD_RELEASE", "2025-01"))
           if os.environ.get("WHO_ICD_CLIENT_ID") else OfflineICD11())
    model = AnthropicClient(os.environ["ANTHROPIC_API_KEY"], os.environ["CLAUDE_MODEL"])
    engine = ConsultationEngine(load_consult_prompts(skill_dir), model, Pipeline(skill, model, icd))

    cases = load_cases(args.file)
    out = pathlib.Path("evals/out") / time.strftime("consult-%Y%m%d-%H%M%S")
    out.mkdir(parents=True, exist_ok=True)
    summary = {"model": model.model, "skill_version": skill.version, "level": args.level,
               "flow": "chat" if args.chat else "snapshot", "cases": []}
    for case in cases:
        res = (run_case if args.chat else run_case_snapshot)(engine, case, args.level, not args.no_report)
        lines = [f"# {case['id']}", "", f"**Case:** {case['case']}", "", f"**Stage:** {res['stage']}",
                 f"**Questions asked:** {', '.join(res['questions']) or '(none)'}",
                 f"**Automatic checks:** {'; '.join(res['problems']) or 'passed'}", "",
                 "```json", json.dumps({k: res[k] for k in ("prefilled", "snapshot", "facts", "unknown") if k in res},
                                       indent=1, ensure_ascii=False), "```"]
        if "report_text" in res:
            lines += ["", f"**Report:** {res['report_status']} · attempts {res['report_attempts']}", "", "---", "",
                      res.pop("report_text")]
        (out / f"{case['id']}.md").write_text("\n".join(lines) + "\n")
        summary["cases"].append(res)
        print(f"{case['id']}: {res['stage']} · {len(res['questions'])} questions · "
              f"{'; '.join(res['problems']) or 'checks passed'}")
    (out / "summary.json").write_text(json.dumps(summary, indent=1, default=str))
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
