# YourCounselor — developer hand-off pack

Backend, safety core, clinical knowledge base, test cases, and a local test console for the YourCounselor Android beta — a **reference and documentation aid for qualified mental-health professionals**, built on the `clinical-assist` v2.1.1 skill.

**Stack: hybrid.** The safety-critical backend is **Python/FastAPI** (the cleaner and inspector are written and covered by tests). A thin **Node/HTML** console (`harness/`) is a local developer convenience only — the real app is Android talking to the Python backend directly.

## Phone app
The Flutter app for Android and iPhone lives in [`mobile/`](mobile/README.md). It is currently a design build with sample data, not yet connected to this backend.

## Read in this order
1. **`BRIEF.md`** — one page, non-technical. Give this to a business stakeholder.
2. **`docs/SPEC-week1.md`** — the Week 1 build spec (what to build, in what order, with done-criteria).
3. **`docs/product-mode-instructions.md`** — how the assistant behaves (modes, gates, rules).
4. **`docs/generation-plan.md`** — how one reply is produced end to end.
5. **`docs/companion-and-future-modules.md`** — what's in the beta and what's deliberately later.
6. **`CLAUDE.md`** — standing rules for anyone (including Claude Code) working in this repo.

## The example handover's files, mapped onto this repo
The JS handover shape you referenced maps onto the tested Python core like this:

| Example file | Here | What it does | Status |
|---|---|---|---|
| `extract.js` | `app/deid.py` | de-identification "cleaner" | ✅ tested |
| `qa.js` | `app/inspector.py` | pre-send safety checks (qc-checklist.md) | ✅ tested |
| `prompt.js` | `app/prompt.py` | build system prompt from the pinned skill + `get_card` | ✅ tested |
| `generate.js` | `app/pipeline.py` | clean → Claude+tools → inspect → retry once → deliver/hold | ✅ tested (fake model) |
| `keyvault.js` | `app/secrets.py` | the one place secrets are read; nothing logged | ✅ syntax-checked |
| `server.js` | `app/main.py` | FastAPI routes (the real server) | ⚠ run live Days 2–4 |
| `server.js` (dev) | `harness/server.js` | Node dev proxy for the console (no secrets) | Node 18 stdlib |
| `index.html` | `harness/index.html` | browser test console | static |
| `package.json` | `package.json` (harness) + `requirements.txt` (backend) | deps | — |
| `intake-schema.json` | `schema/intake-schema.json` | DSM-5-informed structured intake + what may reach the AI | — |
| `.env.example` | `.env.example` | config template | — |

Also: `app/claude_client.py` (Anthropic tool loop) ⚠ run live Day 2 · `app/icd.py` (WHO ICD-11) ⚠ run live Day 3 · `app/db.py` + `db/schema.sql` (Supabase, RLS on) ⚠ Days 2–4.

## Run the tests (no keys, no internet needed)
```bash
python -m unittest discover -s tests -t .      # 43 tests, Python 3.11 stdlib only
```

## Try it locally (keyless smoke test)
```bash
pip install -r requirements.txt
DEV_MODE=1 uvicorn app.main:app --port 8000    # fake model, dev token, no DB
node harness/server.js                          # open http://localhost:5173
```
`DEV_MODE=1` with no `ANTHROPIC_API_KEY` uses a canned reply so you can test the plumbing (cleaner preview, inspector report, the consult round-trip) before wiring real keys. Set a real key to use the actual model. **`DEV_MODE` must be off in production.**

## Run the clinical evals (real model; needs keys)
```bash
python -m evals.run_evals --file evals/vignettes.json   # 20 cases → grading pack for the clinician
```

## The two things that keep this safe
- **`skill/clinical-assist/` is the source of truth for clinical behaviour.** Don't put clinical rules in code.
- **Change control:** model, skill and ICD release are pinned. Changing any of them, or the safety files, needs the eval run + clinician review + a `CHANGELOG.md` entry + the `clinician-reviewed` PR label (CI enforces the label). See `CLAUDE.md`.
