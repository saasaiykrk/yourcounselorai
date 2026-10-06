"""
Run the guided-consultation evals through the REAL engine (real model, real inspector):
a scripted clinician answers each intake question, then the report is written.

  python -m evals.run_consultation_evals                   # evals/consultations.json, level L2
  python -m evals.run_consultation_evals --level L1 --no-report

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
from app.consultation import COMPLETED, INFORMATION_SUFFICIENT, QUESTIONING, SAFETY_STOP, ConsultationEngine
from app.icd import ICD11Client, OfflineICD11
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


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", default="evals/consultations.json")
    ap.add_argument("--level", default="L2")
    ap.add_argument("--no-report", action="store_true", help="check the questioning only (cheaper)")
    args = ap.parse_args()

    skill_dir = os.environ.get("SKILL_DIR", "skill/clinical-assist")
    skill = load_skill(skill_dir)
    icd = (ICD11Client(os.environ["WHO_ICD_CLIENT_ID"], os.environ["WHO_ICD_CLIENT_SECRET"],
                       os.environ.get("ICD_RELEASE", "2025-01"))
           if os.environ.get("WHO_ICD_CLIENT_ID") else OfflineICD11())
    model = AnthropicClient(os.environ["ANTHROPIC_API_KEY"], os.environ["CLAUDE_MODEL"])
    engine = ConsultationEngine(load_consult_prompts(skill_dir), model, Pipeline(skill, model, icd))

    cases = json.loads(pathlib.Path(args.file).read_text())["cases"]
    out = pathlib.Path("evals/out") / time.strftime("consult-%Y%m%d-%H%M%S")
    out.mkdir(parents=True, exist_ok=True)
    summary = {"model": model.model, "skill_version": skill.version, "level": args.level, "cases": []}
    for case in cases:
        res = run_case(engine, case, args.level, not args.no_report)
        lines = [f"# {case['id']}", "", f"**Case:** {case['case']}", "", f"**Stage:** {res['stage']}",
                 f"**Questions asked:** {', '.join(res['questions']) or '(none)'}",
                 f"**Automatic checks:** {'; '.join(res['problems']) or 'passed'}", "",
                 "```json", json.dumps({"facts": res["facts"], "unknown": res["unknown"]}, indent=1), "```"]
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
