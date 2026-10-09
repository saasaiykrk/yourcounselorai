"""
Checks every ICD-11 code the knowledge base (skill/) mentions against WHO's own record in the
pinned release (ICD_RELEASE), and prints WHO's official title for each.

    WHO_ICD_CLIENT_ID=… WHO_ICD_CLIENT_SECRET=… python -m evals.verify_icd_codes [extra codes…]

Needs the WHO keys (https://icd.who.int/icdapi) and internet access; CI runs it on demand
(Actions → ci → Run workflow → verify_icd). ICD-10-CM F-codes and NICE guideline ids are listed
but not checked: the WHO ICD-11 service does not hold them. Exit code 1 if any code is not found.
No case text is involved: codes and titles only.
"""
from __future__ import annotations

import os
import pathlib
import sys

from app.icd import ICD11Client
from app.inspector import ICD_CODE_RE, NICE_ID_BEFORE_RE

SKILL = pathlib.Path("skill")


def codes_in_skill() -> dict[str, set[str]]:
    """code → the skill files that mention it (ICD-11 codes only)."""
    found: dict[str, set[str]] = {}
    for p in sorted(SKILL.rglob("*.md")):
        text = p.read_text(errors="ignore")
        for m in ICD_CODE_RE.finditer(text):
            code = m.group(0)
            if code.startswith("F") or NICE_ID_BEFORE_RE.search(text[max(0, m.start() - 20):m.start()]):
                continue
            found.setdefault(code, set()).add(str(p.relative_to(SKILL)))
    return found


def main(argv: list[str]) -> int:
    cid, secret = os.environ.get("WHO_ICD_CLIENT_ID", ""), os.environ.get("WHO_ICD_CLIENT_SECRET", "")
    release = os.environ.get("ICD_RELEASE") or "2025-01"   # pinned (app/secrets.py)
    if not (cid and secret):
        print("WHO_ICD_CLIENT_ID / WHO_ICD_CLIENT_SECRET are not set: nothing was checked.")
        return 2
    who = ICD11Client(cid, secret, release)
    codes = codes_in_skill()
    for extra in argv:
        codes.setdefault(extra, set()).add("(asked to check)")
    lines = [f"## ICD-11 codes in skill/ checked against WHO (release {release})", "",
             "| Code | WHO title | Found | Where |", "| --- | --- | --- | --- |"]
    missing = []
    for code in sorted(codes):
        info = who.code_info(code.replace(".x", ""))
        if info is None:
            missing.append(code)
        lines.append(f"| {code} | {info['title'] if info else '—'} | {'yes' if info else '**NO**'} | "
                     f"{', '.join(sorted(codes[code]))} |")
    lines += ["", f"{len(codes) - len(missing)} of {len(codes)} found." +
              (f" Not found: {', '.join(missing)}." if missing else "")]
    report = "\n".join(lines)
    print(report)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
            f.write(report + "\n")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
