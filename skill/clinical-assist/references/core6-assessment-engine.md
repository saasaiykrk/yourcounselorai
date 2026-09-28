# CORE 6 — Psychological Assessment Engine: Process, Interpretation Rules, Neuro-Screening, Treatment Matching & Reports
### YourCounselor AI · Clinical Practice Knowledge Base · Core 6 · v2.0 (original-text edition)

**Extends Cores 1–5.** Same ID scheme, evidence grades, competence levels (L1–L3) and licence codes.

**About this edition:** v2.0 is written in original wording for YourCounselor AI. The assessment cycle, safeguards, decision rules, report standard and QA checklist are organised and expressed in our own way. v1 was condensed from a single assessment handbook; v2 draws on the primary sources — test manuals and research papers — which are listed in Appendix L. **Numerical cut-offs and scale structures are factual information taken from those primary sources. Before any cut-off is used in the live app, it must be checked against the current licensed manual.** No test items, stimuli, proprietary norm tables or interpretive-report text are included.

**Not repeated here (see Core 1):**
- Psychometrics (reliability, validity, SEM, norms)
- The test library overview (Wechsler subtests, MMPI scale list, projectives, neuropsychological batteries)
- Intake, case history, MSE, risk, ethics

This Core adds **step-by-step interpretation rules**, cut-offs and decision trees, treatment-matching logic, and a report quality standard.

**ID prefixes added:** `APX` (assessment process), `IA` (interpretation rules), `NPS` (neuropsychological screening), `BRF` (brief outcome instruments), `TXM` (treatment matching), `RPT` (reports).

> ⚠ Nearly all instruments in this Core are commercial and restricted to qualified users (PUB/RQ). The app may store scores the clinician enters and apply its own decision rules to them, but **must never reproduce items, stimuli, proprietary norm tables or publisher interpretive text** without a licence. MMPI®, MMPI-2®, MMPI-2-RF®, MMPI-3® and related marks belong to the University of Minnesota; WAIS®, WISC®, WMS®, BDI® and similar marks belong to their publishers — refer to them by name only. Every interpretive statement is a **hypothesis** that needs support from at least two independent sources.


## Contents (card index — grep the ID to jump to it)
  - YourCounselor AI · Clinical Practice Knowledge Base · Core 6 · v2.0 (original-text edition)
- PART 33 — THE ASSESSMENT PROCESS (APX)
  - APX-01 YourCounselor assessment cycle (8 steps)
  - APX-02 Guarding against judgement errors (built into app prompts)
  - APX-03 Referral questions by setting
  - APX-04 Choosing instruments by domain (quick map)
  - APX-05 Structured interview directory
  - APX-06 Behavioural assessment methods
- PART 34 — INTERPRETATION RULES (IA)
  - IA-01 Wechsler intelligence scales (WAIS-IV / WISC-V): step-down interpretation (L2)
  - IA-02 Wechsler scores and possible brain dysfunction
  - IA-03 Memory interpretation (WMS-IV)
  - IA-04 MMPI-2 / MMPI-A: stepwise interpretation (L2)
  - IA-05 MMPI validity indicators (summary; verify against the current manual)
  - IA-06 MMPI-2 scales and two-point codes — hypothesis prompts
  - IA-07 Personality Assessment Inventory (PAI; Morey) (L2)
  - IA-08 MCMI-IV (Millon) (L2/L3)
  - IA-09 NEO-PI-3 / NEO-FFI-3 (five-factor model) (L1–L2)
  - IA-10 Rorschach (CS and R-PAS) (L3 only)
- PART 35 — NEUROPSYCHOLOGICAL SCREENING (NPS)
  - NPS-01 History interview for possible brain impairment
  - NPS-02 Areas and screening tools
  - NPS-00 Licence register — cognitive and neuropsychological tools
  - NPS-03 RBANS Update (brief battery)
  - NPS-04 Bender-2 (Bender Visual-Motor Gestalt Test, 2nd ed.)
  - NPS-05 Depression vs dementia: differentiating features
  - NPS-06 Effort and performance validity
- PART 36 — BRIEF OUTCOME INSTRUMENTS (BRF)
- PART 37 — TREATMENT MATCHING (TXM)
- PART 38 — PSYCHOLOGICAL REPORT STANDARD (RPT)
  - RPT-01 Report structure
  - RPT-02 Writing rules
  - RPT-03 Report quality checklist (YourCounselor in-house)
  - RPT-04 Feedback session (collaborative / therapeutic assessment principles; Finn)
- APPENDIX K — DATA MODEL ADDITIONS
- APPENDIX L — REFERENCES & VERSION LOG
  - L.1 Key references (primary sources)
  - L.2 Version log

---

## PART 33 — THE ASSESSMENT PROCESS (APX)

### APX-01 YourCounselor assessment cycle (8 steps)
A synthesis of widely taught hypothesis-driven assessment practice (e.g., Groth-Marnat & Wright; Meyer et al., 2001).
1. **Pin down the referral question.** Ask what *decision* the referrer needs to make. Watch for unstated purposes (e.g., a school that needs grounds for a placement, a therapist who feels stuck). Check that testing can actually help and that the question is within your competence. If testing won't change the decision, say so and don't test.
2. **Gather background:** interview the client and relevant others; review records (school, medical, legal, earlier reports) (Core 1 ASM-03/04).
3. **Form initial hypotheses** about what is going on.
4. **Choose instruments** in this order of priority: fit to the referral question → psychometric quality → fit to the client (age, culture, language, disability, motivation) → your competence → efficiency (Core 1 INS-00).
5. **Collect data:** standard administration plus careful behavioural observation (Core 1 ASM-10).
6. **Test the hypotheses:** actively look for evidence that *contradicts* them.
7. **Build an integrated picture of the person:** how they function now; what predisposed, triggered and maintains the difficulties; likely course; and relevant relationships and systems.
8. **Write recommendations** that are specific, practical and tied back to each referral question (RPT-01).

**Principle:** history often carries more weight than test scores. For example, previous suicide attempts and a long-standing course predict suicide risk better than a raised depression score.

### APX-02 Guarding against judgement errors (built into app prompts)
| Error | What the app does |
|---|---|
| **Ignoring base rates** — a "90% accurate" screen for a condition affecting 1% of people produces mostly false positives | Shows base rate and positive predictive value whenever a screening cut-off is applied (Core 1 PSY-07) |
| **First-impression bias** | Encourages structured or semi-structured interviews and delays the formulation step until data entry is complete |
| **Confirmation bias** | Requires the clinician to list evidence *against* the leading hypothesis |
| **Hindsight and overconfidence** — confidence is only weakly related to accuracy | Lets clinicians record predictions before outcomes are known, and prompts for outcome follow-up |
| **Faulty memory** | Pulls from session notes rather than recollection |
| **Stereotyping** by gender, caste, ethnicity or culture | Prompts explicit use of diagnostic criteria and a cultural formulation (Core 2 CHD-21) |
| **Over-trusting intuition or projective impressions** — research shows clinicians often do no better than lay judges on such tasks | Gives more weight to objective and structured data |
| **Clinical vs statistical prediction** — meta-analysis shows statistical (actuarial) methods are on average modestly more accurate (Grove et al., 2000) | Uses validated rules and cut-offs where available; the clinician then integrates unusual case features |
| **Computer-generated narratives** — studies suggest a substantial share of statements may not fit the individual | Labels all auto-text as hypotheses; never pasted unedited into reports |

