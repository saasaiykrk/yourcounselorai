# YourCounselor content handover

Prepared 14 Oct 2026. Every file in this folder is a finished, standalone page: it opens directly in a browser with no build step and no network calls apart from Google Fonts.

## Files

| File | Type | Module slug |
|---|---|---|
| YourCounselor_Cognitive_Behavioural_Therapy_CBT.html | Therapy module (reader) | `cbt` |
| YourCounselor_Acceptance_and_Commitment_Therapy_ACT.html | Therapy module (reader) | `acceptance-commitment-therapy` |
| YourCounselor_Behavioural_Activation_BA.html | Therapy module (reader) | `behavioural-activation` |
| YourCounselor_Dialectical_Behavior_Therapy_DBT.html | Therapy module (reader) | `dbt` |
| YourCounselor_Exposure_Therapy_and_Inhibitory_Learning.html | Therapy module (reader) | `exposure-therapy` |
| YourCounselor_Motivational_Interviewing_MI.html | Therapy module (reader) | `motivational-interviewing` |
| YourCounselor_Person_Centred_Therapy_PCT.html | Therapy module (reader) | `person-centred-therapy` |
| YourCounselor_Solution_Focused_Brief_Therapy_SFBT.html | Therapy module (reader) | `solution-focused-brief-therapy` |
| YourCounselor_Neuro_Linguistic_Programming_NLP.html | Practice module (reader) | `neuro-linguistic-programming` |
| YourCounselor_Foundations_for_Counsellors_and_Psychologists.html | Training module (reader) | `foundations` |
| YourCounselor_Adult_Psychotherapy_Protocol_Matrix_and_Glossary.html | Static reference page | none |
| YourCounselor_The_Core_Eight_Practical_Guide.html | Static article | none |
| YourCounselor_Therapy_Comparison_Chart.html | Static reference page: the eight therapy modules compared side by side | none |
| YourCounselor_Case_History_and_MSE_Practice_Handout.pdf | Printable handout | none |

## How the reader modules work

Each module file contains, in order: the diagram renderer (`YCDiagrams`), the print builder for client handouts and counsellor sheets (`YCHandout`), the module reader (`YCReader`), then the module data (`var DATA = {...}`), a sample `window.YC_CONFIG` and the mount call.

All nine modules use the same 36 section keys in the same order (CBT is the reference). The reader's header comment documents the full config contract. In the app, replace the sample `window.YC_CONFIG` with live values:

- `viewer: { name, email }` from the signed-in user. It drives the watermark, and `viewer.name` is printed on every client handout after "YourCounselor ·" as the psychologist or counsellor giving it. Without a name the handout shows a blank line to write on. If handouts are generated on the server (`onHandoutDownload`), pass the same name to `YCHandout.buildHtml` as `practitioner`.
- `region`: ISO country code from the user's profile (IN, GB, US, CA, AU, NZ, AE). It selects crisis numbers in the safety note and disclaimer. Call `YCReader.setRegion(code)` if the profile changes without a remount.
- `modules: [{ slug, title }]`: the published modules. "Related modules" links appear only for slugs in this list, so links to modules that are not live yet stay hidden.
- `onNavigate(slug)`: open another module when a related-module link is tapped.
- `onHandoutDownload({ slug, handoutId, region, kind })`: server-side PDF generation. If omitted, the page builds the handout in the browser and opens the print dialog.
- `subscriptionActive`, `checks`, `onChecklist`, `onView`, `protect`: as described in the reader header.

`brand` and `crisis` must be supplied; the reader refuses to render without them so legal and safety text can never ship missing. Keep the disclaimer and copyright text exactly as supplied.

The Foundations module also shows a country selector in its top bar; it calls `YCReader.setRegion`.

## Changes made for this handover

Originals were not modified. Changes in these copies:

**Removed (review-stage material)**
- The "For clinical sign-off, not part of the module" panel (review scores, reviewer notes and the preview-only country selector inside it), its CSS and the reader hook that inserted it.
- "Added · review" chips on content items and section headings.
- Watermark fallback text "Clinical review copy" (now "Professional use only").
- MI: a dead placeholder config block (placeholder logo, India-only crisis data, "not enabled in this preview").
- CBT: page title "CBT Module Preview" replaced with "YourCounselor | Cognitive Behavioural Therapy (CBT)". Foundations title given the same "YourCounselor |" prefix.

**Fixed: content that existed in the data but did not display or print**
- SFBT: session steps and course rows rendered as "[object Object]"; the ending script, technique dialogues, "If the client says" guidance, measurement schedule, instruments and worked-case session details did not display.
- BA: the safety check script, per-technique examples, pitfalls and safety notes, tool instructions, technique-selection columns and worked-case dialogue did not display.
- DBT: the safety check script did not display.
- The reader now accepts these alternative data shapes, so all wording appears exactly as written. No clinical text was rewritten.
- PCT quiz: answers were stored as `correct` instead of `answer`, so every response was marked wrong. Renamed.
- Foundations worked case: the last session's label was stored under `review` instead of `session`. Renamed.
- Counsellor sheets (7 sheets in SFBT, MI, PCT) crashed the print builder because `cover` was text or true/false instead of a cover-page object. SFBT's cover sentence moved to the end of the sheet's "Use it:" line; the true/false flags were removed.
- BA: a source link displayed as raw Markdown. Links written as `[label](https://...)` now render as real links in every module.
- Related-module slugs `act` and `mi` corrected to `acceptance-commitment-therapy` and `motivational-interviewing`.

