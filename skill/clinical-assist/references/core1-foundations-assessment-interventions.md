# CORE 1 — Foundations, Assessment & Interventions
### YourCounselor AI · Clinical Practice Knowledge Base · Core 1 · v2.0 (original-text edition)

**About this edition:** v2.0 is written in original wording for YourCounselor AI. It draws on general, widely taught knowledge in psychometrics, clinical assessment and psychotherapy, and cites the primary research literature where a specific model, formula or instrument is named. Facts, formulas, test names and scientific findings are stated in our own words; no textbook, course handout or third-party clinical booklet is reproduced. The only verbatim third-party text is the item wording of instruments whose owners allow free reproduction (see PART 5, INS-14), each shown with its required citation.

> **Status:** Draft for expert review. A qualified clinician must check clinical cut-offs and protocols, and a legal adviser must check licensing and legal statements, before release.


## Contents (card index — grep the ID to jump to it)
  - YourCounselor AI · Clinical Practice Knowledge Base · Core 1 · v2.0 (original-text edition)
- PART 0 — HOW THIS KNOWLEDGE BASE IS ORGANISED (read first)
  - 0.1 Design principles
  - 0.2 ID scheme
  - 0.3 Evidence grades
  - 0.4 Licence codes (for software)
  - 0.5 User competence levels
  - 0.6 Standard card templates
- PART 1 — FOUNDATIONS OF PSYCHOLOGICAL TESTING (FND)
  - FND-01 Core definitions
  - FND-02 What makes something a test
  - FND-03 What tests are used for
  - FND-04 Ways of classifying tests
  - FND-05 Testing vs assessment in day-to-day practice
  - FND-06 Historical timeline (training modules)
  - FND-07 Qualities of a good test
- PART 2 — PSYCHOMETRIC TOOLKIT (PSY)
  - PSY-01 Classical Test Theory
  - PSY-02 Where score differences come from
  - PSY-03 Ways to estimate reliability
  - PSY-04 Formulas
  - PSY-05 What influences reliability
  - PSY-06 Validity
  - PSY-07 Decision accuracy (required for every screening tool)
  - PSY-08 Item analysis
  - PSY-09 Writing items for in-house questionnaires
  - PSY-10 Norms and derived scores
  - PSY-11 Response bias
- PART 3 — ETHICS, LAW & PROFESSIONAL STANDARDS (ETH)
  - ETH-01 Ethical principles for testing and assessment
  - ETH-02 Indian legal context (confirm with a legal adviser before release)
  - ETH-03 Ethics specific to the app
- PART 4 — CLINICAL WORKFLOW, FORMS & PROTOCOLS (ASM)
  - ASM-00 End-to-end workflow
  - ASM-01 Intake form — field schema (YourCounselor AI design)
  - ASM-02 Building rapport
  - ASM-03 Clinical interview
  - ASM-04 Case history format
  - ASM-05 Mental State Examination (MSE) — structured schema
  - ASM-06 Risk screening & safety protocol ⚠ (mandatory)
  - ASM-07 Assessment summary & report template
  - ASM-08 Treatment plan
  - ASM-09 Session notes
  - ASM-10 Observations during testing
- PART 5 — INSTRUMENT LIBRARY (INS)
  - INS-00 Rules for choosing instruments
  - INS-01 Theories of intelligence (for interpretation and training)
  - INS-02 Individual intelligence tests
  - INS-03 Group and culture-reduced intelligence tests
  - INS-04 Infant and preschool assessment
  - INS-05 Intellectual disability — classification (current terminology)
  - INS-06 Aptitude and achievement
  - INS-07 Objective personality inventories
  - INS-08 Projective techniques
  - INS-09 Neuropsychological tests
  - INS-10 Adaptive behaviour
  - INS-11 Instruments for special populations (see POP)
  - INS-12 Interests, values and careers
  - INS-13 Attitudes, moral reasoning, spirituality
  - INS-14 FULL-TEXT SCALES READY FOR DIGITISATION
  - INS-HAMA: Hamilton Anxiety Rating Scale (HAM-A)
  - INS-DASS21: Depression Anxiety Stress Scales – 21
  - INS-PHQ9: Patient Health Questionnaire-9
  - INS-GAD7: Generalized Anxiety Disorder-7
  - INS-RSES: Rosenberg Self-Esteem Scale
  - INS-EIR: YourCounselor Emotional Intelligence Reflection (YC-EIR) — original in-house tool
- PART 6 — INTERVENTION LIBRARY (INT)
  - INT-01 Core counselling micro-skills (all levels)
  - INT-02 Talk therapy (supportive / psychodynamically informed)
  - INT-03 Behaviour therapy / behaviour modification
  - INT-04 Cognitive Behavioural Therapy (CBT)
  - INT-05 Gestalt empty-chair technique
  - INT-06 Narrative therapy
  - INT-07 Guided imagery & relaxation — "Resource & Release" protocols (IH)
  - INT-08 Dream work (exploratory)
  - INT-09 Music-based interventions
  - INT-10 Projective elicitation techniques (exploration, not diagnosis)
  - INT-11 Homework & journaling library
  - INT-12 Roadmap — modalities to add in v2
- PART 7 — COUNSELLING, CAREER & WORKPLACE (CNS)
  - CNS-01 Counselling vs clinical psychology
  - CNS-02 Career counselling workflow
  - CNS-03 Testing in the workplace
- PART 8 — SPECIAL POPULATIONS, FAIRNESS & BIAS (POP)
  - POP-01 Assessing people with disabilities
  - POP-02 Test bias vs test fairness
- PART 9 — GAPS & NEXT BUILD (roadmap)
- APPENDIX A — DATA MODEL FOR SOFTWARE (DATA)
  - DATA-01 Core entities
  - DATA-02 Example instrument definition (DASS-21)
  - DATA-03 Product rules
- APPENDIX B — GLOSSARY (selected)
- APPENDIX C — REFERENCES, LICENSING REGISTER & VERSION LOG
  - C.1 Key references (primary literature)
  - C.2 Licensing register (instruments with items in this file)
  - C.3 Version log

---

## PART 0 — HOW THIS KNOWLEDGE BASE IS ORGANISED (read first)

### 0.1 Design principles
1. **One card per idea.** Each technique, instrument, form or formula lives on its own card with a permanent ID, so it maps directly to one database record, screen or API object.
2. **Fixed templates.** Every card of a given type has the same fields, always in the same order.
3. **Evidence on the surface.** Each technique and instrument shows its evidence grade.
4. **Safety on the surface.** Risk flags and contraindications are required fields, not notes hidden in paragraphs.
5. **Licensing on the surface.** The app digitises an instrument only when its licence permits.

### 0.2 ID scheme
Format: `[PART]-[SECTION]-[NN]`. Examples: `ASM-MSE-01` (Assessment › Mental State Exam), `INT-CBT-04` (Intervention › CBT), `INS-DASS21` (Instrument).

| Prefix | Domain |
|---|---|
| FND | Foundations of testing |
| PSY | Psychometric toolkit & formulas |
| ETH | Ethics, law, standards |
| ASM | Clinical assessment workflow & forms |
| INS | Instrument library |
| INT | Interventions / techniques |
| CNS | Counselling, career, workplace |
| POP | Special populations & fairness |
| DATA | Software data model |

### 0.3 Evidence grades
| Grade | Meaning |
|---|---|
| **A** | Strong — backed by several controlled trials or meta-analyses; an accepted standard of care |
| **B** | Moderate — some controlled studies or solid psychometric support |
| **C** | Limited — case series, expert consensus, or thin/mixed findings |
| **D** | Contested or insufficient — exploratory use only; never the basis for a decision |
| **IH** | YourCounselor AI in-house protocol — not independently validated |

### 0.4 Licence codes (for software)
| Code | Meaning | App rule |
|---|---|---|
| **PD** | Public domain | Can be digitised and auto-scored; always show the citation |
| **FREE** | Free with attribution and/or non-commercial conditions | Read the owner's terms; normally fine with citation |
| **PUB** | Commercial product sold by a publisher | Never reproduce items; record scores only, or obtain a licence |
| **RQ** | Sale restricted to qualified professionals | Never digitise; administered only by a qualified examiner |
| **IH** | Written and owned by YourCounselor AI | Free for internal and product use |

### 0.5 User competence levels
| Level | Who | Permitted scope |
|---|---|---|
| **L1** | Counsellor or trainee working under supervision | Rapport, intake, screening scales, psycho-education, basic techniques |
| **L2** | Qualified clinical or counselling psychologist (RCI-registered where the law requires) | All assessments and interventions within their training |
| **L3** | Specialist (neuropsychology, forensic, child) | Specialist test batteries |

### 0.6 Standard card templates
**Technique card:** ID · Name · Approach/school · Purpose & indications · Contraindications ⚠ · Evidence · Level · Usual duration & number of sessions · Preparation · Steps (numbered) · Scripts/prompts · Homework · Outcome measures · Common pitfalls.

**Instrument card:** ID · Name & current edition · Construct · Age range · Format & item count · Administration (time, mode, level) · Scoring · Norms · Reliability · Validity · Interpretation bands · Cautions ⚠ · Licence · Evidence.

---

## PART 1 — FOUNDATIONS OF PSYCHOLOGICAL TESTING (FND)

### FND-01 Core definitions
- **Test:** a standard procedure for obtaining a sample of behaviour so that it can be described, quantified or used for prediction.
- **Psychological test:** a structured set of tasks or questions that measures personal characteristics linked to behaviour, such as abilities, mood or personality.
- **Testing:** giving a test, scoring it and interpreting the result.
- **Assessment:** a wider problem-solving activity aimed at answering a referral question. It pulls together test data, interview, history, medical information, observation and reports from others. **No test score is ever interpreted in isolation.**

### FND-02 What makes something a test
1. **A behaviour sample.** No test covers everything, so its value rests on how well the sample represents the wider behaviour.
2. **Uniform conditions.** Everyone gets the same instructions, materials, timing and setting. The examiner is part of those conditions, which is why individually administered tests need trained examiners.
3. **Defined scoring rules.** Scoring can be *objective*, where any trained scorer arrives at the same result (e.g., multiple choice), or *subjective*, where judgement is involved (e.g., essays, projective responses).

### FND-03 What tests are used for
| Purpose | Question it answers | Example |
|---|---|---|
| Rating | Where does this person stand relative to others or a standard? | Grades, appraisal ratings |
| Placement | Which programme or service suits this person? | Remedial group, choice of therapy |
| Selection | Which applicants should be accepted? | Admissions, recruitment |
| Competency | Has the person reached a required standard? | Licensing and qualifying exams |
| Diagnosis | What is the nature of the difficulty? | Clinical or learning-difficulty assessment |
| Outcome evaluation | Did the programme or therapy help? | Before/after measures |

### FND-04 Ways of classifying tests
| Basis | Categories |
|---|---|
| Administration | Individual · Group |
| Content | Intelligence · Aptitude · Achievement · Creativity · Personality · Interests/values · Behaviour · Neuropsychological · Adaptive behaviour |
| Kind of performance | **Maximal** (best possible — ability tests) · **Typical** (habitual — personality, interests) |
| Response format | Selected response (true/false, multiple choice, Likert) · Constructed response · Projective |
| Timing | **Speed** (easy items, tight limit) · **Power** (difficult items, generous limit) |
| Frame of reference | **Norm-referenced** (compared with a group) · **Criterion-referenced** (compared with a standard or content domain) |
| Score type | Normative · **Ipsative** (forced choice; scores only show relative strength within one person, so they cannot be compared across people) |

**Individual vs group administration**
| | Individual | Group |
|---|---|---|
| Advantages | Detailed observation, rapport, flexible follow-up questions; suits young, anxious or disabled examinees | Quick, economical, machine-scorable, large norm samples, little examiner training |
| Disadvantages | Slow, costly, depends on examiner skill | Weak rapport; confusion, illness or low effort go unnoticed; rigid |
| Best suited to | Diagnosis and intervention planning | Screening and institutional decisions |

### FND-05 Testing vs assessment in day-to-day practice
Assessment brings together interview, background details, history, medical data, observation, collateral information and tests. **Working rule:** treat a test result as a signal that either supports or questions the clinical impression — never as the decision itself.

### FND-06 Historical timeline (training modules)
| Year | Milestone |
|---|---|
| c. 2200 BCE | Imperial China uses written examinations to select officials |
| 1859–1869 | Darwin's work on variation; Galton studies inherited ability, sensory measures and correlation |
| 1890 | James McKeen Cattell introduces the term "mental test" |
| 1905 | Binet and Simon publish the first practical intelligence scale (revised 1908, 1911) |
| 1916 | Terman's Stanford revision popularises the IQ |
| 1917–18 | US Army Alpha (verbal) and Beta (non-verbal) group tests; Woodworth's Personal Data Sheet, the first personality questionnaire |
| 1921 | Rorschach publishes his inkblot method |
| 1927 | Strong's vocational interest inventory appears |
| 1935 | Morgan and Murray introduce the Thematic Apperception Test |
| 1939 | Wechsler–Bellevue scale introduces the deviation IQ |
| 1943 | MMPI published |
| Mid-1960s on | Growing public and legal scrutiny of privacy, bias and fairness |
| 1980s–today | Item response theory and computer-adaptive testing |

**Teaching case on misuse:** Early-1900s intelligence testing of newly arrived immigrants at Ellis Island (associated with H. H. Goddard) gave tired, frightened people poorly translated tests and judged them against unsuitable norms. It is the standard illustration of why language, testing conditions and appropriate norms matter.

### FND-07 Qualities of a good test
- **Design:** a stated purpose (what it measures, for whom, and how scores will be used); clearly specified content; standard administration; standard scoring.
- **Psychometrics:** adequate reliability and validity, sound item statistics, and suitable, up-to-date norms.

---

## PART 2 — PSYCHOMETRIC TOOLKIT (PSY)
*The formulas and decision rules the software must implement.*

### PSY-01 Classical Test Theory
- **X = T + e** — an observed score is a true score plus random error.
- Assumptions: errors average zero; errors are unrelated to true scores; errors on two different tests are unrelated.
- **σ²X = σ²T + σ²e**.
- **Reliability r_xx = σ²T / σ²X** — the share of observed-score variance that is true-score variance.
- "True score" is the stable part of a score under the measurement conditions, not the person's "real" level of the trait. What counts as error depends on why you are measuring.

### PSY-02 Where score differences come from
| Source | Examples |
|---|---|
| Stable and broad | General ability; familiarity with taking tests |
| Stable and test-specific | Skills particular to this item type; habitual answering styles |
| Passing and broad | Health, tiredness, motivation, anxiety, room conditions |
| Passing and test-specific | Momentary lapses of attention; having just met similar content |
| Administration | Timing mistakes, interruptions, examiner–examinee dynamics, scorer bias |
| Chance | Lucky guesses, careless slips |

