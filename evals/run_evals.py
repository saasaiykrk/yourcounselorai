"""
Run the eval suite through the REAL pipeline (real model, real inspector) and
write a grading pack for the clinician.

  python -m evals.run_evals                      # evals/evals.json
  python -m evals.run_evals --file evals/vignettes.json --level L2

Outputs evals/out/<timestamp>/:
  <id>.md          the reply exactly as the clinician would see it (+ inspector report)
  grading.csv      one row per assertion: id, assertion, PASS/FAIL (clinician fills in), notes
  summary.json     model, skill version, prompt hash, inspector pass rate, attempts, latency

Run it: before every deploy that changes the model, the skill, or the inspector;
and weekly during beta. Pass bar (Phase 2): 100% on safety cases, no invented
codes, leading consideration sound — graded by the clinician, not by this script.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import pathlib
import time

from app.icd import ICD11Client, OfflineICD11
from app.pipeline import DeidRejected, Pipeline
from app.prompt import load_skill
from evals.models import model_from_env


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", default="evals/evals.json")
    ap.add_argument("--level", default="L2")
    ap.add_argument("--provider", choices=("anthropic", "gemini"), default="anthropic",
                    help="which AI writes the replies (gemini: for side-by-side comparison)")
    args = ap.parse_args()

    skill = load_skill(os.environ.get("SKILL_DIR", "skill/clinical-assist"))
    icd = (ICD11Client(os.environ["WHO_ICD_CLIENT_ID"], os.environ["WHO_ICD_CLIENT_SECRET"],
                       os.environ.get("ICD_RELEASE", "2025-01"))
           if os.environ.get("WHO_ICD_CLIENT_ID") else OfflineICD11())
    model = model_from_env(args.provider)
    pipe = Pipeline(skill, model, icd)

    cases = json.loads(pathlib.Path(args.file).read_text())["evals"]
    out = pathlib.Path("evals/out") / time.strftime("%Y%m%d-%H%M%S")
    out.mkdir(parents=True, exist_ok=True)
    rows, summary = [], {"model": model.model, "skill_version": skill.version, "prompt_hash": skill.prompt_hash,
                         "level": args.level, "cases": []}
    for case in cases:
        level = case.get("level", args.level)
        try:
            r = pipe.run(case["prompt"], level=level, requested_mode=case.get("mode", "auto"))
        except DeidRejected as e:
            summary["cases"].append({"id": case["id"], "status": "deid_rejected", "types": sorted(e.counts)})
            continue
        except Exception as e:  # noqa: BLE001 - e.g. the provider's quota: record it, keep the other cases
            summary["cases"].append({"id": case["id"], "status": "error", "error": str(e)[:300]})
            print(f"{case['id']}: ERROR {str(e)[:200]}")
            continue
        (out / f"{case['id']}.md").write_text(
            f"# Case {case['id']}\n\n**Prompt:** {case['prompt']}\n\n**Expected:** {case.get('expected_output','')}\n\n"
            f"**Status:** {r.status} · attempts {r.attempts} · {r.latency_ms} ms\n\n---\n\n{r.display_text}\n\n---\n\n"
            f"```json\n{json.dumps(r.reports, indent=1)}\n```\n")
        for a in case.get("assertions", []):
            rows.append([case["id"], case.get("category", ""), "YES" if case.get("safety_case") else "", a, "", ""])
        summary["cases"].append({"id": case["id"], "status": r.status, "attempts": r.attempts,
                                 "latency_ms": r.latency_ms, "inspector_first_pass": r.reports[0]["passed"]})
    with open(out / "grading.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["case_id", "category", "safety_case", "assertion", "PASS/FAIL (clinician)", "notes"])
        w.writerows(rows)
    done = [c for c in summary["cases"] if c.get("status") == "delivered"]
    summary["delivered_rate"] = round(len(done) / max(1, len(summary["cases"])), 3)
    (out / "summary.json").write_text(json.dumps(summary, indent=1))
    print(f"Wrote {out}  delivered {len(done)}/{len(summary['cases'])}")
    if cases and all(c.get("status") == "error" for c in summary["cases"]):
        raise SystemExit("No case could run (see the errors above).")


if __name__ == "__main__":
    main()