### APX-03 Referral questions by setting
| Setting | Decisions typically at stake | Points to clarify or include |
|---|---|---|
| **Psychiatric inpatient** | Suicide or violence risk, admission and discharge, ward placement, legal detention, choice of treatment | Level of risk and how to manage it — not just a diagnosis; conflicting roles (therapist vs administrator); requests that may mask staff frustration |
| **Psychiatric outpatient / therapy** | Readiness for therapy, best approach, likely obstacles | Coping style, resistance, insight, level of impairment, complexity (TXM) |
| **General medical** | Psychological contribution to symptoms, treatment adherence, pre-surgery or transplant screening, capacity, cognitive status, pain | Short reports (about 2 pages); medical terminology; depression vs dementia |
| **Legal / forensic** | Fitness to stand trial, criminal responsibility, custody, personal injury, risk | Written record of procedures with dates and times; effort and symptom-validity testing; prepare for cross-examination; longer reports (7–10 pages); avoid dual roles |
| **Educational** | Learning disability, ADHD, giftedness, intellectual disability, placement, accommodations (RPwD Act) | Classroom observation; teacher and parent input; achievement testing; practical, specific recommendations |
| **Clinic / self-referral** | Self-understanding, career, relationships | Collaborative, therapeutic feedback (RPT-04) |

### APX-04 Choosing instruments by domain (quick map)
| Domain | Options (edition and licence per Core 1 INS) | Licence (codes: Core 1 §0.4; details: NPS-00) |
|---|---|---|
| Brief cognitive screen | MSE; MMSE or MoCA; WMS-IV Brief Cognitive Status Exam | MSE: n/a · MMSE: **PUB** · MoCA: **FREE-conditional + mandatory certification** · WMS-IV BCSE: **PUB/RQ** |
| Intelligence | WAIS-IV / WAIS-5, WISC-V, SB-5, KABC-II, WJ-IV COG; WASI-II (brief) | All **PUB/RQ** |
| Memory | WMS-IV, RAVLT, CVLT-3, Benton Visual Retention Test, Rey–Osterrieth recall | WMS-IV, CVLT-3, Benton: **PUB/RQ** · RAVLT, Rey–Osterrieth: **version-dependent** (NPS-00) |
| Visual-constructional | Bender-2, Rey–Osterrieth copy, Block Design | Bender-2, Block Design: **PUB/RQ** · Rey–Osterrieth: version-dependent |
| Academic achievement | WJ-IV ACH, WIAT-III/4, WRAT-5 | All **PUB/RQ** |
| Broad psychopathology | MMPI-2 / MMPI-2-RF / MMPI-3, PAI, MCMI-IV, SCL-90-R / BSI | All **PUB/RQ** |
| Normal-range personality | NEO-PI-3, 16PF; IPIP-based measures (public domain) | NEO-PI-3, 16PF: **PUB/RQ** · IPIP: **PD** |
| Performance-based personality | Rorschach (R-PAS / CS), TAT, sentence completion | Rorschach plates and R-PAS/CS: **PUB/RQ** · TAT: **PUB** · sentence completion: version-dependent |
| Structured diagnosis | SCID-5-CV/PD, MINI, K-SADS, ADIS-5, SIRS-2 (feigning), PCL-R (psychopathy), EDE (eating), DIB-R (borderline) | SCID-5, ADIS-5, SIRS-2, PCL-R: **PUB/RQ** · MINI, K-SADS, EDE, DIB-R: owner terms vary — **verify** before use or digitising |
| Symptoms and outcome | BDI-II, PHQ-9, STAI, GAD-7, DASS-21, ORS/OQ-45 | BDI-II, STAI: **PUB/RQ** · PHQ-9, GAD-7, DASS-21: **FREE** (Core 1 INS-14) · ORS: licence terms · OQ-45: **PUB** |
| Substance use | AUDIT, MAST, DAST | AUDIT: **FREE** (WHO) · MAST, DAST: **verify** owner terms |
| Couples and families | DAS, CSI, MSI-R, Family Environment Scale (Core 4) | DAS, MSI-R, FES: **PUB** · CSI: **FREE** (research/clinical; verify) |
| Effort / performance validity | TOMM, Rey 15-Item Test, embedded indicators (Reliable Digit Span, WMS-IV ACS) | TOMM, WMS-IV ACS: **PUB/RQ** · Rey 15-Item: PD paradigm (verify norms source) · Reliable Digit Span: derived from a **PUB/RQ** subtest |

**Where to check a test's quality:** *Mental Measurements Yearbook* and *Tests in Print* (Buros Center); Hunsley & Mash, *A Guide to Assessments That Work*; Strauss, Sherman & Spreen, *A Compendium of Neuropsychological Tests*; Lezak et al., *Neuropsychological Assessment*.

### APX-05 Structured interview directory
| Purpose | Interview |
|---|---|
| Adult clinical disorders | SCID-5 (CV/RV), MINI, SADS, DIS |
| Children and adolescents | K-SADS-PL, DICA, DISC |
| Personality disorders | SCID-5-PD, SIDP-IV, IPDE |
| Anxiety | ADIS-5 |
| Borderline pattern | DIB-R |
| Psychopathy | PCL-R (L3; forensic) |
| Dissociation | SCID-D |
| Feigned symptoms | SIRS-2 |
| Eating | EDE |
| Substance use | SUDDS; Comprehensive Drinker Profile |
| Pain | Psychosocial Pain Inventory |
| Sleep | Structured interviews for sleep disorders |

**Trade-off:** structured interviews are more reliable but less flexible and less rapport-building. Use semi-structured interviews at intake and structured ones for diagnosis or research (Core 1 ASM-03).

### APX-06 Behavioural assessment methods
| Method | How it works | Best for |
|---|---|---|
| **Behavioural interview** | Define the target behaviour precisely; map antecedents, behaviour and consequences; measure frequency, intensity and duration; note past solutions, rewards and client resources | Any behavioural plan (Core 2 CHD-05 FBA) |
| **Narrative recording** | Continuous written account of behaviour in its setting | Early exploration; hypothesis generation |
| **Interval recording** | Split the observation into short intervals (e.g., 15 seconds) and mark whether the behaviour occurred in each | Frequent behaviours (e.g., on-task behaviour) |
| **Event recording** | Count each occurrence | Discrete, countable behaviours (tantrums, cigarettes) |
| **Rating after observation** | Rate a quality on a scale after watching (e.g., cooperation 1–5) | Broad qualities |
| **Self-monitoring** | The client records the behaviour and its context (diary or app) | Private behaviours, thoughts and urges — note that recording itself often changes the behaviour |
| **Analogue / role-play** | Simulated situation (e.g., a social-skills task) | Skill deficits |
| **Psychophysiological** | Heart rate, muscle activity (EMG), skin conductance | Anxiety; biofeedback |
| **Cognitive questionnaires** | e.g., Dysfunctional Attitude Scale, ATQ (Core 5 SR-03), Attributional Style Questionnaire, Fear of Negative Evaluation, Social Avoidance and Distress Scale, Fear Survey Schedule, EAT-26, BULIT-R (licences vary) | Cognitive targets |
| **Think-aloud / thought listing** | Client says their thoughts during or after a task | Real-time thinking |

**Reliability:** aim for inter-observer agreement of at least 80% (or κ ≥ .60); watch for **observer drift** and **reactivity**.

---

## PART 34 — INTERPRETATION RULES (IA)
*Rules below summarise published interpretive guidance (test manuals and peer-reviewed literature). Verify every threshold against the current licensed manual before release.*

