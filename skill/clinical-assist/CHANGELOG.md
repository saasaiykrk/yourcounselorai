# clinical-assist — change log

## v2.1.1 — 2026-09-24
**Owner:** Clinical Safety Officer, Fabeminds Counselling Services (*name to be assigned*) · **Next review:** 2027-09-24

**Added**
- Version / owner / review-date block at the top of `SKILL.md`.
- `references/crisis-resources.md` — single crisis-number register with owner, deputy, annual review date (2027-09-24), review procedure, event triggers and review log. All other files now point to it.
- Core 6 `NPS-00` — licence register for cognitive and neuropsychological tools (MoCA certification requirement, MMSE purchase requirement, PUB/RQ and version-dependent tools), with owner and annual review date; licence column added to Core 6 `APX-04`; licence pointer added under `NPS-02`.
- QC checks 8b (tool licence shown) and 8c (crisis numbers match register).

**Changed**
- "CHILDLINE 1098" → "Child Helpline 1098" (now run under Mission Vatsalya and integrated with ERSS-112) in Core 1 `ASM-06`, Core 2 `CHD-13` and data-model section, SKILL.md, v21-contract, mode templates.
- KIRAN 1800-599-0019 removed from Core 1 `ASM-06` (merged into Tele-MANAS, announced Feb 2024); Women Helpline 181 added to the Core 1 list.
- Core 1, Core 2 and Core 6 are therefore **no longer byte-identical** to the v2.0 originals; edits are limited to the lines listed above.

**Restored (omissions found by line-by-line audit against the original SKILL.md)**
- Opening-round question "Has risk been screened?" and the "just proceed" defaults (Mode A · L2 · risk not yet asked).
- "Partner violence with fear or coercion" as a Gate 1 acute-risk trigger.
- Style rules: describe behaviour rather than labels (personality, forensic); never invent a card; no celebratory emojis; the assistant's role sentence (organise, surface options, flag risk, draft for review); Core 1 ASM-07 pointer.

**Added (source fidelity)**
- `references/v21-master-prompt.md` — the v2.1 master prompt stored **verbatim** and marked authoritative; `v21-contract.md` is now labelled as its condensed operating version.

**Fixed (final recheck)**
- `example-mode-a-panic.md`: Sections 12–17 now carry the "PROVISIONAL — Low confidence" prefix and the exact v2.1 section titles, matching the rule in SKILL.md and the mode templates.

**Clarified**
- `evals/evals.json` exists (4 test cases with assertions). The official packager deliberately excludes the root `evals/` folder from the `.skill` file, so it is distributed separately.


## v2.1 (upgrade from OC-TP v1.1)
**Changed**
- Output structure now follows YourCounselor master prompt v2.1 (`references/v21-contract.md`) instead of OC-TP v1.1.
- Case History & MSE Audit is mandatory Section 1; confidence ceiling; Gate 1 (acute risk) and Gate 2 (data sufficiency).
- Confidence labels, DSM-5-TR alongside ICD-11, cultural formulation (CFI), functional-analysis chain, five-branch decision tree, in-session vs between-session actions, 8-column session table, ready-to-use worksheet structures.
- Medication: only the prescriber-review line. No invented cut-offs; evidence source stated.
- Disclaimer replaced with the v2.1 mandatory text.
- Opening question round reduced: mode defaults to A; role asked only alongside a mode question, else L2 assumed and stated.

**Added**
- `references/case-history-mse-audit.md`, `references/qc-checklist.md`, `assets/mode-templates.md`, `references/example-mode-a-panic.md`, `evals/evals.json`.

**Removed**
- `references/output-contract.md` (OC-TP v1.1) and `references/output-example-paediatric-ocd.md` — they model the superseded format and would conflict.

**Kept unchanged (all clinical functions)**
- Core 1–6 knowledge files (all cards, free scales, evidence grades, techniques) — unchanged in v2.1; see v2.1.1 for the targeted helpline and licence edits.
- Routing table, copyright/licensing rules, India crisis numbers, POCSO, no-harm-contract rule, two-source rule for interpretations.
- L1/L2/L3 competence gating and L1 output rules.
- Task workflows: case help, free-scale scoring (incl. RCI), restricted-test interpretation, TPE-01/02 treatment plans, session support, report writing (RPT-01…03), child/couple/family rules.
- Icon meanings, card-ID citation, India cultural grounding, follow-up-turn editing.
- `referral-criteria.md` and `documentation.md` (only headings/section references updated).
