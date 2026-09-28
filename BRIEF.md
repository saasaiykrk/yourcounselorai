# YourCounselor — one-page brief

*For anyone who needs the picture before the code. Non-technical.*

## What it is
A phone app that helps a **registered mental-health professional** think through a case. The clinician types a short, **de-identified** description of a client; the app returns a structured clinical work-up — a case-history audit, a safety screen, a formulation, things to consider, assessment and therapy options, and a session plan — always framed as **support for the clinician's own judgement, never a diagnosis or a replacement for them.**

It is a **reference and documentation aid for qualified professionals.** It does not diagnose, detect, or treat. Every reply says so and ends with a disclaimer.

## Who it's for
Registered psychologists and counsellors in India (beta targets RCI-registered psychologists first). Not for clients or the public.

## Why it's safe to put in front of clinicians
Three safeguards are built in, not bolted on:
1. **No client identities leave the phone.** Names, phone numbers, addresses, IDs and similar are stripped on the device, and the server rejects anything that slips through.
2. **A reviewing clinical psychologist stands behind it.** Every change to the clinical content is reviewed by a registered clinical psychologist before it ships.
3. **Every reply is safety-checked before the clinician sees it.** An automatic checker confirms the reply screened for risk, gave the right crisis numbers, avoided medication advice, and carried the disclaimer. A reply that fails is held back.

If a case shows immediate danger (suicide risk, abuse of a child, violence), the app stops and shows the crisis pathway instead of a treatment plan.

## How it's being built (phased, deliberately slow where it counts)
| Phase | Roughly | What happens |
|---|---|---|
| 0 | This week | Line up the reviewing psychologist; write the "no identities leave the phone" rule into the build. |
| 1 | Weeks 1–2 | Build the beta: the app, the identity stripper, the clinical engine, the safety checker. |
| 2 | Week 2 | The psychologist grades the app on 20+ realistic test cases. Fix what they flag. |
| 3 | Week 3 | Free closed beta to 20–30 psychologists. Every reply has a "report a problem" button. |
| 4 | Weeks 4–5 | A data-protection lawyer reviews two documents (clinician terms + consent). |
| 5 | Month 2 | Paid launch, opened from the beta waitlist first. |

## What "done" looks like for the beta
Real psychologists using it on real (de-identified) cases, a registered clinical psychologist having signed off the outputs, and a clean incident record. Growth comes from word of mouth in a small, connected professional community — which is exactly why the safeguards come first.

## What this pack is
The technical hand-off for the developer: the build spec, the safety code (written and tested), the clinical knowledge base, the test cases, and a local test console. The non-technical reader needs only this page; the rest is for the developer.

## The one risk worth naming
The thing that breaks a product like this isn't a bug — it's **drift**: six months in, someone edits the clinical content and skips the review "just this once," and quality erodes unseen. The change-control process in this pack (version pinning, the test suite, and clinician sign-off on every clinical change) exists to prevent exactly that. Keep it alive.