**Search (every reader module)**
- Text outside list items (section introductions, boxes, tables) is now searchable. Previously visible words could return "No matches" and the section was hidden.
- Enter and "go to first match" now scroll to the matching words, briefly highlight them (works in all browsers) and close the phone keyboard.

**Mobile and long pages**
- Floating "Home ↑" button on every page. It appears after scrolling 400px and jumps to the top in one press (no animated scroll, which could stop part-way on long pages). In modules it also returns the left sidebar and the phone section chips to the first tab, and it works when the app wraps the module in its own scrolling container.
- On screens up to 900px wide the search bar slides away while scrolling down and returns on any scroll up, so the sticky header no longer covers about half of a phone screen.
- Matrix: the protocol filter bar (search, cluster, care level, evidence) was removed at the owner's request, so every protocol row is always shown; the cluster index links still jump to each section and the Glossary search stays. Matrix: the existing Home button showed at the top of the page because its CSS overrode `hidden`; fixed, and it now scrolls with JavaScript so it also works when the page is embedded. Status text now says "1 protocol row" / "1 glossary entry".

**Owner decisions applied (14 Oct 2026)**
- Audience: every therapy module now says "Psychologists, professional counsellors, psychotherapists and supervised practitioners" on the cover and in the cover band. Foundations keeps its training audience (counsellors, psychologists, trainees and supervisors).
- "Coaches" removed as an audience or role (SFBT audience and settings, MI counsellor sheet and complaints line). Established technique terms such as DBT "phone coaching" are unchanged.
- UAE crisis contacts: the national mental health support line 800 4673 is labelled "(8am to 8pm)", and the UAE disclaimer wording now lists ambulance 998 first. Foundations now has the same UAE contacts as the other modules.
- Every counsellor sheet that records client work now opens with a confidential cover page (client identifier, date, practitioner, setting); supervision sheets use a de-identified case-reference cover. The MI client reflection worksheet is client-facing and has no confidential cover.
- Client handouts: "YourCounselor · [psychologist or counsellor]" line under the logo; the closing note is labelled "Disclaimer", followed by the Copyright & IP notice.
- MI cover label changed from "Professional practice module" to "Clinical reference module", matching the other therapy modules.
- Case History and MSE PDF rebuilt in the YourCounselor print style with the same text, logo, page footer, Disclaimer and Copyright & IP notice; UK spelling throughout; the "Setting or mode" field no longer wraps.

**House style**
- Em and en dashes removed from visible content: number ranges use a hyphen (0-10, sessions 12-16), 14 em dashes were rewritten with ordinary punctuation, and the Matrix "Short form" column shows "None" instead of a dash (legend updated).

## NLP module (added 15 Oct 2026)
Built on the same reader, sections and order as CBT. Content is original teaching text; the owner's NLP slide decks and the table of contents of *The Big Book of NLP Techniques* (Vaknin, 2008) guided topic coverage only. It presents NLP as communication and experiential techniques to integrate into evidence-based care, with linked evidence notes (Sturt and colleagues 2012 systematic review; Wiseman and colleagues 2012; the 2023 RTM feasibility trial). Left out on safety or ethics grounds: memory removal or "erasing", intensifying distressing memories, timeline release of past trauma, pain dissociation without medical assessment, covert influence (embedded commands, nested loops, double binds, subliminal persuasion) and cure claims. The Therapy Comparison Chart still covers the eight therapy modules; NLP is not added to it.

## Therapy Comparison Chart
A standalone page that compares the eight therapy modules on the same fifteen points (aim, how change happens, core ideas, stance, client role, session shape, course, techniques, between-session work, progress tracking, typical use, cautions, common misunderstanding, key names, training). It also has an at-a-glance table, an emphasis grid, a "choosing a starting point" guide, shared principles and notes on combining approaches. Practitioners can choose which approaches to compare; on phones every table becomes cards. "Open" links point to the module files by file name; in the app, map them to the module routes (or `onNavigate`).

## Checks run on the final files
- HTML parses with balanced tags; every inline script compiles; embedded module data is valid JSON.
- Section keys and order identical to CBT in all nine modules.
- Every data field is visible on the page (counsellor-sheet fields are print-only by design).
- All 68 client handouts and counsellor sheets were generated through the existing print builder with content, fields, disclaimer and copyright present and no errors.
- Rendered at 375px, 768px and 1280px: no horizontal page overflow; Home button, search and compact header tested on phone width.
- No sign-off, review, placeholder, TODO or raw Markdown link text in visible content.

## Notes for the content owner
- The UAE line 800 4673 is confirmed by news and guide coverage but was not found on an official government page; recheck it periodically.
- Related-module links to modules not yet published (for example REBT, MBCT, family counselling) stay hidden until those modules are added to `modules`.
