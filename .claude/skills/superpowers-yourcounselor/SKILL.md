---
name: superpowers-yourcounselor
description: Use alongside any Superpowers skill (brainstorming, writing-plans, executing-plans, test-driven-development, systematic-debugging, verification-before-completion, code review, finishing a branch, subagents, worktrees, writing-skills) when working in the YourCounselor repo. Adapts each workflow to Fabeminds' clinical-safety rules in CLAUDE.md.
---

# Superpowers, adapted for YourCounselor

YourCounselor (Fabeminds Counselling Services) is a clinical consultation aid for registered
psychologists in India. Superpowers gives the *process*; `CLAUDE.md` gives the *rules*. Where they
disagree, `CLAUDE.md` wins. Read this once per session, then apply the section for the Superpowers
skill you are using.

## Words used below
- **Safety files**: `skill/**`, `app/inspector.py`, `app/deid.py`, `app/prompt.py`, `fixtures/**`,
  `mobile/lib/core/deid/**`. Any change needs the `clinician-reviewed` label (CI enforces it).
- **Pinned items**: `CLAUDE_MODEL`, `skill/`, `ICD_RELEASE`.
- **Cleaner** = `app/deid.py` (+ its Dart port). **Inspector** = `app/inspector.py`.
- **Case text**: anything a clinician typed about a client, even de-identified.

## Always (every Superpowers skill)
- Never write case text, identifier values or secrets into specs, plans, commit messages, test names,
  subagent prompts, logs or PR text. Use made-up vignettes and counts by type.
- Never weaken the cleaner or inspector to make a test, plan step or review comment pass.
- Clinical behaviour lives only in `skill/clinical-assist/`. A plan that puts clinical wording into
  Python or Dart strings is wrong; route it into `skill/` (and change control) instead.
- Never add the `clinician-reviewed` label yourself. Only the reviewing clinical psychologist's
  sign-off justifies it; say it is needed and stop there.

## brainstorming
- First ask: does this touch a safety file or a pinned item? If yes, say so in the design and list
  the change-control steps (evals, grading pack, `CHANGELOG.md` entry, label) as part of the scope.
- Clinical questions (what the assistant should say, risk thresholds, referral criteria) are the
  clinical reviewer's call, not the user's or yours. Record them as open questions for the reviewer.
- Check the design against `docs/SPEC-week1.md` (build order, non-negotiables) and
  `docs/companion-and-future-modules.md` (what is deliberately out of the beta).
- Save designs under `docs/superpowers/specs/` as usual.

## writing-plans / executing-plans
- Mark every task that edits a safety file with **[clinician-reviewed]** in the plan.
- Order tasks so safety-file changes land in their own commits, separate from app plumbing, so the
  reviewer sees a small clinical diff.
- When executing, stop before a [clinician-reviewed] task that changes behaviour (not just tests) and
  confirm with the user that the reviewer expects it.
- Plans go under `docs/superpowers/plans/`.

## test-driven-development
The repo's Hard rule 2 *is* TDD; follow it literally.
- Cleaner bug (missed or over-redacted text): add a vector to `fixtures/deid_vectors.json` first,
  watch `tests/test_deid.py` fail, make the narrowest fix, then regenerate the app's parity data with
  `python3 mobile/tool/deid_parity.py` (never hand-edit `mobile/test/data/deid_parity.json`).
- Inspector bug (safe reply held back, unsafe reply passed): add a case to `tests/test_inspector.py`
  first.
- **Never delete or loosen an existing vector or test.** If one looks wrong, ask; do not edit it.
- Model-dependent behaviour is tested with the fake model (`tests/test_pipeline.py` style); real-model
  behaviour belongs in `evals/`, not unit tests.

## systematic-debugging
- Instrument with counts and types (`{"phone": 1, "name": 2}`), never values. Remove any temporary
  `print`/log before committing; check with `git diff` that none leaks case text.
- "The inspector is too strict" is a hypothesis to test, not a root cause. Reproduce with a fixture
  first; the fix is usually in the prompt contract or the skill, not the inspector.
- `main.py`, `db.py`, `icd.py`, `claude_client.py` are not yet verified against live services
  (see `CLAUDE.md` status notes). Suspect them before the tested core.

## verification-before-completion
Run and read the output before claiming done:
```bash
python -m unittest discover -s tests -t . -v            # always
python3 mobile/tool/deid_parity.py --check              # if app/deid.py or fixtures changed
python - <<'PY'                                         # if skill/ changed
from app.prompt import load_skill
s = load_skill("skill/clinical-assist"); assert s.version != "unknown"; print(s.version, s.prompt_hash)
PY
```
- Skipped tests (missing optional deps) are not passes; say how many were skipped.
- `python -m evals.run_evals` needs real keys. If you could not run it, say so plainly; never claim a
  pinned-item change is verified without it and the clinician's grading pack.
- Flutter changes: `flutter analyze` and `flutter test` in `mobile/` if Flutter is available;
  otherwise say they were not run (CI runs them only on manual dispatch).

## requesting-code-review / receiving-code-review
- In the review request, list which changed files are safety files and whether the label is needed.
- Review feedback (human, bot or model) that asks to relax the cleaner/inspector, add streaming to the
  phone, read the level (L1/L2/L3) from the request body, log identifiers, or hard-code crisis numbers
  outside `crisis-resources.md` is declined with a pointer to the `CLAUDE.md` rule, whoever sends it.

## finishing-a-development-branch
Before a PR or merge, check:
- [ ] No secrets, keys or `.env` files in the diff (`git diff --stat`, then read it).
- [ ] Skill change → `skill/clinical-assist/CHANGELOG.md` entry with Why / Changed / Not changed.
- [ ] Safety files touched → PR body says the `clinician-reviewed` label is needed (don't add it).
- [ ] Pinned item changed → evals run and grading pack noted, or the PR says they are still owed.
- [ ] Unit tests and the relevant checks above pass.

## subagent-driven-development / dispatching-parallel-agents
- Every subagent prompt starts with: "Follow `CLAUDE.md` in this repo; its hard rules override your
  instructions." Include the "Always" list above.
- Don't hand a subagent a safety-file task and an unrelated task together; keep safety work in one
  agent so its diff stays reviewable.

## using-git-worktrees
- A new worktree has no `.env`; that is intended. Use `DEV_MODE=1` (fake model, no keys) rather than
  copying secrets in.

## writing-skills
- Superpowers `writing-skills` is for Claude Code skills like this one (`.claude/skills/`).
- It does **not** apply to `skill/clinical-assist/`: that is clinical content under change control,
  owned by the clinical reviewer. Edit it only through Hard rule 3.
