# Generation plan

How one consult reply is produced, from the clinician tapping **Send** to the reply appearing. This is the runtime contract for `app/pipeline.py`. Read it with `docs/SPEC-week1.md` (the build plan) and `product-mode-instructions.md` (the behaviour).

## The pipeline, step by step

```
clinician text (cleaned on the phone)
  │
  ▼  1. cleaner re-check (app/deid.py)  ── found anything ──▶  422 identifiers_detected  (log types only)
  │
  ▼  2. build prompt (app/prompt.py): cached system prompt (skill + app contract) + app header (level, mode, date) + text
  │
  ▼  3. Claude call (app/claude_client.py)  ⇄  tools:
  │        • get_card(card_id)      → one Core 1–6 card, on demand
  │        • icd11_lookup(query)    → WHO ICD-11 MMS, pinned release; only returned codes may be shown
  │
  ▼  4. inspector (app/inspector.py) runs qc-checklist.md
  │        pass ──▶ deliver
  │        fail ──▶ regenerate ONCE with the failure list ──▶ inspector again
  │                     pass ──▶ deliver
  │                     fail ──▶ HOLD: safe fallback message + auto-incident
  │
  ▼  5. log the turn (Supabase): input, raw + shown output, every inspector report,
        model, skill version, prompt hash, tool calls, tokens, latency
```

## Why this order
- **Clean before anything else.** No identifier reaches the model or the logs. The phone cleans; the server re-cleans and rejects — defence in depth.
- **The skill is the source of truth.** The system prompt is assembled from the pinned `skill/` folder, not hand-written. The `prompt_hash` is logged so any drift is visible.
- **Cards on demand.** The six Core files are ~115k tokens. Loading all of them every turn is slow and costly. The operating files (~34k tokens) are cached in the system prompt; Core cards are fetched by ID only when a case needs them — the same rule the skill gives a human.
- **Codes are verified, not remembered.** ICD-11 codes come from the WHO API in that turn, or they are marked "to confirm". The inspector blocks an unverified code.
- **Nothing ships unchecked.** The inspector is deterministic (regex/structure), runs on 100% of replies, and its rulebook is `qc-checklist.md`. One regeneration, then a safe hold.

## The app contract line
Every reply starts with a machine-readable line, e.g. `<!--yc mode=A gate=none ceiling=Low level=L2-->`. The inspector parses it; the server strips it before the clinician sees the reply. It lets the inspector check that the mode, gate, ceiling and level match what the case and the verified profile require.

## Retry and fallback
- **One** regeneration only. The failure list is fed back to the model verbatim ("your draft failed these checks: …").
- A second failure is never shown. The clinician gets a safe message (with crisis numbers + disclaimer) and an incident is opened automatically for review.
- This caps latency and cost, and guarantees a clinician never sees an unchecked reply.

## What the inspector cannot do
It checks **structure and safety mechanics**, not clinical soundness — it cannot tell whether the leading consideration is right or the formulation is good. That judgement comes from:
- the clinician-graded eval suite (`evals/vignettes.json`, 20 cases, 114 checks), run before every model/skill change and weekly in beta, and
- the in-app **⚑ Report a problem** button, which opens an incident on any reply.

## Cost & latency controls
- Prompt caching on the ~34k-token system prompt (repeat turns pay the cache-read rate).
- 40 turns/clinician/day (`DAILY_TURN_LIMIT`) and a monthly org spend cap.
- Per-turn tokens and latency logged (`turns.usage`, `turns.latency_ms`) — measure real cost from logs on Day 2, don't estimate.
- A Mode A reply can take 1–2 minutes; the app shows a "drafting… running safety checks…" state and uses a 300s timeout.

## Change control (drift is the real risk)
Model, skill and ICD release are **pinned**. Changing any of them requires: run the evals → clinician reviews the grading pack → `CHANGELOG.md` entry → the `clinician-reviewed` PR label (CI enforces the label on any change to `skill/`, `app/inspector.py`, `app/deid.py`, `app/prompt.py`, `fixtures/`).