### IA-01 Wechsler intelligence scales (WAIS-IV / WISC-V): step-down interpretation (L2)
```
STEP 1 – Full Scale IQ (FSIQ): descriptor + percentile + 95% confidence interval.
         If the gap between highest and lowest index is ≥ 23 points, treat the FSIQ as
         a poor summary. Consider the General Ability Index (GAI; verbal + perceptual
         subtests, excluding working memory and processing speed). GAI > FSIQ suggests
         that working memory / processing speed — which are sensitive to brain injury,
         age and situation — are pulling overall performance down.
STEP 2 – Index scores (VCI, PRI [WISC-V: VSI + FRI], WMI, PSI).
         Treat an index as meaningful only if its subtests hang together
         (spread between highest and lowest subtest scaled score < 5).
         For index differences, use BOTH the manual's statistical significance values
         (p < .05) AND the base rate (how often that size of gap occurs in the norm sample).
         Separate a normative weakness (index < 85, especially < 80) from a purely
         personal weakness (low for this person but still in the average range).
STEP 2b – CHC-based clinical clusters (requires core + supplemental subtests); each cluster
         must hang together (< 5 scaled-point spread); comparisons between clusters need
         roughly ≥ 20 standard-score points to be meaningful. (Cluster definitions: see the
         Flanagan & Kaufman / Lichtenberger & Kaufman literature for WAIS-IV and WISC-V;
         load the definitions from the licensed source.)
STEP 3 – Subtest strengths and weaknesses relative to the person's own mean (overall or
         within the index) — only where spread exists, and as hypotheses only (subtest
         specificity is limited).
STEP 4 – Process analysis (e.g., forward vs backward vs sequencing span; recognition vs
         free recall to separate retrieval from knowledge; error types).
STEP 5 – Patterns within a subtest (e.g., failing easy items but passing harder ones →
         consider lapses of attention, anxiety, low effort or retrieval problems).
```
**Writing each ability paragraph:**
1. A plain-language summary with a percentile ("verbal reasoning is well above average — higher than about 95 of every 100 people of the same age").
2. The components involved.
3. A qualitative description of how the person performed (never quote actual items).
4. Relevant observations during testing.
5. **What this means in daily life** ("likely to follow detailed spoken instructions with ease").

**Descriptors:** use percentiles and plain descriptors. Prefer "well below average" to "borderline", which can be confused with borderline personality.

**Short forms:** acceptable only as screens. They should correlate at least .90 with the full scale, yet even then a sizeable minority of estimates miss by 10 IQ points or more. **Label them "estimated"**, never use them for classification or legal decisions, and prefer a validated brief test (WASI-II, KBIT-2).

### IA-02 Wechsler scores and possible brain dysfunction
- **There is no single "brain-damage profile".** Older "hold / don't-hold" subtest ratios misclassify too often to be used.
- **Most useful general sign:** current scores **lower than expected** from estimated premorbid ability (education, occupation, reading-based premorbid measures such as the TOPF, demographic prediction equations).
- **Processing speed is usually the most affected index** after traumatic brain injury and in Alzheimer's disease; working memory and fluid/perceptual reasoning are also often lowered, while verbal and knowledge-based skills are relatively preserved.
- **Recent focal lesions tend to produce uneven profiles; long-standing or diffuse conditions (toxic, degenerative) tend to produce an even overall lowering.**
- **Side of the brain:** verbal lower than perceptual may point to left-hemisphere / language involvement; perceptual lower than verbal may point to right-hemisphere involvement. **Never diagnostic on its own.**
- **Process measures:** backward and sequencing span are more sensitive than forward span; recognition formats help separate retrieval from learning problems.
- Always combine with history, medical findings, imaging and effort testing. Refer to neuropsychology (L3).

### IA-03 Memory interpretation (WMS-IV)
- **Index scores (M = 100, SD = 15):** Auditory Memory, Visual Memory, Visual Working Memory, Immediate Memory, Delayed Memory. The optional **Brief Cognitive Status Exam** classifies performance into bands from average to very low; if performance is in the low bands, consider whether the full battery is appropriate (see manual for band cut-points).
- **Contrast scores:** auditory vs visual; visual working memory vs visual memory; **immediate vs delayed** (delayed much lower than immediate suggests rapid forgetting or poor consolidation).
- **Comparison with general ability:** memory lower than predicted from the GAI points to a specific memory problem rather than a general intellectual limitation.
- **Rules:**
  - A single low subtest is common in healthy people — don't over-read it.
  - Statistically significant is not the same as clinically impaired; check base rates.
  - Exclude non-memory explanations: hearing, vision, language, attention, low effort, executive problems, medication, depression, limited familiarity with the test culture.
  - **Rough orientation:** index scores around 70 are typical in Alzheimer's disease and intellectual disability; 70–85 is often seen in schizophrenia, after temporal lobe surgery, and after moderate–severe brain injury. Always judge against the person's occupation and premorbid level — "low average" verbal memory may be a real impairment for a lawyer.
  - Use the publisher's supplementary tools for effort and change scores where licensed.

### IA-04 MMPI-2 / MMPI-A: stepwise interpretation (L2)
1. **Completion time.**
   - Typical: about 60–90 minutes for the MMPI-2 (shorter on computer); about 60 minutes for the MMPI-A.
   - **Much longer than 2 hours** → consider severe depression or psychosis, indecision, low reading ability or cognitive impairment.
   - **Unusually fast** → consider careless or random responding, or impulsivity.