(Framework after R. L. Thorndike's classic analysis of error sources.)

### PSY-03 Ways to estimate reliability
| Method | How it is done | Error captured | Watch-outs |
|---|---|---|---|
| Test–retest | Give the same test twice and correlate | Changes over time | Real change, memory and practice effects, reactivity; strictly a *stability* coefficient |
| Alternate forms | Give Form A and Form B and correlate | Content sampling and time | Forms must be genuinely equivalent; expensive to build |
| Split-half | Correlate two halves (e.g., odd vs even items), then correct with Spearman–Brown | Content sampling | Different splits give different answers |
| Internal consistency | Cronbach's α or KR-20 | Item heterogeneity | α is the average of all possible split-halves; long tests inflate it |
| Inter-rater | Correlation or agreement between scorers | Scorer differences | Essential for projective, observational and essay scoring |

### PSY-04 Formulas
```
Standardised alpha:        α = k·r̄ / [1 + (k−1)·r̄]           k = number of items, r̄ = mean inter-item r
Spearman–Brown:            r_new = n·r_old / [1 + (n−1)·r_old]    n = factor by which length changes
Standard error of meas.:   SEM = SD·√(1 − r_xx)
Confidence band:           X ± z·SEM    (68%: ±1 SEM; 95%: ±1.96 SEM)
SE of a difference:        SE_diff = SD·√(2 − r₁ − r₂)            (two scores on the same scale)
```
**Worked example:** a 20-item test with r = .60 rises to about .75 if doubled in length, and to about .90 at six times its length.

### PSY-05 What influences reliability
- **Spread of the group:** a wider range of scores gives a higher coefficient; the same test looks less reliable in a narrow group such as gifted students.
- **Length and item similarity:** more items, and items that hang together, raise reliability.
- **Purpose:** fine-grained or long-term decisions demand higher reliability.
- **Method:** internal consistency usually comes out highest, alternate forms next, test–retest lowest.
- **Speed:** for speeded tests, split-half and α are artificially high — use test–retest or alternate forms.

**Working minimums (conventions):**
| Minimum r | Suitable for |
|---|---|
| ≥ .90 | High-stakes decisions about an individual |
| ≥ .80 | Screening |
| ≥ .70 | Group-level research only |

### PSY-06 Validity
Current view (Messick; the *Standards for Educational and Psychological Testing*): validity concerns how well evidence and theory support a particular interpretation of scores. It is a single concept supported by different kinds of evidence.

| Kind of evidence | Question | How it is collected |
|---|---|---|
| **Content** | Do the items cover the domain properly? | Define the domain; build a blueprint; expert review (Lawshe's content validity ratio quantifies agreement) |
| **Construct** | Does the test reflect the intended attribute? | Specify the theory and expected relationships; convergent and discriminant correlations; factor analysis; experiments; known-group differences; change with development |
| **Criterion — predictive** | Does it forecast a future outcome? | Test now, measure the outcome later (the ideal, though often impractical) |
| **Criterion — concurrent** | Does it relate to a present outcome? | Test and criterion at the same time, often in an already-selected group |
| **Face** | Does it seem relevant to the person taking it? | Not evidence of validity, but it affects cooperation |

Key relationships:
- Validity is capped by reliability. A reliable test can still be invalid; an unreliable test cannot be valid.
- **Restriction of range** (e.g., studying only people already hired or admitted) shrinks observed validity coefficients.
- Criterion validities of .30–.50 are typical in applied work; judge them by their practical decision value, not by r² alone.
- **Cross-validate:** items or weights chosen in one sample must be re-checked in a fresh sample, because some of the original fit is chance.

### PSY-07 Decision accuracy (required for every screening tool)
|  | Criterion positive (has condition / succeeds) | Criterion negative |
|---|---|---|
| **Test positive** | True positive (TP) | False positive (FP) |
| **Test negative** | False negative (FN) | True negative (TN) |

```
Sensitivity = TP/(TP+FN)      Specificity = TN/(TN+FP)
PPV = TP/(TP+FP)              NPV = TN/(TN+FN)
Base rate (BR) = proportion of the population who are truly positive
Selection ratio (SR) = places available / applicants
```
- With a **low base rate** (rare conditions, suicide), even an accurate test produces many false positives.
- A test adds most value when BR is near .50 and SR is low (Taylor & Russell, 1939).
- **Utility (Brogden–Cronbach–Gleser):** Gain = N_selected × r_xy × SD_y × Z̄_selected, minus the cost of testing.

### PSY-08 Item analysis
| Index | Formula | How to read it |
|---|---|---|
| Difficulty p | number correct / N | Ranges 0–1; higher = easier. About .50 spreads scores best; for screening, set p near the cut-point |
| Discrimination D | (U − L)/n, using the top and bottom 27% | ≥ .40 very good; .30–.39 good; .20–.29 borderline; < .20 or negative — revise or drop (Ebel's guidelines) |
| Item–total r | Point-biserial correlation of item with total | Should be clearly positive; a negative value means the item measures something else |
| Distractor analysis | Expected share = wrong answers ÷ number of distractors | Rewrite distractors nobody picks, or that attract high scorers |

- The largest possible D depends on p: 1.0 when p = .50, zero when p = 0 or 1.
- On **speeded tests**, statistics for late items are distorted; analyse data collected with generous time.
- **IRT:** models the chance of a correct answer as a function of the person's trait level (θ), using item parameters for difficulty (b), discrimination (a) and guessing (c). Parameters do not depend on the particular sample. IRT underpins **computer-adaptive testing (CAT)**, which reaches equal or better precision with roughly half the items.

### PSY-09 Writing items for in-house questionnaires
Formats: dichotomous (true/false), multiple choice, Likert (5- or 7-point agreement), category ratings with clearly labelled anchors, checklists, and Q-sort (cards sorted into nine piles following a near-normal distribution).

**Item-writing rules:**
- Match reading level to the population.
- One idea per item.
- No double negatives.
- Avoid absolute words such as "always" and "never".
- Avoid fuzzy frequency words such as "often".
- Items must not give away or depend on one another.
- Vary the position of the correct answer.
- One clearly best answer plus 3–4 believable distractors.
- Avoid clues from option length or grammar.
- No trivia or trick questions.
- In matching tasks, keep each set on one theme and give more options than stems.

**Correction for guessing:** `Corrected = R − W/(n−1)` (R = right, W = wrong, n = options; omitted items are not counted).

**Test blueprint:** a grid of content areas against thinking skills with percentage weights; allocate items in line with the weights.

### PSY-10 Norms and derived scores
A raw score is meaningless until it is compared with something. Three questions set the frame: are we describing now or predicting later; measuring best or typical performance; and comparing against a content standard, the person's own other scores, or other people?

| Score | Formula / definition | Notes |
|---|---|---|
| Percentile rank (PR) | (cumulative frequency below + ½ × frequency at the score) / N × 100 | Easy to explain, but unequal units (bunched in the middle, spread at the extremes). Never add or average PRs |
| z | (X − M)/SD | Mean 0, SD 1 |
| Linear T / converted | C = 10z + 50 (or any chosen mean/SD) | Keeps the original distribution shape |
| Normalised T | Convert PR to z using the normal table, then 10z + 50 | Forces a normal shape; appropriate only if the trait is assumed normal |
| Deviation IQ / index | 100 + 15z | Wechsler, SB5, KABC |
| Scaled (subtest) | 10 + 3z | Wechsler subtests |
| Stanine | Mean 5, SD ≈ 2, nine bands | Discourages reading too much into small gaps |
| NCE | 50 + 21.06z | Equal-interval; matches PR at 1, 50 and 99 |
| Grade/age equivalent | Median score of children at a given grade or age | ⚠ Unequal units and extrapolated at the extremes. A third-grader's GE of 5.9 does not mean they have mastered grade-5 content. Never use for mastery decisions |
| Developmental standard score | Equal-interval scale tied to grade levels | Precise but hard to explain to families |

**Conversion anchors (normal distribution):**
| z | PR | T | IQ | Stanine |
|---|---|---|---|---|
| −2.0 | 2 | 30 | 70 | 1 |
| −1.0 | 16 | 40 | 85 | 3 |
| 0 | 50 | 50 | 100 | 5 |
| +1.0 | 84 | 60 | 115 | 7 |
| +2.0 | 98 | 70 | 130 | 9 |

**Norm rules:**
- The norm group must resemble the person tested (age, grade, language, culture, occupation).
- Use recent norms — the Flynn effect pushes average scores up over decades.
- Develop **local norms** where published ones do not fit, as is often the case for Indian populations.
- Norms based on group averages are narrower than norms for individuals; never mix the two.
- Norms describe how people *do* score, not how they *ought* to; by definition half of any norm group is below its average.

**Score profiles:** plot only scores normed on the same sample, and interpret only differences larger than SE_diff.

### PSY-11 Response bias
| Type | What it is | Examples | How to detect or control it |
|---|---|---|---|
| Response **set** (depends on item content) | Answering to create a particular impression | Social desirability, faking good, faking bad / malingering | Validity scales (e.g., MMPI L, K, F); forced-choice pairs matched for desirability; collateral information |
| Response **style** (independent of content) | A habitual way of answering regardless of content | Agreeing with everything, disagreeing with everything, extreme or middle responding, random answering | Balanced keying (about half the items reversed); consistency checks on repeated or paired items (VRIN/TRIN type); infrequency scales |

---

## PART 3 — ETHICS, LAW & PROFESSIONAL STANDARDS (ETH)

### ETH-01 Ethical principles for testing and assessment
1. **Informed consent:** Before any testing, tell the client why it is being done, who will see the results, how they will be used, and where confidentiality ends. For anyone under 18, obtain a parent's or guardian's consent and the young person's own agreement (assent). Record both.
2. **Competence:** Use only instruments you are trained in and qualified for under the publisher's user requirements. A supervisor carries responsibility for reports written by the people they supervise.
3. **Choosing tests:** Pick instruments with evidence for this purpose and this population. Use the current edition and norms unless there is a recorded reason not to.
4. **Standard administration:** Follow the manual. Any change — for example, to accommodate a disability — must be justified, and the report must say how it may affect the meaning of scores.
5. **Interpretation:**
   - No decision rests on a single score.
   - Screening results only indicate that fuller assessment is needed.
   - Do not rely on computer-generated interpretive reports unless you understand how they are produced.
   - Report derived scores with their margin of error (e.g., confidence intervals).
6. **Confidentiality:** Share results only with written consent or when the law requires it. Remove identifying details from research data.
7. **Duty to warn / protect:** The US *Tarasoff* ruling (California Supreme Court, 1976) established that a therapist may need to act to protect an identifiable person whom a client seriously threatens. Learn the law where you practise and record your reasoning.
8. **Feedback:** Explain results promptly and in plain language, and take reasonable steps to prevent misuse.
9. **Privacy:** Clients decide how much of their inner life to reveal. Ask only what the purpose requires.
10. **Test security:** Keep test items, record forms and manuals secure; respect copyright; store and destroy records safely.
11. **Boundaries:** Avoid dual relationships. Use humour only when it is safe for the client. Handle gifts and physical contact within professional norms.

### ETH-02 Indian legal context (confirm with a legal adviser before release)
- **Mental Healthcare Act, 2017:** Sets out rights of persons with mental illness — dignity, confidentiality, access to care, advance directives and nominated representatives. It presumes that a person who attempts suicide is under severe stress and directs that they receive care, not punishment.
- **Rights of Persons with Disabilities Act, 2016:** Establishes disability rights and reasonable accommodation. Its list of specified disabilities includes intellectual disability, specific learning disabilities, autism spectrum disorder and mental illness.
- **Rehabilitation Council of India (RCI):** Clinical psychologists and certain rehabilitation professionals must be registered.
- **Digital Personal Data Protection Act, 2023:** Directly applies to the app. Mental-health data requires clear consent, use limited to the stated purpose, security safeguards, and user rights to access and erase data. Consent screens and retention rules must be designed around it.
- **International reference:** Principles from US disability law (ADA/IDEA) are reflected in POP-01.

### ETH-03 Ethics specific to the app
- **Copyright:** Never digitise a PUB or RQ instrument without a written licence. For those instruments, store only the scores a clinician enters.
- **Equivalence:** A computer version is not automatically equivalent to paper. Equivalence must be shown; for instance, a computerised version of the GATB led examinees to answer faster but less accurately.
- **Limits of automation:** Automatic scoring is allowed. Automatic *diagnosis* is not — a clinician always makes the call.
- **Risk items:** Any positive response on a risk item (e.g., PHQ-9 item 9, the intake self-harm question) must alert a clinician and display crisis contacts on screen.
- **Audit trail:** Record who administered the measure, which version, the date, any accommodations, and every score change.

---

## PART 4 — CLINICAL WORKFLOW, FORMS & PROTOCOLS (ASM)

### ASM-00 End-to-end workflow
```
Referral → Consent (ETH-01) → Intake form (ASM-01) → Rapport (ASM-02) → Clinical interview (ASM-03)
→ Case history (ASM-04) → Mental State Exam (ASM-05) → Risk screen (ASM-06) → Test selection & testing (PART 5)
→ Integration & formulation (ASM-07) → Diagnosis & feedback → Treatment plan (ASM-08)
→ Sessions + notes (ASM-09) → Progress monitoring (repeat measures) → Ending & follow-up
```

### ASM-01 Intake form — field schema (YourCounselor AI design)
| Section | Fields (type) |
|---|---|
| About you | Full name; Record ID (auto); Assigned clinician; Intake date; Date of birth; Age (auto-calculated); Gender (Woman / Man / Non-binary / Prefer to self-describe / Prefer not to say); Address, city, state, PIN; Phone numbers; Email; Preferred language; Emergency contact (name, relationship, phone) |
| Relationships | Current status (Single / In a relationship / Married / Living together / Separated / Divorced / Widowed / Other); How long in current relationship; How the relationship is going (Poor / Fair / Good); Number of previous marriages |
| Background & identity | Free text, plus optional fields for region, community, faith and languages spoken |
| How you came to us | Self / Doctor / School or college / Court / Employer / Other; What the referrer wants to know |
| Main concern | Free text; When it began; How long it has lasted; What sets it off; Impact rating 0–10 (0 = no effect on daily life, 10 = affecting almost every part of life) |
| Areas of concern (tick any) | Emotional: low mood; hopelessness or worthlessness; worry or nervousness; fears; mood swings; unusually high or excited mood; anger outbursts; grief or loss; low self-worth · Thinking & perception: intrusive or repetitive thoughts; repetitive actions; hearing or seeing things others don't; unusual beliefs; trouble concentrating · Behaviour & habits: restlessness or hyperactivity; alcohol or drug use; eating difficulties; troubling urges or habits · Body & sleep: tiredness or low energy; trouble getting to sleep; waking in the night; nightmares; ongoing pain; seizures; coordination difficulties; hearing or eyesight problems; problems with medication · Life & relationships: relationship difficulties; parenting concerns; loneliness or withdrawal; study or work performance; learning difficulties · Past experiences: distressing or traumatic events; having been abused or neglected ⚠ · Safety ⚠: thoughts of ending your life or past attempts; hurting yourself; thoughts of harming someone else · Other (free text) |
| Who lives with you | Repeating rows: Name · Relationship · Age · Work or school |
| Family now | Current family difficulties (emotional, behavioural, legal, substance-related); Family strengths and support |
| Growing up | What home life was like; Childhood or teenage experiences that still affect you; Developmental, learning or emotional difficulties when young |
| Education & work | Highest qualification; Subject; Work status; Current or most recent role; Work history; Armed forces / uniformed service (Y/N, details) |
| Current pressures | Housing; Money; Little support from others; Other |
| Strengths | What you are good at; What others appreciate in you |
| Free time | Hobbies and interests; Any recent change (None / Doing more / Doing less / Stopped) |
| Legal | Current or past legal matters |
| Mental-health history | Past outpatient care (rows: dates, provider, diagnosis given, age at the time, type of help); Past inpatient care (same fields); Mental-health difficulties in the family |
| Physical health | Doctor's name; Last check-up; Allergies; Current medicines and supplements; Current health conditions; Pain 0–10 and where; Personal/family history tick-list (heart disease, high blood pressure, stroke, diabetes, thyroid disorder, asthma, cancer, tuberculosis, liver disease, stomach/bowel disease, autoimmune disease, multiple sclerosis, Parkinson's disease, Huntington's disease, dementia, fibromyalgia, obesity, birth differences, intellectual disability, emotional or behavioural difficulties, other) |
| Alcohol & drugs | Others worried about your use (Y/N); You worried (Y/N); Needing more for the same effect; Problems at work; Problems in relationships; Times intoxicated per month; Cravings or withdrawal; Family history |
| Beliefs & meaning | Outlook (Religious / Spiritual / Not religious / Unsure / Other); Would you like this to be part of your sessions? |
| **Safety** ⚠ | Any current or past thoughts, plans or attempts to hurt yourself or someone else (free text) → **any positive answer launches ASM-06** |
| Consent | Assessment and treatment; Audio/video recording; Data-sharing choices; Signature and date |

### ASM-02 Building rapport
**What it is:** the sense of trust and mutual understanding between client and clinician. It underpins the working alliance (Bordin; Horvath & Greenberg). It starts with the very first phone call or visit and needs attention in every session. **Its most powerful ingredient is empathy the client can actually see and feel.**

**The room:**
- Comfortable seating and temperature.
- Private and sound-proofed — no glass partitions or interruptions.
- Tidy and uncluttered.
- A glass of water or tea offered.
- Phones on silent.

**What the clinician does:**
1. Greets the client by name and introduces themselves and their role.
2. Speaks calmly and warmly with relaxed, open posture.
3. Explains how sessions work, what is confidential and where confidentiality ends — this gives the client structure and a sense of safety.
4. Recognises and acknowledges the client's feelings.
5. Listens fully without interrupting, and lets the client see they have been heard.
6. Restates and reflects what the client says so they feel understood.
7. Allows silence so the client has room to think.
8. Asks mainly open questions, using closed ones for facts.
9. Uses humour only if it arises naturally and never at the client's expense.
10. Works *with* the client rather than directing them.

**Opening conversation:** Do not choose small-talk topics based on assumptions about gender or marital status. Begin with whatever the client raises, or ask something neutral such as "How do you usually spend your days?" or "What do you like doing when you have time to yourself?" and follow where they go. With children, use topics that suit their age — school, friends, games, food, sport, a favourite teacher.

**Direct vs indirect questions:** Ask directly when you need a clear fact ("Are there any difficulties in your marriage right now?"). Approach sensitive areas indirectly — for instance, by talking about family members, home life or work — when the client seems guarded.

### ASM-03 Clinical interview
**Interview vs everyday conversation:** A clinical interview has a purpose, a plan, defined roles and a record, and goes deep into a limited set of issues. Everyday conversation is informal, unrecorded and wide-ranging but shallow.

**Clinician attitude:**
- *Helpful:* warmth, honesty, acceptance, openness, fairness, genuineness, humility, collaboration.
- *Harmful:* defensiveness, detachment, boredom, aloofness, self-importance — these make clients hold back or drop out.

**Setting:**
- Physically and emotionally comfortable.
- Private.
- No questions that shame, pry unnecessarily, dominate, argue or criticise.

**Good responding:** be clear, encourage, acknowledge, show empathy, ask open questions, and keep the client's account flowing.

**Levels of empathic responding** (after Carkhuff's scale of accurate empathy)
| Level | What the response does | Guidance |
|---|---|---|
| 1 | Ignores or misses what the client said | Avoid |
| 2 | Picks up only the surface, losing some of the meaning | Avoid |
| 3 | Captures the client's feeling and meaning accurately, adding and losing nothing | Minimum acceptable |
| 4 | Goes a step further by naming feelings the client implied but didn't say | Skilled |
| 5 | Adds real depth and opens new understanding | Advanced |

**Interview formats**
| Format | Strengths | Weaknesses | Best for |
|---|---|---|---|
| Structured | Reliable, comparable, efficient, less bias, easy to analyse | Rigid, may stay shallow, answers can be faked | Diagnosis (e.g., SCID-style), research, selection |
| Semi-structured | A fixed core with room for follow-up; non-verbal cues noticed | Takes longer and needs more skill; some bias | Most clinical intakes |
| Unstructured | Flexible; good for sensitive areas; helps clients open up | Less reliable, prone to bias, time-consuming | Exploratory therapy work |

**Kinds of interview:**
- **Intake:** main complaint, present functioning, goals, background, first plan.
- **Life history:** an ordered, chronological account of the person's life.
- **Diagnostic:** focused on symptoms, with flexible follow-up questions.
- **Stress interview:** ⚠ intentionally confrontational. Only with a clear justification, only by experienced clinicians, and never with vulnerable clients.

**Recording:** Notes, audio or video — **any recording requires written consent**.

### ASM-04 Case history format
1. **Identifying details:** name, age, sex, education, occupation, marital status, religion, language, socio-economic background, address; who provided information and how reliable they seem.
2. **Who referred the client and why.**
3. **Presenting complaints:** as described by the client and by informants; onset, duration, course, triggers, severity (1–10).
4. **History of the current problem:** how it developed over time; any treatment so far and its effect.
5. **Past psychiatric and medical history.**
6. **Family history:** genogram; members' ages, occupations and relationships; physical and mental illness in the family; emotional climate at home.
7. **Personal history:**
   - Birth and early development (milestones)
   - School years (performance, friendships, teachers)
   - Work history
   - Menstrual, sexual and marital history
   - Alcohol and drug use
   - Contact with the legal system
8. **Personality before the illness:** relationships, interests, usual mood, character, attitudes, habits, inner life and ambitions.
9. **Interests and values:** religious, political, spiritual, professional, leisure.
10. **Mental State Examination (ASM-05).**
11. **Summary and working formulation (ASM-07).**

### ASM-05 Mental State Examination (MSE) — structured schema
| Domain | Options (multi-select) + comment box |
|---|---|
| Appearance | Well groomed / Unkempt / Dressed unsuitably for the setting / Odd or bizarre / Other |
| Behaviour & attitude | Cooperative / Guarded / Hostile / Agitated / Overactive / Withdrawn / Stereotyped movements / Aggressive / Bizarre |
| Eye contact | Normal / Intense / Avoidant / Fleeting |
| Psychomotor | Normal / Restless / Slowed / Tics / Tremor / Catatonic features |
| Speech | Rate, volume, tone, clarity, amount — Normal / Pressured / Slow / Sparse / Tangential |
| Mood (as reported) | Euthymic / Anxious / Low / Irritable / Angry / Elated — record the client's own words |
| Affect (as observed) | Full / Restricted / Blunted / Flat / Labile; Congruent / Incongruent with mood |
| Thought form | Logical / Circumstantial / Tangential / Loosening of associations / Flight of ideas / Perseveration / Thought block / Incoherent |
| Thought content | Preoccupations / Obsessions / Phobias / Ideas of reference / Delusions (persecutory, grandiose, religious, somatic, other) / Thought broadcast, insertion or withdrawal |
| Risk ⚠ | Suicide: None / Ideation / Plan / Intent / Self-harm. Harm to others: None / Ideation / Intent / Plan → ASM-06 |
| Perception | None / Hallucinations (auditory, visual, tactile, olfactory) / Illusions / Depersonalisation / Derealisation |
| Cognition | Orientation (time, place, person); Attention (serial 7s, digit span); Memory (immediate, recent, remote); Abstract thinking; General knowledge / estimated intellectual level |
| Insight | Good / Partial / Poor (or a 1–6 grading if preferred) |
| Judgement | Good / Fair / Poor (hypothetical test and real-life social judgement) |

**Thought-form tooltips (for the app):**
- *Circumstantial:* gets to the point eventually, but only after many unnecessary details.
- *Tangential:* drifts off and never reaches the point.
- *Loosening of associations:* one idea does not logically follow from the last.
- *Flight of ideas:* fast jumps between topics, often linked by sound or word-play; typical of mania.
- *Perseveration:* keeps returning to the same word or idea.
- *Thought block:* the train of thought stops abruptly.

### ASM-06 Risk screening & safety protocol ⚠ (mandatory)
**Triggered by:** a positive risk response on the intake form, MSE, PHQ-9 item 9, or any disclosure during a session.

**Screen:**
- Ask plainly and calmly about thoughts of death or suicide — how often, any plan, access to means, intent, previous attempts, reasons for living and supports.
- Also ask about risk to others and about abuse, including abuse of a child.

**Risk levels and actions**
| Level | Signs | Action |
|---|---|---|
| Low | Passive thoughts; no plan or intent; strong protective factors | Safety plan; review risk every session; give crisis numbers |
| Moderate | Active thoughts; vague plan; no intent; some risk factors | Joint safety plan; reduce access to means; involve a support person (with consent); see the client more often; consult a supervisor |
| High | Plan, intent and access; recent attempt; psychosis; severe agitation | Do not leave the person alone; arrange urgent psychiatric or emergency assessment; involve family or nominated representative; document everything |

**Safety plan sections** (based on the Stanley–Brown Safety Planning Intervention):
1. Warning signs that a crisis may be building
2. Things the person can do alone to cope
3. People and places that offer distraction
4. People they can ask for help
5. Professionals and crisis lines
6. Making the surroundings safer (limiting access to means)
7. Reasons for living

**Indian crisis contacts** (maintained in `crisis-resources.md` — owner: Clinical Safety Officer; next review 2027-09-24):
- **Tele-MANAS 14416 / 1-800-891-4416** — national, 24×7
- **112** — emergency services
- **1098** — Child Helpline, for children
- **181** — Women Helpline
- *KIRAN has been merged into Tele-MANAS — do not list it separately.*

**Duty to protect:** see ETH-01 (7). **Child abuse:** reporting is mandatory in India under the POCSO Act, 2012.

### ASM-07 Assessment summary & report template
1. Identifying details and referral question
2. Tests given — table: Test | Raw score | Standard score | 95% CI | Descriptor
3. Behaviour during testing (see ASM-10)
4. Findings by area: cognitive, emotional, personality, adaptive
5. **Integrated summary:** what is happening, why and how — cross-checking tests against history and observation
6. **Formulation (5 Ps):** Presenting problem · Predisposing · Precipitating · Perpetuating · Protective factors
7. **Diagnosis:** ICD-11 (or DSM-5-TR where required), made by a qualified clinician, with differentials
8. **Prognosis:** likely course and what influences it
9. **Recommendations:** type of therapy, referrals, accommodations, date for re-assessment
10. **Limitations:** how far these results can be trusted; accommodations used

### ASM-08 Treatment plan
| Element | Content |
|---|---|
| Problem list | Ranked in priority, drawn from the formulation |
| Goals | **SMART** — Specific, Measurable, Achievable, Relevant, Time-bound |
| Approach | Chosen by research evidence for the problem, the client's preferences and the clinician's skills (see PART 6) |
| Sequencing | When each technique comes in (e.g., relaxation skills before exposure) |
| Dose | Number and frequency of sessions (e.g., weekly for 8–12 sessions of CBT, then spaced out) |
| Measures | Baseline, mid-point and end (e.g., DASS-21, PHQ-9) |
| Review | Planned review points; criteria for ending or referring on |
| Relapse prevention | Early warning signs, a maintenance plan, booster sessions |

### ASM-09 Session notes
- **SOAP:** Subjective (what the client reports) · Objective (what is observed, scores) · Assessment (clinical impression, progress) · Plan (next steps, homework).
- **DAP:** Data · Assessment · Plan.

Every note records: date, length, format (in person / online), risk review, homework set and reviewed, next appointment.

### ASM-10 Observations during testing
Note: attitude to being tested; cooperation; effort; anxiety; response to failure or frustration; attention; impulsive vs careful style; persistence; language and speech; motor behaviour; how much encouragement was needed; tiredness.

These observations suggest *hypotheses* that must be checked against other data.

---

## PART 5 — INSTRUMENT LIBRARY (INS)

### INS-00 Rules for choosing instruments
1. Start with the referral question, not with whatever test you usually give.
2. Choose tools with evidence for this purpose *and* this population (age, language, culture, disability).
3. Prefer current editions and local norms.
4. Combine methods: interview, observation and objective tests (projectives only as an add-on).
5. Check the licence (0.4) and the required competence level (0.5).

### INS-01 Theories of intelligence (for interpretation and training)
| Theory | Central idea | What it means for assessment |
|---|---|---|
| Galton; J. M. Cattell | Intelligence reflects sensory sharpness and reaction speed | Lives on in reaction-time research (correlations with IQ of roughly .3–.5) |
| Spearman | A general factor **g** plus specific factors **s** | The full-scale composite is the single best predictor |
| Thurstone | Seven **primary mental abilities**: verbal comprehension, word fluency, number, spatial, associative memory, perceptual speed, induction | Profiles of group factors; these abilities change differently with age |
| Vernon | Hierarchy: g → two major group factors (verbal-educational; practical-mechanical) → minor and specific factors | Bridges g and group-factor views |
| Cattell & Horn | **Fluid** reasoning (gf) with new problems vs **crystallised** knowledge (gc) | gf declines earlier in adulthood; basis for non-verbal tests |
| Cattell–Horn–Carroll (CHC) | Three levels: g → broad abilities → narrow abilities | Blueprint for most modern batteries (WJ, SB5, WISC-V) |
| Guilford | Structure of intellect: operations × contents × products; divergent thinking | Creativity measurement |
| Piaget | Stages: sensorimotor (0–2), preoperational (2–6), concrete operational (7–12), formal operational (12+); schemas adapt through assimilation and accommodation toward equilibrium | Cognitive milestones in children (e.g., conservation) |
| Luria; PASS model | Simultaneous and successive processing, plus planning and attention | K-ABC; Das–Naglieri Cognitive Assessment System |
| Information processing | Speed and capacity ("hardware") plus strategies and **metacognition** ("software") | Training strategy use and self-monitoring |
| Biological | Brain efficiency (e.g., lower glucose use during tasks in higher scorers) | Research only |
| Gardner | Multiple intelligences — linguistic, logical-mathematical, spatial, musical, bodily-kinaesthetic, interpersonal, intrapersonal, naturalist | Useful for enrichment; weak psychometric backing (Evidence C) |
| Sternberg | Triarchic theory — analytic, creative (handling novelty and automating skills) and practical (adapting to, selecting and shaping environments) | Standard IQ tests miss practical intelligence |

**Where experts and the public agree:** intelligence is the ability to learn from experience and adapt to one's surroundings, with verbal ability, problem solving and practical sense at its core.

### INS-02 Individual intelligence tests
| Instrument (current edition) | Ages | Structure | Notes | Licence |
|---|---|---|---|---|
| **WAIS** (WAIS-IV; WAIS-5 published in the US in 2024 — confirm local availability) | 16–90 | Index scores (verbal comprehension, perceptual/fluid reasoning, working memory, processing speed) + FSIQ; M = 100, SD = 15; subtests M = 10, SD = 3 | Reference standard for adult IQ | RQ |
| **WISC** (WISC-V) | 6–16 | Five primary indexes + FSIQ | Child IQ; learning-difficulty and ADHD assessment | RQ |
| **WPPSI** (WPPSI-IV) | 2:6–7:7 | Preschool indexes | Early years | RQ |
| **Stanford-Binet 5** | 2–85+ | Five factors (fluid reasoning, knowledge, quantitative, visual-spatial, working memory), each verbal and non-verbal (10 subtests); routing subtests; built with IRT | Wide range — high ceiling for giftedness, low floor for intellectual disability | RQ |
| **K-ABC-II / KAIT** | 3–18 / 11–85 | Sequential and simultaneous processing (Luria) and CHC | Less dependent on cultural knowledge | RQ |
| **K-BIT-2** | 4–90 | Verbal + matrices, about 20 minutes | **Screening only** — individual results can differ from a full IQ by up to about 25 points | RQ |
| **DTLA-4** | 6–17 | 10 subtests, 16 composites | Composites overlap heavily; interpret with care | PUB |
| **Indian adaptations** (e.g., MISIC, Bhatia Battery, Binet-Kamat, WAPIS — check current status and norms) | Various | Adapted Wechsler or Binet material | Norms often old; use where Indian norms are essential | PUB |

**What Wechsler-type subtests tap (short descriptions):**
- **Information:** general knowledge from long-term memory; influenced by schooling and reading.
- **Digit Span:** attention and auditory working memory; backward span relates more strongly to g than forward.
- **Vocabulary:** word knowledge acquired from experience; the strongest single indicator of g.
- **Arithmetic:** timed mental arithmetic drawing on concentration and working memory.
- **Comprehension:** understanding of social rules and practical judgement.
- **Similarities:** abstract verbal reasoning and concept formation.
- **Letter–Number Sequencing:** working memory; sensitive to brain injury.
- **Picture Completion:** noticing missing visual details; long-term memory.
- **Picture Arrangement** (older editions): putting social events in order.
- **Block Design:** analysing and rebuilding visual patterns; the best non-verbal/perceptual subtest; timed.
- **Matrix Reasoning:** untimed non-verbal reasoning.
- **Object Assembly:** perceptual organisation; relatively unreliable.
- **Coding / Digit Symbol:** processing speed and incidental learning; highly sensitive to ageing and brain dysfunction.
- **Symbol Search:** processing speed.
- **Mazes:** planning and impulse control.

**Order of interpretation:** FSIQ → index scores → meaningful gaps between indexes → subtest strengths and weaknesses (as hypotheses only).

⚠ **Scatter and pattern analysis:** Most proposed "diagnostic" subtest patterns (for example, low Digit Span, Arithmetic and Coding read as a sign of anxiety) are **not supported by research**. Large gaps are common in ordinary people — around a fifth to a quarter show verbal–performance differences of 15 points or more. Treat any pattern as a hypothesis (Evidence D). The **content** of answers, such as strange or idiosyncratic responses, can still flag possible thought disorder for follow-up.

### INS-03 Group and culture-reduced intelligence tests
| Test | Notes |
|---|---|
| **Raven's Progressive Matrices** (Coloured for ages 5–11; Standard; Advanced) | Non-verbal pattern reasoning; very useful when language or hearing is limited. Not culture-free, and some capable adults do poorly on it |
| **Culture Fair Intelligence Test** (R. B. Cattell) | Targets fluid g; heavily timed; in practice no fairer than the Stanford-Binet for disadvantaged groups |
| **CogAT** | School-level battery with verbal, quantitative and non-verbal sections |
| **Shipley-2** | Short vocabulary and abstract-reasoning screen (not a valid test for brain damage) |
| **Army Alpha/Beta, ASVAB, GATB, DAT** | See INS-06 |

**Principle:** tests can only be more or less culture-reduced; none is culture-free.

### INS-04 Infant and preschool assessment
| Instrument | Ages | Notes |
|---|---|---|
| Bayley Scales (Bayley-4) | 1–42 months | Cognitive, language, motor, social-emotional and adaptive domains |
| Gesell Developmental Schedules | 4 weeks – 6 years | Developmental milestones |
| Brazelton Neonatal Behavioral Assessment Scale | Newborns | Reflexes and behaviour; sensitive to prenatal exposures; useful for parent guidance |
| Uzgiris–Hunt Ordinal Scales | 2 weeks – 2 years | Piaget-based (object permanence and similar) |
| WPPSI-IV, SB5, K-ABC-II, DAS-II, McCarthy | 2:6 upward | Preschool cognitive ability |
| Denver-II | 0–6 | Developmental screening |
| Fagan Test of Infant Intelligence | 6–12 months | Preference for novel images / visual recognition memory (research use) |

⚠ **Key rule:** Scores in the average range in infancy **do not predict** later IQ (correlations of roughly 0 to .3 before 18 months). **Very low scores (2 SD or more below average) do predict** later disability. Use infant tests to **screen for developmental delay**, not to forecast intelligence. Preschool scores become fairly stable from around age 6–8.

### INS-05 Intellectual disability — classification (current terminology)
All **three** conditions are required:
1. Intellectual functioning well below average (IQ around 70–75 or lower, allowing for measurement error)
2. Limitations in adaptive behaviour (conceptual, social and practical)
3. Onset during the developmental period (DSM-5-TR and AAIDD now use "developmental period" rather than a fixed age of 18)

**An IQ score alone never establishes the diagnosis.**

| Severity (DSM-5-TR / ICD-11) | Approximate IQ | Support intensity (AAIDD) | Usual adult functioning |
|---|---|---|---|
| Mild | 50/55 – 70/75 | Intermittent | Academic skills up to about grade 6; largely independent living with some support |
| Moderate | 35/40 – 50/55 | Limited | Academic skills around grades 2–4; supervised work and living |
| Severe | 20/25 – 35/40 | Extensive | Basic self-care with training |
| Profound | below 20/25 | Pervasive | Needs continuous care |

(DSM-5-TR bases severity on adaptive functioning, not IQ ranges; the IQ figures are for orientation only.)

### INS-06 Aptitude and achievement
- **Achievement** measures what has already been learned; **aptitude** predicts future learning. The distinction lies mostly in how the scores are used rather than in the items themselves.
- **Multiple-aptitude batteries** (built with factor analysis):
  - **DAT:** verbal, numerical, abstract, clerical speed, mechanical, spatial, spelling, language use. Verbal plus numerical approximates scholastic aptitude. Subtests correlate too highly for detailed profile reading.
  - **GATB:** nine factors grouped as cognitive, perceptual and psychomotor; good predictor of job-training success.
  - **ASVAB / CAT-ASVAB:** a leading example of computer-adaptive testing.
- **School achievement batteries:** e.g., ITBS, MAT, TAP, ITED, Stanford, GED. **Lexile measures** put reader ability and text difficulty on the same equal-interval scale; when they match, expected comprehension is about 75%.
- **Admission tests:** SAT, ACT, GRE, MCAT, LSAT — moderate predictive validity (r ≈ .3–.5), reduced by restriction of range.
- ⚠ **Integrity of high-stakes testing:** pressure encourages teaching to the test, irregular administration and outright cheating (the "Lake Wobegon" phenomenon, where nearly every district reports above-average results). The app should log administration conditions and flag anomalies such as implausible score jumps.

### INS-07 Objective personality inventories
| Instrument | Items / format | Scales | Notes | Licence |
|---|---|---|---|---|
| **MMPI-2** (also MMPI-2-RF; **MMPI-3**, 2020) | 567 true/false | Validity: ? (cannot say), L, F, K, VRIN, TRIN. Clinical scales 1–0 (Hs, D, Hy, Pd, Mf, Pa, Pt, Sc, Ma, Si); content and supplementary scales | T ≥ 65 is clinically elevated; interpretation by code type (e.g., elevated 1-2-3 pattern; 6-8 with possible psychotic features). Consider demographic influences | RQ |
| **16PF** (5th ed.) | Three-choice items | 16 primary traits and 5 global factors | Normal-range personality; counselling | PUB |
| **NEO-PI-3 / NEO-FFI-3** | 240 / 60 items, 5-point | **Five-factor model:** Openness, Conscientiousness, Extraversion, Agreeableness, Neuroticism, with 30 facets | The mainstream model of personality structure | PUB |
| **EPQ-R** (Eysenck) | Yes/No | Psychoticism, Extraversion, Neuroticism, Lie | Biologically based trait model | PUB |
| **CPI** | True/false | 20 "folk concept" scales for ordinary adults | Counselling, leadership | PUB |
| **MCMI-IV** (Millon) | 195 true/false | Personality patterns and clinical syndromes linked to DSM | Clinical populations only | RQ |
| **EPPS** | 225 forced-choice pairs | 15 needs from Murray's theory (e.g., achievement, order, autonomy, affiliation, dominance, nurturance, change, endurance, aggression) | Ipsative — compare within the person only | PUB |
| **MBTI** | Forced choice | Four dichotomies → 16 types | Popular in organisations; types are unstable on retest; not for clinical or hiring decisions (Evidence C) | PUB |
| **Jenkins Activity Survey** | 52 multiple choice | Type A behaviour: speed/impatience, job involvement, hard-driving | Research use. Hostility is the component most linked to heart disease | PUB |
| **STAI** | 40 items, 4-point | State and trait anxiety | Strong psychometrics | PUB |
| **Rotter I-E Scale** | 29 forced-choice pairs | Internal vs external locus of control | Internal locus is linked to better outcomes | FREE (research) |
| **Self-efficacy scales** (Bandura's method) | Confidence ratings 0/10–100 per task | Task-specific self-efficacy | A criterion-referenced tool for therapy | FREE |
| **PIC-2** | Parent-report true/false | Child adjustment | Ages 5–19 | PUB |
| **Q-sort** (Stephenson; used by Rogers) | About 100 statements sorted into 9 piles | Correlation of real-self and ideal-self sorts | Tracks change in self-concept during therapy | FREE (method) |

**Personality theories behind interpretation:**
- **Psychodynamic:** id, ego and superego; defence mechanisms, ranked by Vaillant from psychotic through immature and neurotic to mature defences (altruism, humour, suppression, anticipation, sublimation).
- **Type approaches:** e.g., Type A / Type B.
- **Phenomenological:** Rogers' self theory — the fit between actual and ideal self.
- **Behavioural and social learning:** Rotter's expectancies; Bandura's self-efficacy.
- **Trait approaches:** Allport, R. B. Cattell, Eysenck, the five-factor model.

### INS-08 Projective techniques
**Projective hypothesis:** how people respond to ambiguous material reveals needs and conflicts they may not be aware of.

⚠ **The projective puzzle:** these methods remain widely used even though their average psychometric quality is poor. Two reasons:
1. **Illusory correlation** — clinicians perceive expected links between signs and symptoms even where none exist (Chapman & Chapman).
2. In practice they work mainly as *conversation aids* that generate hypotheses.

**Rule:** a projective finding appears in a report only when other data back it up.

| Technique | Procedure | Scoring | Evidence |
|---|---|---|---|
| **Rorschach** | Ten inkblots; responses, then an inquiry phase | **Exner Comprehensive System / R-PAS** (location, determinants, form quality, content, popular responses); perceptual-accuracy indices | B with standardised scoring (for thought disorder); D with intuitive scoring. Psychosis can be faked |
| **Holtzman Inkblot Technique** | 45 blots, one response each; two parallel forms | 22 objective variables | B, but seldom used |
| **TAT** | 20 picture cards; the client tells a story with a past, present, feelings and ending | Needs and environmental pressures, identification with the hero; mostly qualitative | C (retest r around .3 when formally scored) |
| **CAT / SAT / AAC / TEMAS** | TAT-style versions for children, older adults, adolescents and Hispanic groups | Qualitative | C |
| **Picture Projective Test** | Photographs with a more positive tone than TAT cards | Emotional tone, activity level | C |
| **Sentence completion** (Rotter Incomplete Sentences Blank, custom stems) | The client finishes sentence beginnings | Rotter ISB: each item scored 0–6 for conflict, summed into an adjustment score (cut-off around 135) | B for screening adjustment |
| **Rosenzweig Picture-Frustration Study** | Cartoon scenes showing frustration | Direction of aggression (outward, inward, avoided) × type of reaction | C (low reliability) |
| **Word association** (Galton; Jung) | Say the first word that comes to mind | Response time, content, disruptions | C |
| **Drawings** (Draw-a-Person, House-Tree-Person, Goodenough-Harris, Koppitz) | Draw a person / a house, tree and person | Goodenough-Harris gives a developmental ability estimate (B); emotional "signs" (D) | DAP:SPED for screening only |

### INS-09 Neuropsychological tests
| Instrument | Measures | Notes |
|---|---|---|
| **Bender Visual-Motor Gestalt Test, 2nd ed.** | Visual-motor integration | Koppitz and Lacks scoring systems; screens for brain dysfunction and perceptual-motor development; not a measure of IQ or achievement |
| **Wechsler Memory Scale (WMS-IV)** | Auditory and visual memory, immediate and delayed; working memory | Index M = 100 |
| **Halstead-Reitan Battery** | Category Test (abstraction), Tactual Performance, Speech-Sounds Perception, Seashore Rhythm, Finger Tapping and others | Impairment index; localisation and lateralisation; 6–12 hours |
| **Luria-Nebraska Battery** | Scales for motor, rhythm, tactile, visual, receptive and expressive speech, writing, reading, arithmetic, memory and intellectual processes | About 2.5 hours; profile analysis |
| Supporting data | CT, MRI, PET/fMRI | Multidisciplinary diagnosis |

**Level: L3 only.** Because impaired groups change over time, reliability is often inferred from validity data.

### INS-10 Adaptive behaviour
| Instrument | Notes |
|---|---|
| **Vineland-3** | The most widely used; semi-structured caregiver interview covering communication, daily living, socialisation, motor skills and maladaptive behaviour |
| **SIB-R** (Scales of Independent Behavior–Revised) | 14 subscales in four clusters (motor, social/communication, personal living, community living) plus a problem-behaviour scale; co-normed with the Woodcock-Johnson |
| **ABAS-3; AAIDD Adaptive Behavior Scales** | Include maladaptive areas such as aggression, withdrawal and stereotyped behaviour |
| **Independent Living Behavior Checklist** | Several hundred criterion-referenced skills, each with a condition, behaviour and standard; designed for training plans rather than diagnosis |

### INS-11 Instruments for special populations (see POP)
| Group | Instruments |
|---|---|
| Little or no spoken language; deaf; autistic | **Leiter-3** (entirely non-verbal, gesture instructions), **UNIT-2**, **TONI-4**, Raven's, Hiskey-Nebraska |
| Motor impairment; non-readers | **PPVT-5** (client points to a picture; receptive vocabulary). ⚠ Not a complete IQ test; may underestimate some groups |
| Visually impaired | Perkins-Binet, verbal Wechsler subtests, Blind Learning Aptitude Test |
| Deaf / hard of hearing | Wechsler non-verbal subtests; signed administration by a fluent examiner (not a family member acting as interpreter) |

### INS-12 Interests, values and careers
| Instrument | Model | Notes |
|---|---|---|
| **Strong Interest Inventory** | Empirical occupational scales, Holland themes and four personal-style scales (work, learning, leadership, risk-taking) | Highly stable after about age 25; predicts which occupations people enter |
| **Self-Directed Search / Vocational Preference Inventory** (Holland) | **RIASEC:** Realistic, Investigative, Artistic, Social, Enterprising, Conventional — arranged on a hexagon where neighbours are most similar | Self-scored three-letter code linked to an occupations list |
| **Kuder (KOIS / KGIS)** | Forced-choice triads; ipsative | KGIS for school grades 6–12 |
| **Jackson Vocational Interest Survey** | Work roles and work styles; forced choice | Resists social-desirability bias |
| **Campbell Interest and Skill Survey** | Seven orientations (influencing, organising, helping, creating, analysing, producing, adventuring) with matching interest *and* skill scores | Easy-to-read reports |
| **Values:** Rokeach Value Survey (18 terminal and 18 instrumental values, ranked, ipsative; research use); Study of Values (Spranger's six value types); Work Values Inventory; **Minnesota Importance Questionnaire** (20 needs and 6 values, matched to occupational reinforcer patterns); Values Scale (Nevill & Super; cross-cultural) | | |
| **Career development:** Career Development Inventory (Super's life stages — growth, exploration, establishment, maintenance, disengagement); Career Beliefs Inventory; Career Thoughts Inventory | | |

**Working model of career fit:** productivity reflects ability multiplied by interest, shaped further by **personality** (e.g., drive to achieve, dominance, emotional stability), **social skill** (demands differ by job), and **opportunity**, which no test captures. See CNS-01.

### INS-13 Attitudes, moral reasoning, spirituality
- **Attitude:** a learned tendency to evaluate something favourably or unfavourably, with thinking, feeling and behavioural components.
  - Measurement: Likert, Thurstone and Guttman scales; behavioural observation; indirect methods (the lost-letter technique; the **Implicit Association Test**); physiological measures.
  - Attitudes predict behaviour best when they are strong, easy to bring to mind and specific to the behaviour.
- **Kohlberg's stages of moral reasoning:**
  - Pre-conventional: (1) avoiding punishment, (2) self-interest and fair exchange
  - Conventional: (3) seeking approval, (4) upholding rules and order
  - Post-conventional: (5) social contract, (6) universal ethical principles
  - Measures: the Moral Judgment Interview (reliable with modern scoring); the **Defining Issues Test (DIT-2**, P and N2 indices). ⚠ The DIT may under-score religiously conservative respondents, and its dilemmas feel dated.
- **Gratitude (GQ-6)** and other positive-psychology scales: brief, reliable and generally free for research (confirm terms before commercial use).

### INS-14 FULL-TEXT SCALES READY FOR DIGITISATION
*Why the item wording below is not rewritten:* a validated scale's norms, cut-offs and reliability belong to its exact wording. Paraphrasing the items would make the published scores meaningless and would create an unvalidated derivative. So these items are reproduced **exactly**, and only for instruments whose owners allow free reproduction. All instructions, notes and interpretive text around them are our own. Always show the citation (and any required notice) on screen.

| Instrument | Licence position (verify before commercial release) |
|---|---|
| HAM-A | Public domain (published 1959) |
| DASS-21 | Authors state the questionnaire is public domain and may be copied freely; do not alter items or charge for the scale itself |
| PHQ-9, GAD-7 | Free to reproduce, translate, display and distribute without permission; show the Pfizer/authors notice |
| RSES | Free for research and education; ⚠ get written confirmation from the rights holders before use in a paid commercial app |

---
#### INS-HAMA: Hamilton Anxiety Rating Scale (HAM-A)
- **Construct:** how severe anxiety is, across psychological and physical symptoms. **Rated by:** clinician, through interview. **Licence:** PD. **Evidence:** A (as an outcome measure).
- **Scoring:** each item is rated 0 = Not present, 1 = Mild, 2 = Moderate, 3 = Severe, 4 = Very severe. Total range 0–56.
- **Subscores:** Psychic anxiety = items 1–6 and 14; Somatic anxiety = items 7–13.

| # | Item | Descriptors |
|---|---|---|
| 1 | Anxious mood | Worries, anticipation of the worst, fearful anticipation, irritability |
| 2 | Tension | Feelings of tension, fatigability, startle, moved to tears easily, trembling, restlessness, inability to relax |
| 3 | Fears | Of dark, strangers, being left alone, animals, traffic, crowds |
| 4 | Insomnia | Difficulty falling asleep, broken sleep, unsatisfying sleep and fatigue on waking, dreams, nightmares, night terrors |
| 5 | Intellectual | Difficulty in concentration, poor memory |
| 6 | Depressed mood | Loss of interest, lack of pleasure in hobbies, depression, early waking, diurnal swing |
| 7 | Somatic (muscular) | Pains, aches, twitching, stiffness, myoclonic jerks, grinding of teeth, unsteady voice, increased muscular tone |
| 8 | Somatic (sensory) | Tinnitus, blurred vision, hot and cold flushes, feelings of weakness, pricking sensation |
| 9 | Cardiovascular | Tachycardia, palpitations, chest pain, throbbing of vessels, fainting feelings, missing beat |
| 10 | Respiratory | Pressure or constriction in chest, choking feelings, sighing, dyspnoea |
| 11 | Gastrointestinal | Difficulty swallowing, wind, abdominal pain, burning, fullness, nausea, vomiting, borborygmi, loose bowels, weight loss, constipation |
| 12 | Genitourinary | Frequency or urgency of micturition, amenorrhoea, menorrhagia, frigidity, premature ejaculation, loss of libido, impotence |
| 13 | Autonomic | Dry mouth, flushing, pallor, sweating, giddiness, tension headache, raising of hair |
| 14 | Behaviour at interview | Fidgeting, restlessness or pacing, hand tremor, furrowed brow, strained face, sighing or rapid respiration, facial pallor, swallowing |

**Severity bands (one common convention; sources differ):**
| Total | Severity |
|---|---|
| ≤ 17 | Mild |
| 18–24 | Mild to moderate |
| 25–30 | Moderate to severe |
| > 30 | Severe |

(Some trials treat scores below 8 as no or minimal anxiety.)

⚠ The original scale gives no standard questions, so raters need training. It does not distinguish anxiety well from depression or from medication side-effects.
*Citation: Hamilton, M. (1959). The assessment of anxiety states by rating. British Journal of Medical Psychology, 32, 50–55.*

---
#### INS-DASS21: Depression Anxiety Stress Scales – 21
- **Construct:** dimensional severity of depression, anxiety and stress over **the past week**. **Self-report.** Ages 17+ (use cautiously with adolescents). **Licence:** PD/FREE (see table above). **Evidence:** A.
- **Instruction and response options (exact wording):**

**Instruction:** Please read each statement and select a number 0, 1, 2 or 3 which indicates how much the statement applied to you over the past week. There are no right or wrong answers. Do not spend too much time on any statement.
  - 0 = Did not apply to me at all
  - 1 = Applied to me to some degree, or some of the time
  - 2 = Applied to me to a considerable degree, or a good part of time
  - 3 = Applied to me very much, or most of the time

(The Scale column is for scoring only — do not show it to the client.)

| # | Item | Scale |
|---|---|---|
| 1 | I found it hard to wind down | S |
| 2 | I was aware of dryness of my mouth | A |
| 3 | I couldn't seem to experience any positive feeling at all | D |
| 4 | I experienced breathing difficulty (e.g., excessively rapid breathing, breathlessness without physical exertion) | A |
| 5 | I found it difficult to work up the initiative to do things | D |
| 6 | I tended to over-react to situations | S |
| 7 | I experienced trembling (e.g., in the hands) | A |
| 8 | I felt that I was using a lot of nervous energy | S |
| 9 | I was worried about situations in which I might panic and make a fool of myself | A |
| 10 | I felt that I had nothing to look forward to | D |
| 11 | I found myself getting agitated | S |
| 12 | I found it difficult to relax | S |
| 13 | I felt down-hearted and blue | D |
| 14 | I was intolerant of anything that kept me from getting on with what I was doing | S |
| 15 | I felt I was close to panic | A |
| 16 | I was unable to become enthusiastic about anything | D |
| 17 | I felt I wasn't worth much as a person | D |
| 18 | I felt that I was rather touchy | S |
| 19 | I was aware of the action of my heart without physical exertion (e.g., increased heart rate, missed beat) | A |
| 20 | I felt scared without any good reason | A |
| 21 | I felt that life was meaningless | D |

**Scoring key:**
- Depression = items 3, 5, 10, 13, 16, 17, 21
- Anxiety = items 2, 4, 7, 9, 15, 19, 20
- Stress = items 1, 6, 8, 11, 12, 14, 18
- Add the items in each subscale, then **double the sum** (so scores are comparable with the 42-item DASS).

| Severity | Depression | Anxiety | Stress |
|---|---|---|---|
| Normal | 0–9 | 0–7 | 0–14 |
| Mild | 10–13 | 8–9 | 15–18 |
| Moderate | 14–20 | 10–14 | 19–25 |
| Severe | 21–27 | 15–19 | 26–33 |
| Extremely severe | 28+ | 20+ | 34+ |

⚠ Measures severity on a continuum; it does not diagnose and never replaces an interview. High ratings on depression items 10, 17 or 21 should prompt a risk review (ASM-06).
*Citation: Lovibond, S. H., & Lovibond, P. F. (1995). Manual for the Depression Anxiety Stress Scales (2nd ed.). Sydney: Psychology Foundation.*

---
#### INS-PHQ9: Patient Health Questionnaire-9
- **Construct:** depression severity based on DSM criteria, over the **last 2 weeks**. **Self-report.** **Licence:** free, no permission needed. **Evidence:** A.
- **Instruction and response options (exact wording):**

**Instruction:** Over the last 2 weeks, how often have you been bothered by any of the following problems?
  - 0 = Not at all · 1 = Several days · 2 = More than half the days · 3 = Nearly every day

1. Little interest or pleasure in doing things
2. Feeling down, depressed, or hopeless
3. Trouble falling or staying asleep, or sleeping too much
4. Feeling tired or having little energy
5. Poor appetite or overeating
6. Feeling bad about yourself — or that you are a failure or have let yourself or your family down
7. Trouble concentrating on things, such as reading the newspaper or watching television
8. Moving or speaking so slowly that other people could have noticed; or the opposite — being so fidgety or restless that you have been moving around a lot more than usual
9. Thoughts that you would be better off dead, or of hurting yourself in some way

*Functional item (not scored):* "If you checked off any problems, how difficult have these problems made it for you to do your work, take care of things at home, or get along with other people?" (Not difficult at all / Somewhat difficult / Very difficult / Extremely difficult)

**App rule:** any score above 0 on item 9 launches ASM-06.

| Total (0–27) | Severity |
|---|---|
| 0–4 | Minimal |
| 5–9 | Mild |
| 10–14 | Moderate |
| 15–19 | Moderately severe |
| 20–27 | Severe |

A total of 10 or more is the usual screening threshold.
*Citation: Kroenke, K., Spitzer, R. L., & Williams, J. B. W. (2001). The PHQ-9. Journal of General Internal Medicine, 16, 606–613.*
*Required notice: Developed by Drs. Robert L. Spitzer, Janet B. W. Williams, Kurt Kroenke and colleagues, with an educational grant from Pfizer Inc. No permission required to reproduce, translate, display or distribute.*

---
#### INS-GAD7: Generalized Anxiety Disorder-7
- **Construct:** generalised anxiety severity over the **last 2 weeks**; uses the same 0–3 response options as the PHQ-9. **Licence:** free, no permission needed. **Evidence:** A.

1. Feeling nervous, anxious, or on edge
2. Not being able to stop or control worrying
3. Worrying too much about different things
4. Trouble relaxing
5. Being so restless that it is hard to sit still
6. Becoming easily annoyed or irritable
7. Feeling afraid, as if something awful might happen

| Total (0–21) | Severity |
|---|---|
| 0–4 | Minimal |
| 5–9 | Mild |
| 10–14 | Moderate |
| 15–21 | Severe |

A total of 10 or more is the screening threshold.
*Citation: Spitzer, R. L., Kroenke, K., Williams, J. B. W., & Löwe, B. (2006). Archives of Internal Medicine, 166, 1092–1097.* Show the same Pfizer notice as for the PHQ-9.

---
#### INS-RSES: Rosenberg Self-Esteem Scale
- **Construct:** overall sense of self-worth (one dimension). **Self-report**, 10 items, 4 response options. **Licence:** FREE for research/education — ⚠ confirm commercial use (see table). **Evidence:** A.
- **Items (exact wording; instruction lightly adapted for screen use):**

**Instruction:** Below is a list of statements dealing with your general feelings about yourself. Indicate how strongly you agree or disagree with each.
Response options: Strongly Agree · Agree · Disagree · Strongly Disagree

| # | Item | Keying |
|---|---|---|
| 1 | On the whole, I am satisfied with myself. | + |
| 2 | At times I think I am no good at all. | − |
| 3 | I feel that I have a number of good qualities. | + |
| 4 | I am able to do things as well as most other people. | + |
| 5 | I feel I do not have much to be proud of. | − |
| 6 | I certainly feel useless at times. | − |
| 7 | I feel that I'm a person of worth, at least on an equal plane with others. | + |
| 8 | I wish I could have more respect for myself. | − |
| 9 | All in all, I am inclined to feel that I am a failure. | − |
| 10 | I take a positive attitude toward myself. | + |

**Scoring:**
- **Positively worded items (1, 3, 4, 7, 10):** Strongly Agree = 4, Agree = 3, Disagree = 2, Strongly Disagree = 1.
- **Negatively worded items (2, 5, 6, 8, 9) — reverse-scored:** Strongly Agree = 1, Agree = 2, Disagree = 3, Strongly Disagree = 4.
- **Total 10–40**; higher = higher self-esteem. Use it as a continuous score — there are no official cut-offs.
- If the alternative 0–3 scoring is used (range 0–30), scores under 15 are often described as low.

**Interpretation notes from the research:**
- Higher self-esteem is linked mainly to taking initiative and feeling good. It does not appear to *produce* better grades or work performance; success tends to lift self-esteem rather than the other way round.
- Blanket praise can encourage narcissism; tie praise to real effort and achievement.
- Low self-esteem is associated with sadness and depression risk, and hope predicts school results better than self-esteem (Baumeister et al., 2003; Ciarrochi et al., 2007).

*Citation: Rosenberg, M. (1965). Society and the Adolescent Self-Image. Princeton, NJ: Princeton University Press.*

---
#### INS-EIR: YourCounselor Emotional Intelligence Reflection (YC-EIR) — original in-house tool
*Replaces the former INS-EQSA, which depended on a third-party workbook. Every item below is newly written for YourCounselor AI.*
- **Construct:** five areas of emotional competence, following the widely used five-domain model popularised by Goleman (1995): Self-awareness (SA), Managing emotions (ME), Self-motivation (MO), Empathy (E), Social skills (SS).
- **Format:** 25 statements, 5 per domain, rated 1–5: 1 = Rarely true of me · 2 = Occasionally true · 3 = True about half the time · 4 = Usually true · 5 = Almost always true.
- **Licence:** IH. **Evidence:** IH / D — not a validated psychometric test; answers shift with mood and self-image.

| # | Statement | Domain |
|---|---|---|
| 1 | I can usually name the emotion I am feeling while it is happening. | SA |
| 2 | When I feel angry, I can pause before I react. | ME |
| 3 | I keep working toward a goal even when progress is slow. | MO |
| 4 | I can sense how someone feels even when they don't say it. | E |
| 5 | I can disagree with someone without damaging the relationship. | SS |
| 6 | I notice how my mood affects the way I treat people. | SA |
| 7 | I bounce back from disappointments within a reasonable time. | ME |
| 8 | I can get myself started on tasks I don't enjoy. | MO |
| 9 | I listen fully before giving my own opinion. | E |
| 10 | I find it easy to start a conversation with someone new. | SS |
| 11 | I know which situations are likely to unsettle me. | SA |
| 12 | I have ways to calm myself when I feel tense. | ME |
| 13 | When something goes wrong, I look for what I can learn from it. | MO |
| 14 | I can see a situation from another person's side, even when I disagree. | E |
| 15 | I can help other people settle a disagreement. | SS |
| 16 | I can tell whether I am tired, hungry or genuinely upset. | SA |
| 17 | I rarely say things in the heat of the moment that I regret later. | ME |
| 18 | I set myself goals that stretch me. | MO |
| 19 | People tell me I understand them well. | E |
| 20 | I ask for help when I need it. | SS |
| 21 | I have a realistic sense of my strengths and weak spots. | SA |
| 22 | I stay composed when I am under pressure. | ME |
| 23 | I stay hopeful about my goals when things get hard. | MO |
| 24 | I notice when someone in a group is being left out. | E |
| 25 | I work well as part of a team. | SS |

**Scoring key (items rotate through the five domains):**
| Domain | Items |
|---|---|
| SA | 1, 6, 11, 16, 21 |
| ME | 2, 7, 12, 17, 22 |
| MO | 3, 8, 13, 18, 23 |
| E | 4, 9, 14, 19, 24 |
| SS | 5, 10, 15, 20, 25 |

**Bands (each domain 5–25):**
| Score | Meaning |
|---|---|
| 18–25 | Strength |
| 10–17 | Worth attention |
| 5–9 | Development priority |

**Use:** a coaching and self-reflection aid for choosing one or two development goals. **Never** for clinical or selection decisions. For validated measurement, license an established instrument (e.g., MSCEIT, EQ-i 2.0, TEIQue).

---

## PART 6 — INTERVENTION LIBRARY (INT)

### INT-01 Core counselling micro-skills (all levels)
| Skill | Purpose | Example |
|---|---|---|
| Attending | Communicate presence | Relaxed open posture; eye contact adjusted to cultural norms |
| Open questions | Invite the client to expand | "How did that feel for you?" |
| Closed questions | Pin down facts | "Which month did this begin?" |
| Paraphrasing | Mirror the content | "So since the transfer, you've felt quite alone at work." |
| Reflecting feelings | Put a name to the emotion | "It sounds like you're disappointed, and maybe a little resentful." |
| Summarising | Tie things together and close a topic | "Let me gather up what we've talked about so far…" |
| Silence | Give the client room to think | Wait 5–10 seconds after an emotional disclosure |
| Validation | Show that feelings make sense | "Given everything that happened, that reaction is understandable." |
| Immediacy | Talk about what is happening between you right now | "I noticed you became quiet when we got onto your father." |

### INT-02 Talk therapy (supportive / psychodynamically informed)
- **Aim:** identify what is causing distress, understand how pressures are affecting the client's life, and develop better ways of coping.
- **Evidence:** A for psychotherapy in general; varies by specific approach.
- **Level:** L1–L2.
- **Format:** 45–60-minute sessions — weekly at first (twice weekly in a crisis), moving to fortnightly as things improve.
- **Methods:**
  - *Free association:* the client speaks about whatever comes to mind without filtering.
  - *Working with transference:* feelings the client develops toward the therapist often echo other relationships and can be explored gently.
  - *Focusing:* after open exploration, the therapist condenses what has emerged into one clear problem statement so the work can move on to solutions.
- **Benefits:** a trustworthy, neutral listener; new coping strategies; symptom relief; may prevent problems becoming entrenched.
- **Drawbacks:** it can feel awkward to open up to a stranger; progress may be slow; cost and time.

### INT-03 Behaviour therapy / behaviour modification
**Foundations:**
- Behaviour means what a person does in their surroundings. Whether it is a problem is judged against norms and goals, not moral labels.
- Difficulties are either **excesses** (too much of something, e.g., tantrums) or **deficits** (too little, e.g., social skills).
- Behaviour modification uses learning principles to reduce unwanted behaviour and to build and strengthen helpful behaviour.

**Learning principles**
| | Something is added | Something is taken away |
|---|---|---|
| **Behaviour increases** | Positive reinforcement (e.g., praise) | Negative reinforcement (e.g., a car's warning beep stops once the belt is fastened) |
| **Behaviour decreases** | Positive punishment (e.g., a reprimand) | Negative punishment (e.g., losing screen time) |

**Functional analysis (ABC):** Antecedent → Behaviour → Consequence.
*Example:* The team meeting starts (A) → the employee stays silent despite having ideas (B) → avoids the anxiety of speaking but is overlooked for projects (C).
Keep ABC records for one to two weeks before intervening.

**Technique cards**

**INT-03a Systematic desensitisation** (Wolpe)
- Indications: phobias and specific anxieties. Evidence: A (for exposure-based methods). Level: L2.
- **Rationale:** reciprocal inhibition — a relaxed body cannot be highly anxious at the same time, so relaxation is paired with feared cues.
- **Steps:**
  1. *Learn relaxation:* slow diaphragmatic breathing and progressive muscle relaxation, practised daily until the client can relax quickly.
  2. *Build a hierarchy:* 10–15 feared situations rated 0–100 on SUDS and listed from least to most frightening. *Example (fear of lifts):* looking at a photo of a lift → standing near a lift → stepping in with the doors open → riding one floor with the therapist → riding several floors alone.
  3. *Graded exposure:* in imagination and/or real life while relaxed. Advance only when the current step produces little anxiety (SUDS around 20–30 or lower); if anxiety climbs, go back a step.
- Contraindications ⚠: uncontrolled heart conditions (for real-life exposure), active psychosis, recent trauma without prior stabilisation.

**INT-03b Exposure (with response prevention for OCD):** Contact with the feared situation — gradual or intensive — while escape and rituals are blocked, allowing fear to reduce through extinction and new learning. Evidence: A.

**INT-03c Token economy:** The client earns tokens for agreed target behaviours and trades them for rewards. Decide in advance which behaviours count, how many tokens they earn, and how the system will be phased out. Used with children and in inpatient or residential care. Evidence: B.

**INT-03d Extinction:** Stop providing whatever reward keeps a behaviour going (e.g., planned ignoring of attention-seeking tantrums). ⚠ Prepare caregivers for the **extinction burst**, when the behaviour briefly gets worse before improving. Never ignore dangerous behaviour. Evidence: B.

**INT-03e Biofeedback:** Live readouts of body signals (heart rate, breathing, muscle tension, skin conductance) help the client learn to regulate them. Evidence: B (anxiety, headache).

**INT-03f Modelling / role play:** The client observes a calm, effective response and then practises it (e.g., rehearsing how to respond calmly when a feared situation arises). Evidence: B.

**INT-03g Aversion therapy:** ⚠ **RESTRICTED.** Pairs an unwanted behaviour with an unpleasant experience. Electric-shock methods are ethically obsolete, and drug-based aversion (e.g., disulfiram for alcohol) belongs to medical practice only. Prefer covert sensitisation (done in imagination) or evidence-based alternatives such as motivational interviewing, CBT and contingency management. Evidence: C.

**Comparison**
| | Systematic desensitisation | Exposure | Aversion |
|---|---|---|---|
| Used for | Phobias, anxiety | Phobias, anxiety, OCD | Addictions, habits |
| How it works | Counter-conditioning | Extinction / inhibitory learning | Conditioned avoidance |

- **Strengths:** targets present-day problems; easy to explain; works with children, adults and people with disabilities.
- **Limitations:** addresses behaviour more than meaning, and tends to overlook thoughts and biology — the gap CBT was developed to fill.

### INT-04 Cognitive Behavioural Therapy (CBT)
- **Model:** a situation triggers thoughts, which shape feelings, body sensations and actions. *Example:* A friend hasn't replied to a message for a day. Thought "She's just busy" → calm → carry on with the day. Thought "She's upset with me" → anxious → keep checking the phone and send several more messages.
- **Evidence:** A (depression, anxiety disorders, OCD, PTSD, insomnia, eating disorders; an add-on for psychosis and substance use).
- **Level:** L2. **Format:** short-term (usually 8–20 sessions), structured, goal-focused, centred on the present, collaborative and educational — the client gradually becomes their own therapist.

**Levels of thinking (Beck)**
1. Deliberate, reasoned thought
2. **Automatic thoughts** — quick, habitual, rarely questioned, often negative
3. **Core beliefs / schemas** — deep assumptions formed early in life (e.g., "I'm not good enough")

**ABC model (Ellis):** Activating event → Belief → Consequences (feelings and actions).
*Example:* A manager replies to a report with a two-word email (A) → "She thinks my work is poor; I'll never be good at this job" (B) → anxious and low, avoids speaking in the next meeting (C).

**Common thinking traps (psycho-education list; after Beck and Burns)**
| Trap | What it looks like |
|---|---|
| All-or-nothing thinking | Only two options — perfect or a complete failure |
| Overgeneralising | One bad event becomes "this always happens" |
| Mental filter | Fixing on one negative detail and missing the rest |
| Disqualifying the positive | Brushing off good things as flukes |
| Jumping to conclusions | *Mind-reading* (assuming others think badly of you) and *fortune-telling* (predicting things will go wrong) |
| Magnifying / minimising | Blowing up the bad, shrinking the good |
| Emotional reasoning | Treating a feeling as proof ("I feel useless, so I must be") |
| "Should" rules | Rigid demands on yourself or others that lead to guilt or resentment |
| Labelling | "I'm an idiot" instead of "I made an error" |
| Personalising / blaming | Taking all the responsibility yourself — or putting all of it on others |

**Three stages of change (after Meichenbaum):**
1. Noticing one's own thoughts, feelings and reactions.
2. Beginning a different inner dialogue.
3. Building and using new coping skills in daily life.

**Core techniques**
| Technique | How it works |
|---|---|
| Thought record | Situation · Emotion and intensity (0–100%) · Automatic thought · Evidence supporting it · Evidence against it · Balanced alternative · Re-rate the emotion |
| Behavioural experiment | Test a prediction in real life and compare the result with what was expected |
| Examining the evidence | The client makes the case for the thought; thin evidence shows up the distortion |
| Cognitive rehearsal | Picture a difficult situation and practise more helpful thoughts in advance |
| Guided discovery (Socratic) | See below |
| Journaling | A daily record of situations, thoughts, feelings and actions, reviewed together |
| Behavioural activation | Planning meaningful and enjoyable activities (for depression) |
| Positive reinforcement | Rewarding helpful behaviour |
| Modelling / role play | Practising new responses |
| Homework | Practice between sessions — set every time and always reviewed |

**Socratic questioning** (six question types from Paul & Elder's critical-thinking framework; sample questions written for YourCounselor AI)
| Type | Sample questions |
|---|---|
| Clarifying | "When you say 'useless', what exactly do you mean?" "How does this connect to what happened on Monday?" |
| Examining assumptions | "What are you taking for granted here?" "How might we find out if that's true?" |
| Reasons and evidence | "What makes you sure of that?" "Can you think of a specific time?" "Would that evidence convince someone else?" |
| Other viewpoints | "How else could this be seen?" "If a close friend said this about themselves, what would you tell them?" |
| Consequences | "Suppose that were true — what would follow?" "What does holding on to this belief cost you?" |
| Questioning the question | "What do you think I'm trying to get at with that question?" |

- **Sequence:** ask → listen closely (to words and context) → **summarise** at intervals → **synthesise** with a question that invites a new conclusion → agree a **plan** together (SMART goals).
- **Therapist stance:** genuinely curious and not-knowing. Balance open exploration that doesn't push toward a fixed answer (Padesky) with gentle direction toward a more balanced view the therapist has in mind (Beck).
- **Disputing vs guided discovery — illustrative example (fictional):** "Meera" believes she is a bad mother because she missed her son's school performance for a work deadline.
  - *Disputing* collects counter-evidence — she helps with homework every evening and never misses his check-ups — and brings some short-lived relief.
  - *Guided discovery* asks what "a good mother" means to her, where that standard came from (her own mother gave up her career), what her son actually said afterwards, and what she would like to do differently. Meera arrives at her own plan (telling her manager about key school dates, a weekly outing alone with her son) and a new belief: "I'm a caring mother who sometimes has to juggle." Because the conclusion is hers, it tends to last longer.
- **Benefits:** reduced distress, a habit of questioning one's own thinking, insights that stick, independence, lower relapse.
- **Limitations:** takes time; can feel challenging, so keep the tone warm.

**REBT (Ellis):** A (event) → B (beliefs, rational or irrational) → C (healthy or unhealthy emotional response) → **D** (dispute irrational beliefs: demands, "awfulising", "I can't bear it", self-condemnation) → **E** (effective new outlook).

**Where CBT is applied:**
- *Education:* study habits, exam nerves, confidence in public speaking, social skills.
- *Clinical:* depression, anxiety, OCD, substance use, personality disorders, taking medication as prescribed, add-on for psychosis.
- *Everyday life:* anger, social anxiety, self-esteem, daily stress.

**Limitations and contraindications:**
- Needs the client's active involvement.
- Requires adaptation for significant cognitive impairment or very young children.
- Exposure work can temporarily increase anxiety.
- Not an instant fix.

### INT-05 Gestalt empty-chair technique
- **Aim:** help the client say what has gone unsaid — to someone absent, deceased or unsafe to confront, or to a part of themselves. **Evidence:** B (within emotion-focused therapy for unresolved grief and interpersonal hurt). **Level:** L2.
- **Setup:** An empty chair is placed facing the client, who imagines the other person seated there and speaks to them directly. The therapist encourages, stays closely attuned and helps the client work through strong feelings. Variations include moving to the other chair to reply as that person, and group enactments.
- **Uses:** bereavement, relationship endings, conflict (practising before a real conversation), old hurts and trauma (only after stabilisation), preparing for difficult meetings.
- **Imagery version (IH):** after the INT-07 relaxation induction, the client pictures the person and speaks to them in imagination. The therapist helps the client move toward completion — saying what matters, letting go, forgiveness *only if the client chooses it*, a goodbye, and a closing self-statement. Several sessions are usually needed.
- **Contraindications ⚠:**
  - Active psychosis, marked dissociation, raw unprocessed trauma, or poor emotional regulation.
  - **Never set it as unsupervised homework** for trauma or abuse themes.
  - Clients who cannot visualise can simply speak without imagery.

### INT-06 Narrative therapy
- **Origin:** Michael White and David Epston (1980s). **Evidence:** B–C. **Level:** L1–L2.
- **Principles:** respectful (the client is not broken), non-blaming, and the **client is the authority on their own life**.
- **Central idea — externalising:** the person is not the problem; *the problem is the problem*. *Example:* instead of "I am an anxious person", the client describes how "the Worry" tries to take over their mornings.
- **Methods:**
  1. The client tells their story in their own words, making meaning and shaping identity.
  2. **Unpacking:** break a large, overwhelming problem into smaller, manageable pieces.
  3. The therapist suggests a *title* for the story and the client tells it under that heading.
  4. **Story completion:** the therapist starts telling the client's story from what is already known and the client continues it — helpful when the client is hesitant or holding back.
  5. Look for **unique outcomes** — times the problem did not win — and build a preferred story from them.
- **Advantages:** engaging; draws on imagination and expression; can lift mood and self-image. Particularly suited to children (imagination, vocabulary, communication).
- **Limitations:** depends on the therapist's narrative skill; clients may wander or over-elaborate; creative formats don't suit everyone.

### INT-07 Guided imagery & relaxation — "Resource & Release" protocols (IH)
- **Evidence:**
  - Relaxation and guided imagery for stress and anxiety: B.
  - The specific theme structure and scripts below: **IH** (YourCounselor AI in-house; not independently validated). The containment exercise draws on the widely used "container" stabilisation technique from trauma-focused therapy.
- **Level:** L2 (L1 may run Protocol A under supervision).
- **Age:** roughly 13+; shorten and simplify for younger clients.
- ⚠ **Contraindications:** psychosis or thought disorder, dissociative disorders, severe PTSD not yet stabilised, epilepsy where relaxation can trigger seizures, and anyone who becomes distressed with eyes closed. Stop if distress rises. Have a grounding exercise ready (e.g., naming five things you see, four you can touch, three you hear, two you smell, one you taste).

**Preparation (homework before the session):**
- Choose ONE theme from the list below that fits the case formulation.
- Ask the client to write down memories linked to that theme, from childhood to now, as a numbered list with enough detail to recall each one. Writing is itself a helpful, expressive exercise.
- Read the list together before starting.

**Theme list (grouped):**
- *Identity:* Who am I?
- *Resource themes:* moments of joy · pride · achievement · courage or taking the lead · being appreciated · laughter · calm and peace · gratitude · feeling inspired · feeling whole
- *Hurt themes:* being insulted, mocked or humiliated · being betrayed, deceived or cheated · being used or objectified, including sexually · being left out or rejected ("nobody likes me") · being misunderstood · feeling unsafe or trapped
- *Self-judgement themes:* guilt · shame · embarrassment · regret over hurtful jokes or pranks · failure · feeling small, useless or incompetent · self-doubt · feeling irresponsible · feeling lost or demoralised · insecurity
- *Difficult-emotion themes:* anger · resentment or grudges · hatred · thoughts of revenge · jealousy (feeling it or being its target) · frustration · sadness · depression · anxiety · helplessness · feeling out of control · urges the client feels ashamed of · aggression or violence witnessed or done · breathlessness or panic

**Shared induction (both protocols):**
1. *Setting:* quiet room, phones off, lights low or curtains drawn; loose clothing, heavy jewellery removed. The client lies down, or sits up if they tend to fall asleep.
2. *Breathing:* eyes closed; three slow breaths — in through the nose, a long unhurried breath out.
3. *Body scan:* guide attention slowly from the top of the head downward — forehead, eyes, jaw, tongue, neck, shoulders, arms, hands, chest, stomach, back, hips, legs, knees, calves, ankles, feet — inviting each area to soften and grow heavy. Use brief images in your own words (e.g., "your shoulders settling like sand at the bottom of still water"). Rest in silence for a few moments at the end.

**Protocol A — Resource recall (positive themes, e.g., "moments of pride"):**
1. Gently name the theme.
2. Invite the client to bring up their first three to five memories **one by one**, allowing about 30–60 seconds of silence for each so the image can become vivid.
3. Invite the remaining memories on the list to come up together, then "any other moments like this that come to mind now." Allow at least a minute.
4. Ask the client to notice where in the body the good feeling sits and to stay with it for about 30 seconds.
5. Frame the memories as inner resources: "These moments belong to you. You can return to them whenever things feel heavy." Pause about 20 seconds.
6. Invite gratitude toward whoever or whatever the client wishes — people, nature, or a higher power if that is meaningful to them. Pause about 30 seconds.
7. Offer a **self-statement** agreed with the client beforehand, repeated slowly two or three times. *Example:* "I carry what is good in me wherever I go." Pause 20–30 seconds.
8. *Return:* a few deeper breaths, gentle movement of fingers and toes, feet felt on the floor, eyes opening in the client's own time. **Allow 1–2 minutes; never rush.**
9. Talk through the experience.

**Protocol B — Contain & release (difficult themes, e.g., guilt):**
1. Remind the client of the theme. Difficult memories are **only touched briefly (about 5–7 seconds each)** — never relived at length.
2. **Container imagery:** ask the client to picture a container strong enough to hold anything — one they design themselves (a steel safe, a sealed trunk, a vault), with a lock only they control. "Briefly notice memory 1… now place it inside, close the lid and lock it." Pause 10–20 seconds.
3. Repeat for the first few memories one at a time, then the rest together, then "anything else connected to this that comes up now."
4. Ask the client to put the container somewhere far away and secure that they choose, knowing it can be opened later, in therapy, only when they decide. Pause about 10 seconds.
5. "Notice any sense of space or lightness now." Pause 10–20 seconds.
6. **Self-compassion:** "Every person makes mistakes and carries hurts. When you feel ready — and only if it feels right — you might offer some kindness to yourself, and to others where appropriate." Pause 20–30 seconds. ⚠ **Never encourage or imply forgiveness of an abuser.**
7. **Self-statement**, repeated slowly three times. *Example:* "I can set this down. I am allowed to feel lighter." Pause about 20 seconds.
8. Return and debrief as in Protocol A.

**How to explain it to clients** ⚠: the exercise helps them **put painful memories to one side and loosen their emotional hold**. It does not erase anything. Material that still needs work is taken up in later sessions, for example with CBT or trauma-focused therapy.

**If the client falls asleep:** common in early sessions and a sign of relaxation — reassure them. If it keeps happening, switch to a seated position. Never criticise.

**Benefits:** lower stress and anxiety, better mood and motivation, mental rehearsal of performance, relief from pain and tension.

**Limitations:**
- Some people find imagery difficult.
- Can raise anxiety in some clients.
- May not fit every person's cultural or personal preferences.
- Takes time.
- Needs adapting for young children.

### INT-08 Dream work (exploratory)
- **Background:** Freud saw dreams as disguised wishes — now of mainly historical interest. Current views treat dreaming as part of how the mind processes experience and emotion. **Evidence:** C for Hill's cognitive-experiential dream model; D for fixed symbol meanings. **Level:** L2.

**Dream diary — client guidance:**
- Keep a notebook and pen beside the bed and date each entry.
- Write as soon as you wake, before getting up (keep your eyes closed for a moment first to hold the dream).
- Note feelings, people, animals, places, colours, journeys or vehicles, what happened (if anything), and the first thought, word or tune on waking.
- Sketch images if that helps.
- Don't add a storyline or start interpreting while you write.
- Give each dream a short title.

**Questions to explore in session:**
- Who was there — or was I alone?
- What did I feel? When have I felt that recently while awake?
- What does this place, person or object mean *to me*?
- Where have I come across it lately?
- What keeps coming back across different dreams?

**Guidance:**
- The client's own associations matter far more than any dream dictionary (use those only as a last resort).
- Common themes are *starting points, not answers*:
  - Death → something ending or changing
  - Driving or vehicles → how in control of life's direction the person feels
  - Flying → freedom or mastery
  - Falling → losing control, or letting go
  - Being chased → something being avoided
  - Being lost → uncertainty about direction
  - Sitting an exam unprepared → worry about being judged or measured
  - Being naked in public → feeling exposed
  - Losing teeth → anxiety or feeling powerless
  - Romantic or sexual dreams → closeness, or qualities the dreamer wants more of
- Dreams do **not** foretell the future.
- The client has the final word on meaning.
- Repeated distressing nightmares need clinical treatment — e.g., **Imagery Rehearsal Therapy** (Evidence A for nightmares) — and screening for PTSD.
- Advise clients never to act against real people on the basis of a dream.

### INT-09 Music-based interventions
- **Definition:** *Music therapy* proper is the clinical use of music by a credentialed music therapist to reach individual goals. Counsellors can use music-based activities within their own competence. **Evidence:** B (depression, anxiety, dementia, autism, pain, substance use).
- **Groups who may benefit:** trauma survivors, autistic people, people with dementia, people in custody, people with physical illness or pain, people with mental-health conditions or substance-use problems, and children and adolescents (behaviour, mood, ADHD).
- **Process:**
  1. Assess mood, physical health, sensory-motor, social, communication and thinking skills, musical history and tastes, and **trauma history and triggers**.
  2. Agree goals.
  3. Activities: listening to music the client chooses, singing, playing instruments, writing songs, moving to music, talking about lyrics.
  4. Review progress.
- **Benefits:**
  - Emotional: release, feeling less alone, better mood.
  - Physical: lower heart rate, blood pressure and muscle tension; better sleep; distraction from pain; movement gains (e.g., in Parkinson's disease).
  - Cognitive: sense of control; coping.
  - Social: connection and communication.
  - Spiritual: exploring meaning.
- ⚠ Music can bring back traumatic memories — check for triggers first.

### INT-10 Projective elicitation techniques (exploration, not diagnosis)
**INT-10a Word association**
- The therapist says a series of words; the client says or writes the first word, phrase or sentence that comes to mind (IH format: written, about 30–50 seconds per word).
- Tailor the list to the case — e.g., the client's own name, mother, father, brother/sister, partner, children, in-laws, friends, job, boss, money, success, failure, faith, home — plus words linked to the presenting problem.
- Note what is said, hesitations, emotional reactions and unusual answers.
- Use: bringing to the surface attitudes and feelings the client doesn't state directly. Evidence: C.
- Limitations: depends on vocabulary and openness; clients can censor their answers.

**INT-10b Sentence completion (custom)**
- Prepare case-specific sentence starters beforehand, e.g., "At home I feel…", "The thing that annoys me most is…", "I am most afraid that…", "I wish my mother would…", "When people criticise me…".
- Look for recurring themes of conflict, attitudes and unmet needs.
- For a scored screening, use a standardised form (Rotter ISB).
- Evidence: B (standardised), C (custom).

**INT-10c Story completion:** see INT-06 (4).

### INT-11 Homework & journaling library
- Theme memory lists (INT-07)
- CBT thought records
- Activity scheduling
- Dream diary
- Gratitude log (three things each day)
- Scheduled "worry time"
- Sleep diary
- ABC behaviour records
- Exposure practice logs

**Rule:** explain why each task matters, start small, and always review it at the next session.

### INT-12 Roadmap — modalities to add in v2
DBT skills · ACT · Exposure and response prevention protocol · Motivational interviewing · Mindfulness-based CBT · Schema therapy · Trauma-focused CBT / EMDR overview · Couples and family therapy · Group therapy · Grief counselling · Solution-focused brief therapy · Crisis intervention · Condition chapters (see PART 9).

---

## PART 7 — COUNSELLING, CAREER & WORKPLACE (CNS)

### CNS-01 Counselling vs clinical psychology
| | Clinical | Counselling |
|---|---|---|
| Origins | Medical model; study of psychopathology | Vocational guidance movement |
| Focus | Identifying and treating disabling problems | Strengths, decisions and adjustment |
| Time focus | Causes and the past | The present and the future |
| Aim of change | Change in personality and behaviour | Problem-solving using existing strengths |
| Typical instruments | MMPI, WAIS, Rorschach, TAT, Bender | Strong, SDS, Kuder, 16PF, CPI, EPPS, WAIS |
| How results are used | Clinician decides (gatekeeper role) | **Shared and discussed with the client** (facilitator role) |

### CNS-02 Career counselling workflow
1. Intake: goals, education, work history, practical constraints (money, family, location).
2. Interests: Strong Interest Inventory or SDS (RIASEC code).
3. Abilities: aptitude battery or IQ test; achievement.
4. Personality and work values: 16PF or NEO; MIQ or a work-values measure.
5. Career readiness and beliefs (if the client is undecided).
6. Integration: match ability, interest and personality against **opportunity** (job market, access).
7. Explore options (informational interviews, job shadowing) and agree an action plan.
8. Follow up.

### CNS-03 Testing in the workplace
- **Selection:**
  - Sequence: job analysis → job description → recruitment → assessment → selection.
  - Structured interviews are roughly twice as reliable and valid as unstructured ones, which are distorted by first impressions, confirmation bias, the halo effect and stereotypes.
  - Standardised tests generally predict better than interviews and references.
  - Specific-aptitude tests (e.g., clerical speed, mechanical reasoning) and **work samples** (e.g., in-tray exercises for managers) predict well.
- **Integrity tests:** overt tests (attitudes to theft, admissions) and personality-based tests (conscientiousness, reliability). Reasonably valid at group level but open to faking. ⚠ **Polygraph** results carry high false-positive rates and are legally restricted in many countries.
- **Performance appraisal:**
  - *Output measures:* countable, but units and fairness are hard to get right.
  - *Personnel records:* absence, lateness — low reliability.
  - *Judgement-based methods:* **ranking** (straight ranking; forced distribution; paired comparison, needing N(N−1)/2 pairs) or **rating** (graphic scales; **BARS** — behaviourally anchored; **BOS** — behaviour frequency). Watch for halo, leniency, severity and central-tendency errors.
- **Fair selection:** check for adverse impact (the US "four-fifths rule" — if one group's selection rate is below 80% of the highest group's rate, possible discrimination is flagged). Validate procedures, and avoid group-specific cut-offs where the law forbids them.
- **Organisational measures:** climate, job satisfaction (e.g., JDI, MSQ), burnout (Maslach Burnout Inventory), person–environment fit; also human-factors and consumer research.

---

## PART 8 — SPECIAL POPULATIONS, FAIRNESS & BIAS (POP)

### POP-01 Assessing people with disabilities
**Principles (drawn from IDEA/ADA practice and consistent with the RPwD Act 2016):**
- Non-discriminatory assessment in the person's own language or communication mode.
- Instruments validated for that purpose and group.
- Trained examiners.
- Assess every area connected with the suspected disability (health, vision, hearing, social-emotional, cognitive, academic, communication, motor) — not just IQ.
- Decisions made by a multidisciplinary team, never on one test.
- Least restrictive setting; an individualised education plan (IEP) with measurable goals.

**Reasonable accommodations:** large print, Braille, audio or spoken presentation, a reader or scribe, spoken answers, a separate quiet room, extra time, rest breaks, written instructions, assistive devices.

⚠ **Changing the format is usually acceptable; changing time limits can change what scores mean.** For example, SAT scores obtained with extra time over-predicted college grades for students with learning disabilities. Record every accommodation.

**Terms:**
- **Non-language test:** no language at all (instructions by gesture).
- **Non-reading test:** spoken instructions only.
- **Motor-reduced test:** requires only pointing.
- **Developmental schedule:** structured observation of milestones.
- **Behaviour scale:** adaptive behaviour rated by an informant.

### POP-02 Test bias vs test fairness
- **Test bias** (a technical matter): the test works **differently** for a subgroup — its scores mean something different or predict differently.
  - Evidence of bias includes: item content that is unfamiliar or offensive to a group; differential item functioning (DIF); different regression slopes or intercepts when predicting outcomes; different factor structures.
- **A difference in group averages does not by itself prove bias.** Well-constructed tests (e.g., Leiter-3, PPVT-5, K-ABC) screen items for DIF with expert panels.
- **Test fairness** (a question of values): whether using the test is just, given its social consequences and the selection approach chosen. Keep the two ideas separate in discussion.
- **Culture-fair is not culture-free.** Cultures differ in what testing means, and in attitudes to speed, abstract tasks and competition.
- Before testing a client from a minority or rural background:
  1. Establish their dominant language.
  2. Check how familiar they are with taking tests.
  3. Check whether the norm group includes people like them.
  4. Consider non-verbal or dynamic assessment.
  5. State interpretive cautions explicitly.

---

## PART 9 — GAPS & NEXT BUILD (roadmap)
To be written for v2:
1. **Condition chapters**, each on a fixed template: clinical picture · ICD-11 criteria (via the WHO ICD API) · screening tools · differentials · evidence-based treatments (graded) · session outline · cultural notes · pitfalls and when to refer · client handouts. Conditions: depression, bipolar disorder, anxiety/panic/phobias, OCD, PTSD, psychosis, personality disorders, eating disorders, substance and behavioural addictions, ADHD, autism, specific learning disorders, dementia, sleep disorders, somatic presentations, sexual concerns.
2. Full DBT, ACT, MI, ERP, trauma-focused, family and group protocols.
3. Crisis manual (expanding ASM-06): abuse disclosure, panic in session, psychiatric emergency pathway.
4. Child and adolescent assessment protocol; older-adult protocol.
5. Clinician wellbeing: supervision, burnout (MBI), vicarious trauma, practice management.
6. Psychopharmacology quick reference (for liaison, not prescribing).
7. Directory of Indian norms and a licensing register covering every instrument.

---

## APPENDIX A — DATA MODEL FOR SOFTWARE (DATA)

### DATA-01 Core entities
| Entity | Key fields |
|---|---|
| **Client** | client_id, name, dob, gender, contact, emergency_contact, language, created_at |
| **Consent** | consent_id, client_id, type (assessment/treatment/recording/data-sharing/minor-guardian), version, granted_at, revoked_at, signature_ref |
| **Clinician** | clinician_id, name, qualification, registration_no (e.g., RCI), competence_level (L1/L2/L3), supervisor_id |
| **Intake** | intake_id, client_id, section_json (per ASM-01), severity_0_10, risk_flags[] |
| **Session** | session_id, client_id, clinician_id, datetime, duration, modality (in-person/tele), note_format (SOAP/DAP), note_json, risk_review (bool), homework_assigned[], homework_reviewed[] |
| **InstrumentDefinition** | instrument_id (e.g., INS-DASS21), name, version, construct, licence (PD/FREE/PUB/RQ/IH), licence_notice, min_level, recall_period, response_scale[], items[], scoring_rules, bands[], risk_items[], citation |
| **Administration** | admin_id, instrument_id, client_id, clinician_id, date, mode (paper/digital/interview), accommodations[], validity_notes |
| **ItemResponse** | admin_id, item_no, value, timestamp |
| **Score** | admin_id, scale, raw, transformed (e.g., ×2), band, ci_low, ci_high, auto_calculated (bool), clinician_verified (bool) |
| **RiskFlag** | flag_id, client_id, source (intake/MSE/PHQ9-item9/session), level (low/moderate/high), action_taken, safety_plan_id, resolved_at |
| **SafetyPlan** | plan_id, client_id, warning_signs[], coping[], social_contacts[], professional_contacts[], means_safety, reasons_for_living, updated_at |
| **Formulation** | client_id, presenting, predisposing, precipitating, perpetuating, protective, provisional_dx[], differentials[] |
| **TreatmentPlan** | plan_id, client_id, goals[] (SMART fields: specific, measure, target, deadline), interventions[] (INT IDs), sessions_planned, review_dates[] |
| **TechniqueDefinition** | technique_id (INT-…), name, evidence_grade, min_level, contraindications[], steps[], scripts[], homework_templates[] |
| **AuditLog** | who, what, when, before/after (every score edit and every record access) |

### DATA-02 Example instrument definition (DASS-21)
```json
{
  "instrument_id": "INS-DASS21",
  "name": "Depression Anxiety Stress Scales - 21",
  "licence": "PD",
  "licence_notice": "Lovibond & Lovibond (1995). Items reproduced unaltered.",
  "min_level": "L1",
  "recall_period": "past week",
  "response_scale": [
    {"value": 0, "label": "Did not apply to me at all"},
    {"value": 1, "label": "Applied to me to some degree, or some of the time"},
    {"value": 2, "label": "Applied to me to a considerable degree, or a good part of time"},
    {"value": 3, "label": "Applied to me very much, or most of the time"}
  ],
  "scales": {
    "depression": {"items": [3,5,10,13,16,17,21], "multiplier": 2,
      "bands": [[0,9,"Normal"],[10,13,"Mild"],[14,20,"Moderate"],[21,27,"Severe"],[28,42,"Extremely severe"]]},
    "anxiety": {"items": [2,4,7,9,15,19,20], "multiplier": 2,
      "bands": [[0,7,"Normal"],[8,9,"Mild"],[10,14,"Moderate"],[15,19,"Severe"],[20,42,"Extremely severe"]]},
    "stress": {"items": [1,6,8,11,12,14,18], "multiplier": 2,
      "bands": [[0,14,"Normal"],[15,18,"Mild"],[19,25,"Moderate"],[26,33,"Severe"],[34,42,"Extremely severe"]]}
  },
  "alerts": [{"rule": "item(10)>=2 || item(17)>=2 || item(21)>=2", "action": "prompt_risk_review"}],
  "citation": "Lovibond & Lovibond (1995)"
}
```

### DATA-03 Product rules
1. The app scores; the clinician interprets. Only L2+ users can edit diagnosis fields.
2. Every screening result carries the label: "Screening only — not a diagnosis."
3. Show SEM / confidence bands wherever the instrument provides them.
4. Risk alerts cannot be dismissed until a clinician records the action taken.
5. Instrument definitions are version-locked; re-scoring always uses the version in force at the time of administration.
6. Consent is checked before any administration, recording or data sharing.
7. Data residency, encryption at rest and in transit, role-based access, and erasure on request (DPDP Act).
8. Display each instrument's citation and any required licence notice on its screen.

---

## APPENDIX B — GLOSSARY (selected)
- **Base rate:** the proportion of a population that actually has the condition or outcome.
- **Ceiling / floor:** the highest / lowest level a test can measure.
- **Construct:** an attribute that cannot be observed directly and is inferred from behaviour (e.g., anxiety).
- **Criterion:** the outcome against which a test is validated.
- **Differential validity:** when a test predicts differently for different groups — one form of bias.
- **Ipsative:** scores expressed relative to the same person's other scores.
- **Metacognition:** knowing about and regulating one's own thinking.
- **Nomological network:** the set of expected relationships that define a construct.
- **Norm group:** the reference sample used to interpret scores.
- **Power test / speed test:** limited by item difficulty vs limited by time.
- **Reliability:** how consistent scores are.
- **Validity:** how well evidence supports the intended interpretation of scores.
- **SEM:** the spread of an individual's scores around their true score over repeated testing.
- **SUDS:** Subjective Units of Distress, rated 0–100.
- **Schema:** a deep core belief (in CBT) or an organised pattern of action and thought (in Piaget).

---

## APPENDIX C — REFERENCES, LICENSING REGISTER & VERSION LOG

### C.1 Key references (primary literature)
- American Educational Research Association, APA & NCME (2014). *Standards for Educational and Psychological Testing.*
- Beck, A. T. (1976). *Cognitive Therapy and the Emotional Disorders.* · Burns, D. D. (1980). *Feeling Good.*
- Bordin, E. S. (1979). The generalizability of the psychoanalytic concept of the working alliance. · Horvath, A. O., & Greenberg, L. S. (1989). Working Alliance Inventory.
- Carkhuff, R. R. (1969). *Helping and Human Relations.*
- Ellis, A. (1962). *Reason and Emotion in Psychotherapy.*
- Meichenbaum, D. (1977). *Cognitive-Behavior Modification.*
- Messick, S. (1989). Validity. In *Educational Measurement* (3rd ed.).
- Paul, R., & Elder, L. (2006). *The Thinker's Guide to the Art of Socratic Questioning.* · Padesky, C. A. (1993). Socratic questioning: Changing minds or guiding discovery?
- Stanley, B., & Brown, G. K. (2012). Safety Planning Intervention. *Cognitive and Behavioral Practice*, 19, 256–264.
- Taylor, H. C., & Russell, J. T. (1939). *Journal of Applied Psychology*, 23, 565–578.
- White, M., & Epston, D. (1990). *Narrative Means to Therapeutic Ends.*
- Wolpe, J. (1958). *Psychotherapy by Reciprocal Inhibition.*
- Instrument citations: shown on each INS-14 card.
- Test publishers' current manuals for all PUB/RQ instruments named in PART 5 (names are used for identification only; no content reproduced).

### C.2 Licensing register (instruments with items in this file)
| ID | Items included | Licence | Action before commercial release |
|---|---|---|---|
| INS-HAMA | Yes (verbatim) | PD | None beyond citation |
| INS-DASS21 | Yes (verbatim) | PD/FREE | Keep items unaltered; cite |
| INS-PHQ9 | Yes (verbatim) | FREE | Show Pfizer/authors notice |
| INS-GAD7 | Yes (verbatim) | FREE | Show Pfizer/authors notice |
| INS-RSES | Yes (verbatim) | FREE (research/education) | ⚠ Obtain written confirmation for commercial use |
| INS-EIR | Yes (original) | IH | None |
| All other instruments | No | PUB/RQ/FREE as listed | License before digitising anything beyond score entry |

### C.3 Version log
| Version | Change |
|---|---|
| v2.0 | Full rewrite in original wording. New original examples, scripts and intake layout. Former INS-EQSA replaced by original INS-EIR. INT-07 rebuilt as the "Resource & Release" in-house protocol. All card IDs kept unchanged (except INS-EQSA → INS-EIR) so existing app mappings still work. Validated scale items retained verbatim under their free-use licences. |

*End of Core 1*
