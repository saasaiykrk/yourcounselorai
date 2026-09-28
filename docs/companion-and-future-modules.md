# Companion and future modules

What is in the beta, and what is deliberately left for later. This keeps scope honest: the beta ships the consult core and nothing else. Everything below the line is **not** in Week 1–3 and must not delay the beta.

## In the beta (Phases 1–3)
- **Clinician consult** — the seven modes, both gates, the audit-first discipline (this pack).
- **De-identification** — on-device cleaner + server re-check.
- **Registration & levels** — L1/L2/L3 from verified registration.
- **Inspector** — pre-send safety checks on every reply.
- **Incident button + logging** — every reply reportable; every turn logged.

## The skill already contains these — expose them only when the core is proven
The `clinical-assist` knowledge base (Core 1–6) already covers far more than the beta surfaces. These become in-app modules **after** the consult core is validated and the clinician is signing off updates:

| Module | Backed by | Notes |
|---|---|---|
| **Scale scoring** (PHQ-9, GAD-7, DASS-21, HAM-A, Rosenberg) | Core 1 INS-14; Core 6 BRF (Reliable Change) | Only these five are item-by-item licensed. Structured scoring + risk-item triggers + change tracking. |
| **Structured intake capture** | `schema/intake-schema.json`, Core 1 ASM-01 | The intake form that feeds the consult; a natural second screen. |
| **Documentation pack** | Mode F, `documentation.md` | SOAP/DAP/intake summary/risk note/referral letter/discharge — drafts for the clinician. |
| **Couples module** | Core 4 (CPL/CP cards) | Requires the private per-partner violence screen (Appendix H product rules) — build the safety gating first. |
| **Child & adolescent** | Core 2 (CHD/INT cards) | Consent + assent flows, safeguarding, developmental matching. |
| **CBT worksheet toolkit** | Core 5 (WS/GRD) | Thought records, core-belief work, grounding "Ground me" button. |
| **Report writer** | Core 6 (RPT cards) | Full psychological report structure + QA checklist. |
| **Outcome dashboards** | Core 6 BRF, Core 4 product rules | Trend charts; never expose one partner's private entries to the other. |

## Client-facing "companion" — explicitly out of scope for now
The product brief imagines eventually helping clients directly. **The beta does not do this.** The skill has a hard rule: *clients are not users* — if the person seems to be a client seeking help, the assistant responds supportively and points to a professional or crisis line, and does not run protocols. Any client-facing companion is a separate product with its own clinical, legal and safety review. Do not build it inside the clinician app.

## Deferred technical items (named so they aren't forgotten)
- **On-device name detection** — the regex cleaner can't catch every bare first name; the possible-name chips + attestation cover the beta. Add an on-device NER model only if beta logs show names slipping through.
- **BYOK ("bring your own API key")** — the brief mentioned clinicians using their own GPT key. Dropped for the beta (it breaks "the app holds no keys" and bypasses the inspector and logging). Revisit only after paid launch, and only with the inspector kept server-side.
- **Offline / low-connectivity mode** — not in beta.
- **Multi-language UI** — the assistant already works in the client's language within a reply; a translated app UI is later.
- **Payments & subscriptions** — Phase 5; the beta is free.

## The rule that keeps this list a list
Every item here waits behind two things: (1) the consult core passes clinician validation, and (2) the clinician reviews the skill change that adds the module. Modules are added one at a time, each with its own eval cases. Shipping breadth before the core is proven is the failure mode this doc exists to prevent.