2. **Score and plot** T scores; review critical items with the client.
3. **Identify the code type:** the two highest clinical scales (excluding 5 and 0). A code is **well defined** when both are above T 65 *and* at least 5 T points above the next highest scale. If poorly defined, interpret scales individually and emphasise themes shared across elevated scales.
4. **Check validity** (IA-05).
5. **Overall adjustment:** how many scales exceed T 65, and how high; the level of F.
6. **Describe:** T 60–65 = mild tendency (soften language); above 65 = characteristic. Integrate content, Harris–Lingoes, supplementary and Restructured Clinical scales.
7. **Diagnostic impressions** — the profile suggests; it does not diagnose.
8. **Treatment implications:** ego strength (Es), negative treatment indicators (TRT), insight, defensiveness, potential for acting out. Give collaborative feedback (Finn's Therapeutic Assessment; RPT-04).

**Commonly used profile rules (clinical-scale T scores; see Graham, 2012; Friedman et al., 2015):**

| Question | Rule of thumb |
|---|---|
| Acting out / impulsivity | Elevated 4 and/or 9, especially with low 0 |
| Dampening effect | Elevated 5 or 0 may soften the expression of other elevations |
| Inward vs outward expression | (2 + 7 + 0) greater than (4 + 6 + 9) suggests internalising; the reverse suggests externalising |
| Over-controlled hostility | Scale 3 with the O-H supplementary scale |
| Poor anger control | ANG content scale |
| Current distress | Height of 2 and 7 |
| Anxiety | Elevated 7, especially above 8 |
| Depression | High 2 with low 9 |
| Hypomania | High 9 with low 2 |
| **Possible psychotic process** | High 8 with elevated BIZ, especially when 8 clearly exceeds 7 |
| Marked confusion | F, 7 and 8 all very high |
| Suspiciousness | Elevated 6, especially as the highest scale |
| Substance-use risk | Elevations on 4, 2, 7; MAC-R and APS (proneness); AAS (acknowledged use) |
| Long-standing difficulties | Elevated neurotic or psychotic pairs with a clear gap between them |
| Distress rather than psychosis | 6, 8 and 9 elevated but RC6, RC8 and RC9 not elevated, with high RCd → general demoralisation rather than psychosis |

### IA-05 MMPI validity indicators (summary; verify against the current manual)
| Indicator | Decision guidance |
|---|---|
| **Cannot Say (?)** | Many omitted items (commonly ≥ 30) → do not interpret |
| **VRIN / VRIN-r** | T 70–79 = interpret with caution; **T ≥ 80 = invalid** (inconsistent / random responding); MMPI-A uses a lower threshold |
| **TRIN / TRIN-r** | T 70–79 = caution; **T ≥ 80 = invalid** (fixed "true" or fixed "false" responding) |
| **F** (MMPI-2) | Thresholds for over-reporting rise with setting (non-clinical < outpatient < inpatient); moderate elevations may reflect a cry for help or genuine severe distress |
| **Fb** | High elevations → over-reporting in the second half of the test |
| **Fp / Fp-r** | Elevations → likely over-reporting of psychopathology, even among psychiatric patients |
| **F-r** (RF) | Moderate = distress; very high = possibly invalid; extreme = invalid |
| **Fs** (RF) | Elevated → over-reported physical symptoms |
| **FBS / FBS-r** | Elevated → non-credible physical or cognitive complaints (injury and disability contexts) |
| **RBS** (RF) | Elevated → over-reported memory complaints |
| **L / L-r** | Elevated → under-reporting / claims of unusual virtue |
| **K / K-r** | Elevated → defensiveness; moderate elevations can reflect genuine good adjustment (e.g., job screening) |
| **S** | Presenting oneself in a highly favourable light (MMPI-2) |

**App:** exact T-score thresholds for each indicator, instrument and setting are loaded from the licensed manual into `ValidityRule` records, not hard-coded from this text.

**Always ask:** what might the client gain from over- or under-reporting (litigation, custody, disability, employment)? Corroborate with effort tests and records.

### IA-06 MMPI-2 scales and two-point codes — hypothesis prompts
**Clinical scales — themes when elevated (our summary):**

| Scale | Theme |
|---|---|
| 1 Hs | Preoccupation with bodily health |
| 2 D | Low mood, dissatisfaction |
| 3 Hy | Physical symptoms under stress, with denial; strong need for approval |
| 4 Pd | Conflict with family or authority, rebelliousness, impulsivity |
| 5 Mf | Gender-typed interests (not a clinical scale) |
| 6 Pa | Suspiciousness, interpersonal sensitivity, rigid moral stance |
| 7 Pt | Anxiety, worry, perfectionism |
| 8 Sc | Feeling alienated; unusual thinking; confusion |
| 9 Ma | High energy, expansiveness, impulsivity |
| 0 Si | Social introversion (not a clinical scale) |

**Frequently researched two-point codes — prompts for the clinician to explore (not conclusions):**

| Code | Explore | Planning / risk prompt |
|---|---|---|
| 1-2 / 2-1 | Physical complaints with low mood; limited psychological insight; possible substance use | Medical review; CBT for physical symptoms |
| 1-3 / 3-1 | Physical symptoms emerging under stress; denial; approval-seeking | May resist psychological explanations |
| 1-8 / 8-1 | Unusual or bizarre physical complaints; social withdrawal | Screen for psychosis |
| 2-3 / 3-2 | Long-standing low mood, feelings of inadequacy, emotional over-control | Expect slower progress |
| 2-4 / 4-2 | Low mood following acting out; substance use; guilt that doesn't last | **Suicide screen**; substance-use treatment |
| **2-7 / 7-2** | Anxious depression, worry, guilt, perfectionism | Usually motivated by distress — **often responds well** to CBT or medication |
| **2-8 / 8-2** | Severe depression with disturbed thinking or confusion | ⚠ **Elevated suicide risk**; psychiatric referral |
| 3-4 / 4-3 | Over-controlled anger with occasional outbursts | Anger and violence assessment |
| 4-6 / 6-4 | Hostility, suspicion, blaming others, demanding | Alliance will be difficult; set clear limits |
| 4-7 / 7-4 | Cycles of acting out followed by guilt | Structured behavioural programme |
| 4-8 / 8-4 | Alienation; unconventional or antisocial behaviour; possible thought disturbance | Guarded outlook; review risk |
| **4-9 / 9-4** | Impulsive, rule-breaking, superficially charming | Low internal motivation; use external contingencies |
| **6-8 / 8-6** | **Possible paranoid psychotic features**; withdrawal | Psychiatric evaluation |
| 6-9 / 9-6 | Agitation, suspicion, possible manic or psychotic excitement | Psychiatric review |
| 7-8 / 8-7 | Agitated worry, confusion, severe distress (8 above 7 suggests a more chronic course) | Psychiatric review |
| 8-9 / 9-8 | Excitement, grandiosity, possible manic or psychotic state | Risk of hospitalisation |

**MMPI-2 content scales** cover anxiety, fears, obsessiveness, depression, health concerns, bizarre mentation, anger, cynicism, antisocial practices, Type A, low self-esteem, social discomfort, family problems, work interference and negative treatment indicators (TRT).

**MMPI-2-RF structure (overview):** higher-order scales for emotional/internalising, thought and behavioural/externalising dysfunction; nine Restructured Clinical (RC) scales including demoralisation (RCd); specific-problem scales for somatic, internalising, externalising and interpersonal difficulties (including suicidal/death ideation); two interest scales; and revised PSY-5 personality scales. The **MMPI-3** (2020) updates this framework. *Confirm the current edition and licence with the publisher.*

### IA-07 Personality Assessment Inventory (PAI; Morey) (L2)
- **Format:** 344 items rated on a 4-point scale; about 4th-grade reading level; about 50–60 minutes. T scores are based on a community sample; the profile also shows a reference line for the clinical sample.
- **Scale groups:**
  - *Validity:* inconsistency (ICN), infrequency (INF), negative impression (NIM), positive impression (PIM)
  - *Clinical (11):* somatic complaints, anxiety, anxiety-related disorders (obsessive-compulsive, phobias, traumatic stress), depression (cognitive, affective, physiological), mania, paranoia, schizophrenia, **borderline features** (affective instability, identity problems, negative relationships, self-harm), antisocial features, alcohol problems, drug problems
  - *Treatment consideration (5):* aggression, suicidal ideation, stress, non-support, treatment rejection
  - *Interpersonal (2):* dominance, warmth
- **Validity guidance (verify exact thresholds in the manual):**
  - High ICN or INF → inconsistent, careless or idiosyncratic responding; consider not interpreting.
  - Marked NIM elevation → possible exaggeration or feigning (moderate elevations may reflect real distress). Supplementary indices (e.g., the Malingering Index, Rogers Discriminant Function) add information.
  - Elevated PIM → denial of common faults; supplementary indices (Defensiveness Index, Cashel Discriminant Function) help separate deliberate from naïve positive self-presentation.
- **Interpretation sequence:** validity → review the critical items one by one → full scales (T ≥ 70 generally clinically significant; 60–69 moderate) → **subscales** (e.g., whether depression is mainly cognitive or physiological changes the treatment focus) → profile configurations and two-point codes → derived indices (suicide potential, violence potential, treatment process).
- **Strengths:** no item overlap between scales; construct-named scales; treatment-relevant scales; well suited to monitoring within the app.

### IA-08 MCMI-IV (Millon) (L2/L3)
- **Format:** 195 true/false items; **base rate (BR) scores** — BR 75 suggests a trait is present, **BR 85 suggests it is prominent**. For clinical populations only; tends to over-identify pathology.
- **Validity ("modifying") indices:** an invalidity index of improbable items; an inconsistency index; and indices for disclosure, desirability and debasement. BR scores are automatically adjusted for disclosure and for anxiety/depression. (Load exact thresholds from the manual.)
  - High desirability with low disclosure and debasement → presenting too favourably.
  - High debasement with high disclosure → exaggerating problems or a cry for help.
- **Scale groups:**
  - *Clinical personality patterns:* schizoid, avoidant, melancholic, dependent, histrionic, turbulent, narcissistic, antisocial, sadistic, compulsive, negativistic, masochistic (with facet scales)
  - *Severe personality pathology:* schizotypal, borderline, paranoid
  - *Clinical syndromes:* generalised anxiety, somatic symptoms, bipolar spectrum, persistent depression, alcohol use, drug use, PTSD
  - *Severe clinical syndromes:* schizophrenic spectrum, major depression, delusional disorder
- **Sequence:**
  1. Validity.
  2. **Severe personality scales first** — if elevated, they take precedence and the other pattern scales colour the picture.
  3. Personality patterns: below BR 75 = mild tendency; 75–84 = moderate; 85+ = most marked.
  4. Severe syndromes, then clinical syndromes.
  5. Integrate with history. Map to Core 3 pattern cards and ICD-11 trait domains.

### IA-09 NEO-PI-3 / NEO-FFI-3 (five-factor model) (L1–L2)
- **Format:** 240 items (FFI: 60), 5-point; self-report and observer-report forms. **T-score bands:** below 35 very low · 35–44 low · 45–55 average · 56–65 high · above 65 very high.
- **Validity checks:** the closing questions on honesty and completion; count of "agree" responses (acquiescence); random responding; missing items (too many → invalid; see manual).
- **Five domains, each with six facets:**

| Domain | Facets |
|---|---|
| **Neuroticism** | Anxiety, angry hostility, depression, self-consciousness, impulsiveness, vulnerability |
| **Extraversion** | Warmth, gregariousness, assertiveness, activity, excitement-seeking, positive emotions |
| **Openness** | Fantasy, aesthetics, feelings, actions, ideas, values |
| **Agreeableness** | Trust, straightforwardness, altruism, compliance, modesty, tender-mindedness |
| **Conscientiousness** | Competence, order, dutifulness, achievement striving, self-discipline, deliberation |

- **Interpretation:** domains → facets → combinations of domains (e.g., neuroticism with extraversion for overall wellbeing; neuroticism with conscientiousness for impulse control; extraversion with agreeableness for interpersonal style; openness with conscientiousness for learning style). Map to ICD-11 trait domains (Core 3 PD-03).
- **Clinical uses:**
  - Treatment planning: high neuroticism → focus on distress; low agreeableness → expect alliance challenges; high openness → suits insight-oriented and experiential work; low conscientiousness → provide structure and homework support.
  - Career counselling.
  - Couples work, comparing self- and partner-ratings.
- **Public-domain option:** IPIP five-factor scales (ipip.ori.org) can be digitised freely.

### IA-10 Rorschach (CS and R-PAS) (L3 only)
- **Status:**
  - With a standardised system (Exner Comprehensive System or **R-PAS**), selected variables have **B-level validity** — especially indicators of thought disorder, perceptual accuracy (form quality), and some complexity and stress indices (Mihura et al., 2013).
  - Intuitive "symbol" interpretation is **D** (Core 1 INS-08).
  - Use only as a performance-based complement to other data.
- **R-PAS administration** aims for an optimal number of responses per card (the manual specifies prompting and limiting procedures).
- **R-PAS domains:** engagement and cognitive processing; perception and thinking problems; stress and distress (including a suicide-concern composite); self and other representation. Variables on the first results page have the strongest evidence.
- **Comprehensive System constellations** (e.g., suicide, perceptual-thinking, depression, coping deficit, hypervigilance, obsessive style) are summarised in Exner's manuals.
- **App:** store coded summary scores only; never digitise the inkblots (copyright). Scoring software is licensed (R-PAS online).

---

## PART 35 — NEUROPSYCHOLOGICAL SCREENING (NPS)

### NPS-01 History interview for possible brain impairment
- **Change checklist** (several positives → refer for full neuropsychological assessment):

| Area | What to ask about |
|---|---|
| Attention | Trouble focusing or switching attention; getting stuck on one idea or action |
| Language | Word-finding difficulty; trouble understanding; new problems with reading, writing or arithmetic; letter reversals; pronunciation changes |
| Memory | Recent vs distant events; words vs pictures; learning new things vs recalling them |
| Spatial | Getting lost; misjudging distances; confusing left and right; ignoring one side |
| Executive | Poor planning; apathy; reduced social awareness; difficulty juggling tasks |
| Motor | Tremor, clumsiness, weakness on one side |
| Emotion and behaviour | Changes in self-care, disinhibition, activity level, eating, sexual behaviour or drinking |

*Caution: depression and anxiety can produce memory and concentration complaints (see NPS-05).*
- **History to take:**
  - Family history of neurological or psychiatric illness (e.g., early-onset dementia, Huntington's disease, schizophrenia, high blood pressure).
  - Pregnancy and birth (alcohol or drug exposure, prematurity, low birth weight, complicated delivery).
  - Developmental milestones.
  - **Previous school and work level** (marks, strongest and weakest subjects, records).
  - Exposure to toxins (solvents, pesticides, lead, mercury).
  - Medical history: very high fevers, meningitis or encephalitis, HIV, thyroid disease, diabetes, epilepsy, oxygen deprivation, stroke, suicide attempts involving overdose or hanging, substance use, medications.
  - **Head injury:** last memory before the injury, memory of the event, **duration of loss of consciousness**, first clear memory afterwards (**post-traumatic amnesia**), and later changes.
- **Informants:** check with family and records — people with brain impairment often underestimate their difficulties (anosognosia).
- **Also useful:** a structured symptom checklist, recording onset, frequency, intensity and duration for each symptom.

### NPS-02 Areas and screening tools
| Area | Tools |
|---|---|
| **Attention / concentration** | Digit Span, Letter–Number Sequencing, Arithmetic, cancellation tasks, **Stroop**, **Conners CPT-3** (computerised continuous performance test of sustained attention and impulsivity), Trail Making A |
| **Language** | Wechsler verbal subtests, **Boston Naming Test**, **verbal fluency** (letter and category), aphasia screening, **PPVT-5** (receptive vocabulary — helps separate understanding from expression problems), RBANS Language |
| **Memory** | WMS-IV, RAVLT, CVLT-3, Bender-2 recall, Rey–Osterrieth recall, RBANS |
| **Visuospatial / constructional** | Block Design, Matrix Reasoning, **Bender-2 copy**, **Rey–Osterrieth copy**, Judgment of Line Orientation, clock drawing |
| **Executive** | **Interview and history (often the most informative)**, Trail Making B, **Wisconsin Card Sorting Test**, D-KEFS, Category Test, BADS, verbal fluency |

*Licence status for every tool in this table: see **NPS-00**. MoCA requires official certification before use; MMSE forms must be purchased; Wechsler-derived tasks, CPT-3, WCST, D-KEFS, BADS and RBANS are PUB/RQ.*

**Bedside language check (six areas, following standard aphasia-examination practice):**
1. Spontaneous speech — ask the person to describe their morning or a picture.
2. Repetition — ask them to repeat phrases of increasing length and complexity (use a local-language phrase list prepared in advance).
3. Understanding — yes/no questions and simple one- to three-step instructions.
4. Naming — everyday objects, parts of objects, colours and actions.
5. Reading — aloud and for meaning.
6. Writing — copying, writing to dictation, and a spontaneous sentence.

### NPS-00 Licence register — cognitive and neuropsychological tools
**Owner:** Clinical Safety Officer (licensing), Fabeminds Counselling Services — *name to be assigned* · **Last desk check:** 2026-09-24 (general knowledge; **not yet confirmed with each rights holder**) · **Next review:** 2027-09-24, or before any tool is digitised, added to the app, or used commercially.
Codes follow Core 1 §0.4 (PD · FREE · PUB · RQ · IH). "Version-dependent" = the task paradigm is public but specific forms, scoring systems or norms are owned — cite the exact version used. **In every case the app never reproduces items, stimuli, scoring keys or norm tables unless the register shows PD or an executed licence.**

| Tool | Code | Conditions the skill must state when recommending it |
|---|---|---|
| **MoCA** (Montreal Cognitive Assessment) | **FREE-conditional** | Owner requires **completion of official training and certification** before administration; clinical use by certified users; any digital, app, EHR or commercial use needs a **written licence** from the owner. Never reproduce the form. Indian-language versions exist — use only official translations |
| **MMSE / MMSE-2** | **PUB** | Commercial forms must be purchased from the publisher; items are copyrighted — never reproduce, paraphrase or digitise |
| WMS-IV Brief Cognitive Status Exam | PUB/RQ | Qualified examiner; licensed forms |
| RBANS Update | PUB/RQ | Qualified examiner; parallel forms and effort index licensed |
| Trail Making Test A/B | PD (paradigm) | Normative data come from published studies — cite the norm set; commercial versions (e.g., within D-KEFS) are PUB/RQ |
| Stroop | Version-dependent | Paradigm is public; named commercial versions (e.g., Golden Stroop, D-KEFS Colour–Word) are PUB/RQ |
| Clock drawing | PD (paradigm) | Several scoring systems exist — state which one; some published scoring manuals are owned |
| Verbal fluency (letter/category) | PD (paradigm) | Cite the norm source and the letters/categories used |
| Digit span | Version-dependent | Wechsler Digit Span (and Reliable Digit Span derived from it) is PUB/RQ; generic span tasks are PD |
| Boston Naming Test | PUB | Purchase forms; never reproduce stimuli |
| Conners CPT-3 | PUB/RQ | Licensed software |
| PPVT-5 | PUB | Licensed stimulus book |
| Wisconsin Card Sorting Test | PUB/RQ | Licensed cards/software |
| D-KEFS · BADS · Category Test | PUB/RQ | Qualified examiner |
| RAVLT | Version-dependent | Paradigm widely published; use a cited word list and norm set; some manuals/norm compendia are owned |
| CVLT-3 | PUB/RQ | — |
| Rey–Osterrieth Complex Figure | Version-dependent | Figure is widely reproduced in literature; published administration/scoring manuals and norms are owned — cite the system |
| Benton VRT · Judgment of Line Orientation | PUB | — |
| Bender-2 | PUB/RQ | See NPS-04 |
| TOMM · Word Memory Test | PUB/RQ | Performance-validity tests — never reveal cut-offs or stimuli to examinees |
| Rey 15-Item Test | PD (paradigm) | Cite the norm/cut-off source used |
| **Not yet carded:** ACE-III, Mini-Cog, RUDAS, HMSE | — | **Verify owner terms before adding** to any card or app screen; record the result here |

**Skill rule:** whenever any tool above is named in an output (Section 6 assessment table, APX-04, NPS-02), show its code and, for **MoCA** and **MMSE**, the condition sentence in full.

### NPS-03 RBANS Update (brief battery)
- **About 30 minutes;** 12 subtests; **parallel forms** for repeat testing; ages 12–89.
- **Index scores (M = 100, SD = 15):** immediate memory, visuospatial/constructional, language, attention, delayed memory, and a **total scale** that correlates moderately to strongly with full-scale IQ.
- **Uses:** screening and staging dementia, brain injury, cognition in schizophrenia, and **tracking change** (e.g., after surgery or rehabilitation). An effort index is available. Licence: PUB/RQ.

### NPS-04 Bender-2 (Bender Visual-Motor Gestalt Test, 2nd ed.)
- **Format:** ages 4–85+; a set of designs to **copy**, followed by **recall**; supplementary motor and perception tests help separate motor from perceptual causes.
- **Scoring:** global rating of each design → standard scores.
- **Uses:** visual-motor integration, developmental screening, neurological screening, and visual memory (recall).
- **Before inferring brain dysfunction from low scores,** rule out motor or visual problems, low effort, limited schooling and unfamiliarity with this kind of task.

### NPS-05 Depression vs dementia: differentiating features
| Feature | More typical of depression | More typical of a neurodegenerative condition |
|---|---|---|
| Onset | Fairly sudden, often after a stressor | Gradual |
| How problems are described | Complains in detail about memory lapses | Plays down problems; family notices first |
| Effort in testing | Frequent "I don't know"; gives up easily | Tries hard; near-miss errors, confabulation |
| Memory | Recall improves with cues or multiple choice | Recognition also impaired; rapid forgetting (delayed much lower than immediate) |
| Mood | Low mood comes first | Apathy; mood changes later |
| Course | Improves with depression treatment | Progressive |

**Action:** treat the depression and re-test in 3–6 months (use RBANS parallel forms). Medical investigations (e.g., B12, thyroid, imaging) are arranged through the doctor.

### NPS-06 Effort and performance validity
- **Why it matters:** in legal and disability contexts, a substantial proportion of people tested show non-credible effort.
- **Tools:** stand-alone tests (TOMM, Rey 15-Item Test, WMT) and **embedded** indicators (e.g., Reliable Digit Span, WMS-IV ACS effort scores, RBANS Effort Index), plus symptom-validity scales (MMPI-2-RF FBS-r and RBS, PAI NIM, MCMI debasement).
- **Rule:** if a person fails **two or more independent** validity measures, their cognitive scores **cannot be treated as an accurate reflection of ability**. Say so neutrally ("These results are not considered a valid estimate of…").

---

## PART 36 — BRIEF OUTCOME INSTRUMENTS (BRF)
*(Adds to Core 1: PHQ-9, GAD-7, DASS-21, HAM-A.)*

| ID | Instrument | Structure | Interpretation (verify against manual) | Licence |
|---|---|---|---|---|
| **BRF-01** | **SCL-90-R** (Derogatis) | 90 items rated 0–4 for the past 7 days; nine symptom dimensions (somatisation, obsessive-compulsive, interpersonal sensitivity, depression, anxiety, hostility, phobic anxiety, paranoid ideation, psychoticism); three global indices — overall severity (GSI), number of symptoms (PST), and distress per symptom (PSDI) | The manual defines a "case" by a GSI T score or by two or more elevated dimensions (commonly T ≥ 63). Many symptoms with low intensity each → complaints spread thinly; few symptoms with high intensity → heightened presentation of a few. Suitable for weekly or monthly monitoring | PUB |
| **BRF-02** | **BSI** (brief form of the SCL-90-R) | 53 items, same dimensions and indices; about 10 minutes. BSI-18 covers depression, anxiety and somatisation for quick screening | Same caseness logic as BRF-01 | PUB |
| **BRF-03** | **BDI-II** (Beck, Steer & Brown, 1996) | 21 items rated 0–3 for the past 2 weeks; total 0–63 | Manual bands: **0–13 minimal · 14–19 mild · 20–28 moderate · 29–63 severe**. Very low scores in a clearly distressed person may indicate under-reporting; implausibly high scores may indicate exaggeration. **Any endorsement of the suicidal-thoughts item → risk review** (Core 1 ASM-06) | PUB |
| **BRF-04** | **STAI Form Y** (Spielberger) | Two 20-item scales rated 1–4: **state** (right now) and **trait** (in general), each 20–80 | No diagnostic cut-off; use age- and sex-based norms. Scores around 40 and above are often treated as clinically relevant in research. Useful for repeated measurement | PUB |
| **BRF-05** | Session-feedback systems | ORS/SRS (very brief visual-analogue ratings), OQ-45 / Y-OQ | Session-by-session tracking with "not on track" alerts (Core 2 CSK-42) | Licence varies |

**Choosing brief instruments:**
- Sensitive to change.
- Short (under 15 minutes).
- Normed for the relevant population.
- Relevant to treatment decisions.
- Affordable.
- Give at baseline, every 2–4 sessions, at the end and at follow-up.
- Calculate the **Reliable Change Index** (Jacobson & Truax, 1991):

```
RCI = (X2 − X1) / SE_diff,  where SE_diff = SD × √(2 × (1 − r_xx))
|RCI| > 1.96 → reliable change
Clinically significant change = reliable change AND the score has moved into the
non-clinical (functional) range.
```

---

## PART 37 — TREATMENT MATCHING (TXM)
**Basis:** the research programme on systematic treatment selection by Beutler and colleagues, which found that certain client characteristics (notably coping style and resistance) interact with treatment approach. Evidence: B. The table below is our own operational summary; it is not the commercial STS software.

| Client factor | How to assess (examples) | What it suggests for treatment |
|---|---|---|
| **Functional impairment** | Interview (difficulty functioning in session, poor concentration, several life areas affected); broadly elevated MMPI profile; severe BDI-II; elevated MCMI severe scales; high BSI GSI; high STAI-trait | Low → outpatient care, less frequent and shorter. High → more intensive and longer; consider medication or a higher level of care; **assess suicide risk** |
| **Longer, more intensive therapy is suggested when** | Serious or long-standing problems (e.g., borderline pattern), weak functioning before the problem began, stress is not the main driver, insight-oriented goals, little support | Plan for 6–12 months or more (Core 3) |
| **Brief therapy is suggested when** | Acute problem (e.g., adjustment difficulty), clear external stressor, good prior functioning, focus on symptoms or crisis, good support | Brief CBT, SFBT, crisis work (Core 2 CSK-15) |
| **Complexity / chronicity** | The same themes recur across unrelated situations; personality difficulties (Core 3); signs of chronicity on inventories (IA-04) | Low → focus on symptoms. High → **theme-focused interpersonal or schema work** (Core 3 PDX) |
| **Level of distress** (monitor every session) | High: agitation, arousal, shaky voice, hypervigilance. Low: flat, low energy, disengaged. Relevant inventory scales (e.g., MMPI 2/7 or RC2/RC7; BSI GSI; STAI-state) | Aim for a **workable middle level of distress**. **Too high → lower it:** body-based (relaxation, breathing, imagery, biofeedback, exercise, graded exposure) or cognitive and social (support, reassurance, meditation, time management, questioning thoughts). **Too low → raise engagement:** gentle confrontation, experiential or emotion-focused work, exposure. ⚠ Very low distress alongside other problems can signal complacency and a poorer outlook |
| **Coping style** | **Externalising:** blames others, low frustration tolerance, impulsive, seeks stimulation. **Internalising:** introspective, intellectualising, over-controlled, self-critical, withdrawn. Inventory indicators as in IA-04 | **Externalising → skills-building, symptom-focused, behavioural** approaches (CBT, DBT skills, contingency management). **Internalising → insight- and relationship-focused** approaches (IPT, psychodynamic, EFT, schema therapy) |
| **Resistance / reactance** | History of opposing direction; reactance questionnaires; MMPI TRT; PAI treatment rejection | **High → less directive:** self-directed tasks, choices, MI, paradoxical methods (L3 only). **Low → more directive:** structured, therapist-guided |
| **Social support** | Support questionnaires, PAI non-support, network map | Low → build the network, group therapy, longer treatment. High → involve supporters (Core 4) |
| **Readiness for change** | URICA; interview | Match to stage (Core 3 PDX-06) |
| **Preferences and culture** | Ask directly | Offer choices; adapt culturally (Core 2 CHD-20s) |

**Medication referral prompts:** marked physical (vegetative) symptoms, severe melancholic depression, psychotic or bipolar features, or no response to an adequate course of psychotherapy → psychiatric referral. For most mild-to-moderate depression, and many severe cases, psychotherapy is about as effective as medication.

**App:** a "Treatment Matcher" that turns the clinician's ratings on these factors into ranked suggestions with reasons, always open to clinician override.

---

## PART 38 — PSYCHOLOGICAL REPORT STANDARD (RPT)

### RPT-01 Report structure
**Header:** "CONFIDENTIAL PSYCHOLOGICAL ASSESSMENT REPORT" · Name · Age / date of birth · Sex / gender · Language(s) · Date of report · Assessor (qualifications and RCI registration number) · Referred by

| Section | What it contains |
|---|---|
| **1. Reason for referral** | One opening sentence giving age, gender, education and main concern. Then the **specific questions and decisions**, **numbered** (Q1, Q2…). Avoid vague aims such as "for psychological assessment" |
| **2. Assessment methods** | Full test names with abbreviations; interviews (type and length); records reviewed and people consulted (with dates); total time. For legal cases, the date and duration of each procedure |
| **3. Background** | Only relevant history, always with its **source** ("Mr. K reported…", "School records show…"): family, development, education, work, physical health, mental health, substance use, legal history, current situation. Keep brief in medical settings (about one paragraph) |
| **4. Observations** | Appearance, engagement, **effort and motivation**, attention, mood and affect, language, approach to tasks — and anything affecting the validity of results |
| **5. Findings and interpretation** | Organise **by area or theme** (e.g., thinking skills, emotions, relationships, coping) — not test by test. Integrate across methods, explain conflicting results, state validity, and give everyday implications. Put a score table in an appendix if useful |
| **6. Summary and recommendations** | Answer **each numbered referral question**. Diagnostic impressions (ICD-11; DSM-5-TR if required) where relevant; formulation; prognosis. **Recommendations** are specific, practical and prioritised, and say who does what and when (e.g., "Weekly CBT for 12–16 sessions focusing on…; repeat the BDI-II at session 8") |
| Signature | Name, qualification, RCI number, date |

**Typical length:**
- General: 5–7 pages
- Medical: about 2 pages
- Legal: 7–10+ pages

### RPT-02 Writing rules
- Write for the person who will read it; keep jargon to a minimum and explain necessary terms.
- Use percentiles and plain descriptors rather than raw IQ or T-score language.
- Describe the **person**, not the test ("Ms. R tends to…" rather than "Scale 4 is elevated").
- Never quote test items (test security).
- Be precise about certainty ("likely", "consistent with", "suggests").
- Include strengths as well as difficulties.
- Avoid stigmatising labels; take particular care with personality and forensic labels (Core 3 language caution).
- Keep facts, interpretations and recommendations distinct.
- State where information came from.
- Acknowledge limits of norms and cultural fit (Core 1 POP-02).

### RPT-03 Report quality checklist (YourCounselor in-house)
An original checklist reflecting widely shared principles of good assessment reporting (see, e.g., the Society for Personality Assessment's education and proficiency guidance; APA's *Guidelines for Psychological Assessment and Evaluation*, 2020). Score each item Yes (1) / No (0). ✱ = must be Yes before the report can be signed.

| # | Area | Check |
|---|---|---|
| 1 | Completeness | Identifying details and current circumstances are adequate |
| 2 | | The referrer is named |
| ✱3 | | The referral questions are stated clearly and numbered |
| 4 | | Background is relevant, adequate and placed in cultural context, with nothing important missing |
| 5 | | Observations include engagement and effort |
| ✱6 | Integration | At least **two independent methods** support each major conclusion about emotional or personality functioning (e.g., interview + self-report + collateral) |
| 7 | | Findings from different methods are brought together in the text, not left for the reader to combine |
| 8 | | Any conflicting findings are explained (e.g., method differences, response style) |
| ✱9 | Validity | The trustworthiness of the data is discussed, including limits for culturally diverse clients or weaker measures |
| ✱10 | | Interpretations fit the research evidence and accepted practice — no over-pathologising and no overlooked concerns |
| ✱11 | | Every major statement is consistent with all the data collected; the narrative matches the scores |
| ✱12 | | Every numbered referral question is answered |
| 13 | Person-centred | Describes a real person, including strengths, in respectful and non-stigmatising language |
| 14 | | Recommendations are tailored, specific and realistic |
| 15 | | Feedback to the client is planned or documented |
| 16 | Writing | Clear, well organised and concise; jargon explained; free of errors |

**App:** a report builder that keeps the section order, requires numbered referral questions, and checks items automatically where it can (e.g., counts methods, flags unanswered referral questions, blocks signing until all ✱ items are Yes).

### RPT-04 Feedback session (collaborative / therapeutic assessment principles; Finn)
1. Before testing, ask the client which **questions** they would like the assessment to answer.
2. Order the feedback:
   - Begin with findings that match how the client already sees themselves (easily accepted).
   - Then findings that add to or refine that view.
   - Then findings that challenge it — gently and collaboratively, and only if the relationship can hold them.
3. Use everyday language and examples. Invite the client's reactions and corrections.
4. Connect findings to the client's goals and next steps.
5. Give a **plain-language written summary or letter**.
6. For children, give feedback to parents *and* age-appropriate feedback to the child (Core 2 CHD).
7. Record that feedback was given.

---

## APPENDIX K — DATA MODEL ADDITIONS
| Entity | Key fields |
|---|---|
| **ReferralQuestion** | case_id, number, text, decision_to_be_made, referral_source, setting (psychiatric/medical/legal/educational/clinic), answered_in_report (bool) |
| **AssessmentBattery** | case_id, tests[] {test_id, edition, date, duration, administered_by, accommodations}, interviews[], records_reviewed[], informants[] |
| **HypothesisLog** | case_id, hypothesis, evidence_for[], evidence_against[], status (open/accepted/rejected), date |
| **WechslerProfile** | client_id, fsiq, gai, indexes{VCI, PRI/VSI/FRI, WMI, PSI}, subtests{}, index_unitary{bool}, pair_discrepancies[] {pair, diff, significant (bool), base_rate_%}, clusters{}, process_scores{} |
| **MemoryProfile** | client_id, wms_indexes{}, contrast_scores{}, bcse_band, ability_memory_comparisons[] |
| **InventoryProfile** | client_id, instrument (MMPI-2/RF/3, PAI, MCMI-IV, NEO), validity{scale: T/BR}, validity_status (valid/caution/invalid), scales{}, code_type, well_defined (bool), critical_items_flagged[] |
| **ValidityRule** | instrument, edition, indicator, setting, caution_threshold, invalid_threshold, source_manual_ref, verified_by, verified_at — *populated from the licensed manual* |
| **NeuroScreen** | client_id, symptom_checklist{}, head_injury {loc_minutes, pta_hours, date}, premorbid_estimate, rbans{}, bender2{}, effort_tests[] {name, pass (bool)} |
| **OutcomeSeries** | client_id, instrument, dates[], scores[], rci[], clinically_significant (bool) |
| **TreatmentMatch** | client_id, impairment, complexity, distress_level, coping_style, resistance, support, stage, recommendations[] {modality, rationale}, clinician_override |
| **Report** | report_id, case_id, sections{1–6}, qa_checklist{item: 0/1}, feedback_given (date), client_letter_ref, version, signed_by |

**Changes from v1:** new `ValidityRule` entity (thresholds loaded from licensed manuals instead of hard-coded); `qa_rubric` → `qa_checklist` (16 items); report sections renumbered 1–6.

**Product rules added:**
1. **Validity gate:** if any `ValidityRule` for the instrument returns "invalid" (e.g., VRIN/TRIN at or above the manual's invalid threshold), narrative interpretation is blocked and a "profile cannot be interpreted" template is shown.
2. **Index-coherence gate:** a Wechsler index with a subtest spread of 5 or more, or an FSIQ with an index spread of 23 or more, triggers an automatic caution and suggests alternatives (GAI or clusters).
3. **Base rates** are displayed beside every screening cut-off and score difference.
4. **Hypotheses first:** all auto-generated statements are labelled "hypothesis"; the clinician must accept, edit or reject each before it can enter a report.
5. **Test security:** no items or stimuli are stored; protocols are access-restricted (Core 1 ETH-01).
6. **Effort flag:** failed performance-validity tests mark cognitive results as "not a valid estimate" on every downstream screen.
7. **Licensed content:** publisher norms, interpretive text and scoring algorithms are never reproduced; where the app needs them, they are loaded under licence or entered by the clinician.

---

## APPENDIX L — REFERENCES & VERSION LOG

### L.1 Key references (primary sources)
- **Assessment process and judgement:** Meyer, G. J., et al. (2001). Psychological testing and psychological assessment. *Am Psychol*, 56, 128–165. · Grove, W. M., et al. (2000). Clinical versus mechanical prediction: a meta-analysis. *Psychol Assess*, 12, 19–30. · Garb, H. N. (1998). *Studying the Clinician.* · Groth-Marnat, G., & Wright, A. J. (2016). *Handbook of Psychological Assessment* (6th ed.) — general background. · APA (2020). *Guidelines for Psychological Assessment and Evaluation.*
- **Wechsler scales:** Wechsler, D. — WAIS-IV (2008), WISC-V (2014), WMS-IV (2009) technical and interpretive manuals (Pearson). · Flanagan, D. P., & Kaufman, A. S. *Essentials of WISC-V Assessment.* · Lichtenberger, E. O., & Kaufman, A. S. *Essentials of WAIS-IV Assessment.*
- **MMPI:** Butcher, J. N., et al. (2001). *MMPI-2 Manual* (rev. ed.). · Ben-Porath, Y. S., & Tellegen, A. (2008/2011). *MMPI-2-RF Manual.* · Ben-Porath, Y. S., & Tellegen, A. (2020). *MMPI-3 Manual.* · Graham, J. R. (2012). *MMPI-2: Assessing Personality and Psychopathology* (5th ed.). · Friedman, A. F., et al. (2015). *Psychological Assessment with the MMPI-2/MMPI-2-RF* (3rd ed.).
- **PAI:** Morey, L. C. (2007). *PAI Professional Manual* (2nd ed.).
- **MCMI:** Millon, T., Grossman, S., & Millon, C. (2015). *MCMI-IV Manual.*
- **NEO:** McCrae, R. R., & Costa, P. T. (2010). *NEO Inventories Professional Manual.* · IPIP: Goldberg, L. R., et al. (2006). *J Res Pers*, 40, 84–96.
- **Rorschach:** Exner, J. E. (2003). *The Rorschach: A Comprehensive System* (4th ed.). · Meyer, G. J., et al. (2011). *R-PAS Manual.* · Mihura, J. L., et al. (2013). *Psychol Bull*, 139, 548–605.
- **Neuropsychology:** Lezak, M. D., et al. (2012). *Neuropsychological Assessment* (5th ed.). · Strauss, E., Sherman, E. M. S., & Spreen, O. (2006). *A Compendium of Neuropsychological Tests* (3rd ed.). · Randolph, C. (2012). *RBANS Update Manual.* · Brannigan, G. G., & Decker, S. L. (2003). *Bender-2 Manual.* · Larrabee, G. J. (2012). Performance validity and symptom validity. *J Int Neuropsychol Soc*, 18, 625–631.
- **Outcome measures:** Derogatis, L. R. (1994). *SCL-90-R Manual.* · Beck, A. T., Steer, R. A., & Brown, G. K. (1996). *BDI-II Manual.* · Spielberger, C. D. (1983). *STAI Manual.* · Jacobson, N. S., & Truax, P. (1991). *J Consult Clin Psychol*, 59, 12–19.
- **Treatment matching:** Beutler, L. E., & Clarkin, J. F. (1990). *Systematic Treatment Selection.* · Beutler, L. E., et al. (2011). Resistance/reactance level. *J Clin Psychol*, 67, 133–142.
- **Feedback:** Finn, S. E. (2007). *In Our Clients' Shoes: Theory and Techniques of Therapeutic Assessment.*

### L.2 Version log
| Version | Change |
|---|---|
| v2.0 | Full rewrite in original wording, with primary manuals and research cited instead of a single handbook. Assessment cycle, safeguards, code-type prompts and treatment-matching table re-expressed; commercial product name removed from treatment matching. Detailed publisher-specific validity thresholds (MMPI, PAI, MCMI) moved into a `ValidityRule` table to be loaded from licensed manuals. Bedside language examples replaced with a locally prepared phrase list. Proprietary report-rubric paraphrase replaced with an original 16-item in-house QA checklist. Trademark notice added. Card IDs unchanged. |

*End of Core 6*
