# CORE 3 — Personality Difficulties & Treatment-Plan Engine
### YourCounselor AI · Clinical Practice Knowledge Base · Core 3 · v2.0 (original-text edition)

**Extends Core 1 and Core 2.** Same ID scheme, evidence grades (A/B/C/D/IH), competence levels (L1–L3) and licence codes.

**About this edition:** v2.0 is written in original wording for YourCounselor AI. The plan engine, pattern cards, goal statements and objective banks are our own. They are written to our measurability standard (TPE-02) and organised around the **ICD-11 dimensional model**, the app's primary diagnostic system. Therapies and models are described in our words and credited to their developers (Appendix G). No commercial treatment-planner statement library, diagnostic-manual criteria text or therapy-manual handout is reproduced. For official ICD-11 wording, the app pulls definitions live from the WHO ICD API.

**ID prefixes added in this Core:**
- `TPE` — treatment-plan engine
- `PD` — personality pattern cards
- `PDX` — personality-focused interventions

**Not repeated here:** CBT, REBT, SFBT, family therapy, relaxation, desensitisation, ethics and risk (see Cores 1–2; cross-referenced only).

> ⚠ **Language caution.** Personality labels — especially "sadistic" and "self-defeating/masochistic" — have been misused in legal settings, for example to excuse domestic violence or to blame victims. In any document that may reach a court, describe *behaviour*, not labels. Several patterns below are **not official ICD-11 or DSM-5-TR categories**; code them using the ICD-11 severity and trait system.


## Contents (card index — grep the ID to jump to it)
  - YourCounselor AI · Clinical Practice Knowledge Base · Core 3 · v2.0 (original-text edition)
- PART 20 — TREATMENT-PLAN ENGINE (TPE)
  - TPE-01 Plan builder: six steps (main app workflow)
  - TPE-02 Measurability check (app validator)
  - TPE-03 Standard assessment block (added to every personality-focused plan)
  - TPE-04 Statement library structure
  - TPE-05 Recovery-oriented overlay (optional for any plan)
- PART 21 — PERSONALITY FRAMEWORK
  - PD-00 Treatment principles
  - PD-01 Evidence status
  - PD-02 Polarity lens for formulation (after Millon)
  - PD-03 Dimensional systems
  - PD-04 Trait-blend modifiers (replaces v1 subtype map)
- PART 22 — PATTERN CARDS (library for the plan builder)
  - Cluster A-type patterns (odd / eccentric)
  - PD-PAR Paranoid pattern
  - PD-PAR-F Modifier: paranoid pattern with grandiosity
  - PD-PAR-M Modifier: paranoid pattern with hostility and vengefulness
  - PD-SZD Schizoid pattern
  - PD-STY Schizotypal presentation
  - Cluster B-type patterns (dramatic / erratic)
  - PD-ASP Antisocial / dissocial pattern
  - PD-ASP-M Modifier: antisocial pattern with cruelty and deep mistrust
  - PD-AGG Aggressive / sadistic pattern (not an official category)
  - PD-BPD Borderline pattern
  - PD-BPD-P Modifier: borderline pattern with sullen defiance
  - PD-BPD-SD Modifier: borderline pattern with self-directed anger and guilt
  - PD-HIS Histrionic pattern
  - PD-HIS-D Modifier: histrionic pattern with exploitative features
  - PD-NAR Narcissistic pattern
  - PD-NAR-C Modifier: narcissistic pattern with fragile self-worth
  - PD-NAR-U Modifier: narcissistic pattern with exploitative, rule-breaking features
  - PD-PA Negativistic / passive-aggressive pattern (not an official category)
  - Cluster C-type patterns (anxious / fearful)
  - PD-AVD Avoidant pattern
  - PD-AVD-C Modifier: avoidant pattern with marked ambivalence
  - PD-AVD-H Modifier: avoidant pattern with suspiciousness
  - PD-DEP Dependent pattern
  - PD-DEP-S Modifier: dependent pattern with low mood and self-effacement
  - PD-OCP Obsessive-compulsive (anankastic) pattern
  - PD-OCP-B Modifier: obsessive-compulsive pattern with indecision and ambivalence
  - Patterns outside current official systems
  - PD-DPS Depressive personality pattern (not an official category; ego-syntonic)
  - PD-INT Self-defeating / intropunitive pattern (not an official category)
- PART 23 — PERSONALITY-FOCUSED INTERVENTION LIBRARY (PDX)
  - PDX-01 Dialectical Behaviour Therapy (DBT; Linehan)
  - PDX-02 Schema Therapy (Young)
  - PDX-03 Mentalization-Based Treatment (MBT; Bateman & Fonagy)
  - PDX-04 Transference-Focused Psychotherapy (TFP; Kernberg and colleagues)
  - PDX-05 Acceptance and Commitment Therapy (ACT; Hayes, Strosahl & Wilson)
  - PDX-06 Motivational Interviewing (MI; Miller & Rollnick) for ego-syntonic patterns
  - PDX-07 Emotionally Focused Couple Therapy (EFT; Johnson)
  - PDX-08 Self-psychology interventions (Kohut)
  - PDX-09 Pre-therapy contact reflections (Prouty)
  - PDX-10 Managing the therapy frame in high-risk presentations
  - PDX-11 Clinical hypnosis and self-hypnosis (adjunct)
  - PDX-12 Adlerian interventions
  - PDX-13 Reusable skill objectives across patterns
  - PDX-14 Self-help reading (examples; check local availability)
- APPENDIX F — DATA MODEL ADDITIONS (extends Core 1 DATA-01 and Core 2 Appendix D)
- APPENDIX G — REFERENCES & VERSION LOG
  - G.1 Key references (primary literature and official sources)
  - G.2 Version log

---

## PART 20 — TREATMENT-PLAN ENGINE (TPE)

### TPE-01 Plan builder: six steps (main app workflow)
| Step | Output | Rule |
|---|---|---|
| 1 Choose problems | One primary problem, plus one or two secondary | Keep the plan focused; park other issues for later |
| 2 Describe the problem | How the problem shows up *for this client*, in behavioural terms | Link to the ICD-11 formulation (severity + trait qualifiers); DSM-5-TR mapping optional |
| 3 Set long-term goals | At least one broad, positive goal | Written in the client's language; doesn't need to be measurable |
| 4 Write objectives | Short-term objectives | **Must pass the measurability check** (TPE-02) |
| 5 Link interventions | At least one intervention per objective | Show the evidence grade; add or change interventions if an objective isn't being met |
| 6 Record diagnosis | Code(s) | Based on the full assessment (Core 1 ASM-07) |

- Every plan must be **individual**. Library statements are starting points to adapt, never a ready-made plan.
- Each plan also records strengths, current stressors, support network, family context and culture.

### TPE-02 Measurability check (app validator)
An objective passes only if it contains: **an action verb + an observable behaviour + a number or frequency + a setting + a time frame.**
- ❌ "Feel better about myself."
- ✅ "Write down **3** self-critical thoughts and a balanced reply to each, **twice a week for 4 weeks**."
- ✅ "Practise slow breathing for **5 minutes** before **every** team meeting for **6 weeks**."

**App:** every objective carries structured fields `{target_count, unit, setting, deadline}`; the builder prompts the clinician whenever one is missing.

### TPE-03 Standard assessment block (added to every personality-focused plan)
| Item | Options |
|---|---|
| **Client's view of the problem** | Distressed by the pattern and wants change (ego-dystonic) · Mixed feelings · Sees no problem (ego-syntonic). When syntonic, begin with motivational work (PDX-06) |
| **Co-occurring conditions** | Screen for depression, anxiety, substance use, PTSD/complex PTSD, bipolar disorder, ADHD — and **suicide risk**, which rises when depression is present → Core 1 ASM-06 |
| **Age, gender and culture** | Factors that explain or recast the "problem" behaviour (Core 2 CHD-20) |
| **Severity and level of care** | ICD-11 severity (personality difficulty / mild / moderate / severe) plus functional impact on social, family and work life. **Re-rate at every review** |
| **Measures** | Clinician rating of ICD-11 severity and traits; PID-5 or PID5BF+M (maps to ICD-11 domains); Standardised Assessment of Severity of Personality Disorder (SASPD); Level of Personality Functioning Scale; schema questionnaires; structured interviews (e.g., SCID-5-PD, IPDE); broad inventories (MMPI-3, MCMI-IV) where licensed and indicated (Core 1 INS) |

### TPE-04 Statement library structure
Each pattern card (PART 22) provides:
- `presentation[]` — plain-language description of how the pattern commonly appears
- `long_term_goals[]`
- `objectives[] {text, target_count, unit, setting, deadline_weeks, linked_interventions[]}`
- `interventions[] {text, modality, evidence_flag, homework_ref}`
- `icd11 {severity_prompt, trait_domains[], borderline_pattern}`, `icd10cm_code`

Objective banks are **starting templates with suggested numbers**. The clinician picks one, edits it to fit the client, and adjusts the numbers.

**Core objectives shared by all personality plans (reuse; don't duplicate):**
1. Attend at least 80% of scheduled sessions over the first 8 weeks and tell the therapist about any concern with the therapy relationship as it arises.
2. Complete the TPE-03 assessment measures within the first 3 sessions.
3. Agree 2–3 personal treatment goals, in the client's own words, by session 4.
4. Follow the agreed session frame (time, contact, safety terms) with no more than one breach per month.
5. If referred for medication review, attend the appointment within 4 weeks and report on effects at each session.
6. Where group therapy is recommended, attend an introductory group session within 6 weeks.
7. With consent, family or partner attend at least 1 session to describe how the pattern affects them and agree one change in how they respond.
8. List at least 3 recurring difficulties from past close relationships by week 6.
9. Name at least 2 beliefs or habits that help relationships last, and practise one of them weekly for 4 weeks.
10. Identify at least 2 links between early experiences (e.g., neglect, harsh criticism, abuse, parental example) and current patterns by the mid-point review.
11. In the final 3 sessions, talk through feelings about ending and agree a written maintenance plan.

### TPE-05 Recovery-oriented overlay (optional for any plan)
Based on the ten guiding principles of recovery published by the US Substance Abuse and Mental Health Services Administration (SAMHSA), adapted for India.

**Default long-term goal:** "Build a life that feels meaningful to me, in the community I choose, while working towards what I'm capable of."

| # | Principle | Example objective | Clinician action |
|---|---|---|---|
| 1 | Hope | Client names at least 1 realistic hope for the next year by week 4 | Share recovery examples; notice and name progress |
| 2 | Person-driven | Client describes their preferred path of recovery in writing by week 3 | Explore options; share preferences with family if the client consents |
| 3 | Many pathways | Client identifies 2 supports outside therapy (e.g., faith, sport, peer group) | Respect varied routes to recovery |
| 4 | Holistic | Client sets 1 goal each for physical, emotional and social wellbeing | Integrate these into the plan |
| 5 | Peer support | Client attends a peer or self-help group at least twice in 2 months | Refer (India: peer-support groups, NGOs, online communities) |
| 6 | Relationships and networks | Client strengthens contact with 1 supportive person weekly | Map the support network |
| 7 | Culture | Client names cultural or religious needs relevant to care | Adapt the plan accordingly |
| 8 | Addressing trauma | Client agrees whether and when to work on past trauma | Offer trauma-informed options |
| 9 | Strengths and responsibility | Client completes a strengths inventory and a self-care plan by week 6 | Build on assets; review self-care |
| 10 | Respect | Client reports reduced self-stigma on a 0–10 scale at review | Address stigma; advocate for rights under the MHCA 2017 |

Normalise setbacks throughout: recovery is rarely a straight line.

---

## PART 21 — PERSONALITY FRAMEWORK

### PD-00 Treatment principles
1. **Treat personality difficulties rather than work around them.** They reduce quality of life and **worsen outcomes for co-occurring conditions** such as depression and substance use.
2. **Sequence the work** (a principle shared by most integrative approaches, including Millon's personality-guided therapy):
   - Build the alliance first.
   - Then aim for **early, achievable practical wins** that build hope and commitment.
   - Then address the deeper, self-maintaining patterns through cognitive, schema, interpersonal or psychodynamic work.
3. **When the client doesn't see the pattern as the problem:** anchor therapy to what *they* want — fewer arguments, a better appraisal, staying out of legal trouble — and show how each intervention serves that aim.
4. **Blends are common.** Most clients show features of more than one pattern. Build the plan from the dominant pattern, then add objectives from the relevant trait-blend modifiers (PD-04).
5. **Think dimensionally.** ICD-11 describes personality problems by severity and trait profile, which reflects the reality that people rarely fit a single category.
6. **Monitor yourself:** use supervision for strong reactions (anger, feeling manipulated, wanting to rescue). Notice when a client triggers your own patterns, e.g., needing approval or holding very high standards.

### PD-01 Evidence status
| Treatment | Target | Grade |
|---|---|---|
| **DBT** (numerous RCTs) | Borderline pattern: self-harm, suicide attempts, hospital admissions | **A** |
| **Mentalization-Based Treatment** | Borderline pattern | **A–B** |
| **Transference-Focused Psychotherapy** | Borderline pattern | **B** (mixed findings) |
| **Schema Therapy** | Borderline pattern; a large multicentre RCT supports it for avoidant, dependent, obsessive-compulsive, paranoid, histrionic and narcissistic presentations (Bamelis et al., 2014) | **B** (A for borderline in some reviews) |
| Other patterns | Best available evidence plus clinical consensus; integrative approach | **C** |
| Medication | Targets specific symptoms only (mood, impulsivity, brief psychotic symptoms); no medication treats personality disorder itself | Refer to a psychiatrist |

### PD-02 Polarity lens for formulation (after Millon)
Millon described personality styles along three dimensions:
- **Seeking pleasure ↔ avoiding pain** — some styles reverse this, finding comfort in pain or discomfort in pleasure.
- **Active ↔ passive** — shaping one's world vs adapting to it.
- **Self ↔ other** — looking to oneself or to others for reward and security.

**Therapeutic aim:** strengthen whichever side is under-developed. For example: increase capacity for enjoyment in detached presentations; reduce anticipation of pain in avoidant ones; build self-reliance in dependent ones; build attention to others in narcissistic ones; resolve the pull between self and others in negativistic ones.

### PD-03 Dimensional systems

**A. ICD-11 (6D10 Personality disorder; 6D11 trait domains) — primary system for this app**
- **Step 1 — Is there a personality problem, and how severe?**
  - *Personality difficulty* (QE50.7 — not a disorder; a noted pattern)
  - *Mild* (6D10.0) · *Moderate* (6D10.1) · *Severe* (6D10.2) personality disorder; *severity unspecified* (6D10.Z)
  - Severity is judged by how far the problems affect the person's sense of self (identity, self-worth, self-direction) and their relationships, how pervasive they are, and the emotional, thinking and behavioural signs of disturbance — plus how much distress and harm result.
- **Step 2 — Which trait domains stand out?** (code as many as are prominent)
  - 6D11.0 **Negative affectivity** — frequent, intense negative emotions; low self-esteem; mistrust
  - 6D11.1 **Detachment** — keeping distance from others and emotions
  - 6D11.2 **Dissociality** — disregard for others' rights and feelings; self-centredness; lack of empathy
  - 6D11.3 **Disinhibition** — acting on impulse; distractibility; irresponsibility; recklessness
  - 6D11.4 **Anankastia** — perfectionism; rigid control of self, others and situations
- **Step 3 — Borderline pattern specifier** (6D11.5) where appropriate.
- **App:** store the severity rating, the trait profile and (optionally) the clinician's pattern card together. Each pattern card lists its usual ICD-11 trait mapping. Retrieve official ICD-11 definitions through the WHO ICD API rather than storing them as text.

**B. DSM-5-TR Alternative Model (Section III) — optional cross-walk**
- **Criterion A — Level of Personality Functioning Scale (LPFS):** rate each area 0 (little or no impairment) to 4 (extreme):
  - *Self:* identity, self-direction
  - *Relationships:* empathy, intimacy
- **Criterion B — five trait domains with 25 facets:** negative affectivity, detachment, antagonism, disinhibition, psychoticism. (Antagonism roughly corresponds to ICD-11 dissociality; low rigid perfectionism in disinhibition corresponds to ICD-11 anankastia; psychoticism has no ICD-11 personality equivalent.)
- The model keeps six types: antisocial, avoidant, borderline, narcissistic, obsessive-compulsive, schizotypal.
- **Measure:** PID-5 (220 items; 25- and 100-item short forms) and PID5BF+M (maps onto both systems). ⚠ Check APA licensing before digitising items.

### PD-04 Trait-blend modifiers (replaces v1 subtype map)
Millon observed that personality presentations often blend features of two or more styles. Rather than use separate subtype diagnoses, v2 treats blends as **modifiers**: the clinician selects the dominant pattern card, then adds the modifier, which contributes extra presentation notes and objectives. Code the result with ICD-11 severity plus trait qualifiers (or "other specified" in DSM-5-TR).

| Modifier ID | Dominant pattern + added features | Main ICD-11 traits |
|---|---|---|
| PD-AVD-C | Avoidant + marked ambivalence and resentment | Negative affectivity, detachment |
| PD-AVD-H | Avoidant + marked suspiciousness and edginess | Negative affectivity, detachment |
| PD-DEP-S | Dependent + low mood and self-effacement | Negative affectivity |
| PD-HIS-D | Histrionic + exploitative, deceptive features | Dissociality, disinhibition |
| PD-NAR-C | Narcissistic + fragile self-worth and resentment | Dissociality, negative affectivity |
| PD-NAR-U | Narcissistic + rule-breaking, exploitative features | Dissociality, disinhibition |
| PD-ASP-M | Antisocial + cruelty and deep mistrust | Dissociality |
| PD-OCP-B | Obsessive-compulsive + indecision and ambivalence | Anankastia, negative affectivity |
| PD-BPD-P | Borderline + sullen defiance and ambivalence | Borderline pattern, negative affectivity |
| PD-BPD-SD | Borderline + self-directed anger, guilt and hopelessness | Borderline pattern, negative affectivity |
| PD-PAR-F | Paranoid + grandiosity | Negative affectivity, dissociality |
| PD-PAR-M | Paranoid + hostility and vengefulness | Negative affectivity, dissociality |

**Patterns not recognised in current official systems** (code by severity and traits; describe the features):
- Aggressive / sadistic pattern (PD-AGG)
- Self-defeating / intropunitive pattern (PD-INT)
- Depressive personality pattern (PD-DPS)
- Negativistic / passive-aggressive pattern (PD-PA)

---

## PART 22 — PATTERN CARDS (library for the plan builder)
**Card layout:**
- **Presentation:** how the pattern commonly shows itself, in plain language (not diagnostic criteria — pull official ICD-11 text from the WHO API)
- **ICD-11 mapping:** typical trait domains to consider
- **Goals:** long-term goals
- **Objectives:** measurable templates (add to the core objectives in TPE-04; adjust numbers per client)
- **Schemas:** early maladaptive schemas often involved (PDX-02)
- **Methods:** best-fit approaches
- **Stance:** how the therapist should position themselves
- **⚠:** risks and pitfalls
- **Codes:** ICD-11 · ICD-10-CM (for insurers and legacy records)

### Cluster A-type patterns (odd / eccentric)

**PD-PAR Paranoid pattern**
- **Presentation:** expects to be used, cheated or betrayed without good grounds; doubts friends' and partners' loyalty; reluctant to share personal information in case it is used against them; finds hidden insults in ordinary remarks; holds on to grudges; reacts quickly with anger to perceived slights; may suspect a partner of infidelity without evidence.
- **ICD-11 mapping:** negative affectivity (mistrust), detachment; sometimes dissociality.
- **Goals:** trust others more where it is warranted; base conclusions on evidence; engage more with people; think more flexibly; express anger in healthy ways; feel safer being open.
- **Objectives:**
  - Rate sense of safety in sessions at 6/10 or above for 3 consecutive sessions.
  - Record 2 situations per week in which suspicion arose, noting the evidence for and against, for 6 weeks.
  - In 3 situations over the next month, respond to a perceived slight with a calm, direct statement instead of withdrawing or planning retaliation.
  - For 1 recurring conflict, list at least 2 ways own behaviour may contribute, by week 8.
  - For each suspicious explanation brought to session, generate at least 2 alternative explanations, for 4 weeks.
  - Share 1 piece of personal information with a trusted person each fortnight for 2 months.
  - Go 4 weeks without checking a partner's phone or testing their loyalty.
  - Choose 1 grudge and write an unsent letter letting go of it, by week 12.
  - Explore the feelings of shame or inadequacy underneath the mistrust in at least 3 sessions.
- **Schemas:** Mistrust/Abuse.
- **Methods:** CBT (examining evidence), social skills, couples work, person-centred work, schema therapy.
- **Stance:** transparent, respectful and predictable. Hand the client as much control as possible (e.g., show them your notes, explain each step). No jokes at their expense and no early confrontation; explore beliefs rather than argue with them.
- **⚠:** assess risk of violence (Core 1 ASM-06); rule out delusional disorder or psychosis.
- **Codes:** ICD-11 6D10.x + relevant 6D11 qualifiers · ICD-10-CM F60.0.

**PD-PAR-F Modifier: paranoid pattern with grandiosity**
- **Adds:** inflated beliefs about self held on thin evidence; superiority and contempt; responds to hurt pride with exaggerated claims; believes others envy them.
- **Extra objectives:**
  - Speak respectfully to the therapist in every session for 4 weeks, and say when feeling misunderstood.
  - Have 1 friendly conversation with someone each week for 6 weeks and report on it.
  - For 3 situations, compare "what I assumed others thought" with what they actually said or did.
  - Name 2 emotions other than anger felt during the week, for 4 weeks.
  - Explore in at least 2 sessions how expectations of being "a strong man/woman" limit emotional expression.
  - Break 1 grand ambition into 3 small, achievable steps and complete the first within a month.
- **Methods:** person-centred work, self-psychology (PDX-08), group and family work.
- **Stance:** mirror and validate before any reality-testing.

**PD-PAR-M Modifier: paranoid pattern with hostility and vengefulness**
- **Adds:** persecutory beliefs; attributes own hostility to others; revenge fantasies or acts; combative and domineering.
- **Extra objectives:**
  - Express anger in session without accusing or threatening, in each session for 6 weeks.
  - List 3 ways to show strength that don't involve intimidation, and use one weekly for a month.
  - Log hostile fantasies daily; aim for a 50% reduction in frequency over 8 weeks.
  - With consent, family members agree 1 change in how they respond to intimidating behaviour.
  - Identify 2 links between past experiences of being mistreated and present hostility by week 10.
- **Methods:** REBT, social and assertiveness skills, couples work.
- **⚠:** high risk of violence. Apply the duty-to-protect procedures (Core 1 ETH-01; Core 2 CHD-13).

**PD-SZD Schizoid pattern**
- **Presentation:** little wish for close relationships; prefers solitary activities; little interest in sexual experiences; finds few things enjoyable; no close confidants; seems unaffected by praise or criticism; restricted emotional expression.
- **ICD-11 mapping:** detachment (social and emotional).
- **Goals:** enjoy more activities; become more active; experience and express more emotion; develop social skills; clarify vague thinking; build warmer connections at a comfortable pace.
- **Objectives:**
  - Describe, in the client's own words, at least 2 reasons for avoiding relationships by week 4.
  - Schedule and complete 3 enjoyable solitary activities per week for 4 weeks, then 1 activity involving another person per week for the next 4.
  - Exercise for at least 20 minutes, 3 times a week, for 8 weeks.
  - Write 2 beliefs about other people's motives and test one with a small experiment by week 8.
  - In session, describe a feeling while noticing it in the body, on at least 3 occasions.
  - Meet 1 new person (e.g., at a class or group) within 3 months.
  - With consent, family agree to respect agreed periods of solitude.
- **Schemas:** Social Isolation/Alienation, Negativity/Pessimism.
- **Methods:** person-centred work and, for very detached clients, contact reflections (PDX-09); behavioural activation; social skills; group work later on.
- **Stance:** low pressure; respect the need for distance; don't push closeness early; follow the client's pace.
- **⚠:** check for depression hidden behind detachment; distinguish from autism and early psychosis.
- **Codes:** ICD-11 6D10.x + 6D11.1 · ICD-10-CM F60.1.

**PD-STY Schizotypal presentation**
- **Presentation:** believes unrelated events refer to them; unusual beliefs or perceptual experiences beyond cultural norms; odd speech or reasoning; suspiciousness; flat or unusual emotional expression; eccentric appearance or behaviour; few close relationships; social anxiety that doesn't ease with familiarity.
- **ICD-11 mapping:** ⚠ In ICD-11, **schizotypal disorder is classified with psychotic disorders (6A22), not personality disorders.** Use this card for planning only; code 6A22.
- **Goals:** think more clearly; reduce magical thinking and detachment from reality; enjoy more; build social skills; express feelings more; fear rejection or harm less.
- **Objectives:**
  - Meet agreed daily grooming and hygiene targets on at least 5 days a week for 6 weeks.
  - Identify 2 settings where discussing unusual beliefs is and isn't well received, by week 4.
  - When an unusual idea arises, check it against at least 1 reliable outside source, twice a week for 6 weeks.
  - Practise the phrase "Having a strong feeling doesn't make the thought true" when anxious, and log its use for 4 weeks.
  - For 1 event previously interpreted in an unusual way, write a practical explanation by week 6.
  - Complete a graded social exposure step with relaxation each week for 8 weeks.
- **Schemas:** Social Isolation/Alienation.
- **Methods:** CBT for psychosis-spectrum experiences, mindfulness, social skills, group work, psychiatric referral.
- **⚠:** **Check cultural context.** Beliefs shared within the client's cultural or religious community (e.g., *nazar* / evil eye, spirit possession, astrology) are not symptoms. Monitor for transition to psychosis.
- **Codes:** ICD-11 6A22 · ICD-10-CM F21.

### Cluster B-type patterns (dramatic / erratic)

**PD-ASP Antisocial / dissocial pattern**
- **Presentation:** repeated rule- or law-breaking; lying and conning; acting on impulse; aggression; reckless disregard for safety; failure to meet work, money or family obligations; little remorse; behaviour problems that began before adulthood.
- **ICD-11 mapping:** dissociality, disinhibition.
- **Goals:** consider others' needs; control impulses; manage anger; value cooperation and affection; behave responsibly; accept that rules apply to them.
- **Objectives:**
  - Express frustration without threats or violence in all sessions and in at least 3 logged real-life situations per month.
  - Write a list of at least 5 personal costs of past dishonest or unlawful acts by week 3.
  - Before any significant decision, complete a written pros/cons check; log at least 1 per week for 8 weeks.
  - Describe how 1 important person felt about something the client did, and say what they regret, by week 8.
  - For 3 conflicts with others, write a non-hostile explanation of the other person's behaviour.
  - Make 1 friendly gesture or compliment to someone each week for 6 weeks.
  - Attend work (or training) on at least 90% of scheduled days for 3 months.
  - Identify 2 recurring patterns in conflicts with authority and 1 change to try, by week 10.
- **Schemas:** Mistrust/Abuse, Punitiveness, Insufficient Self-Control/Self-Discipline.
- **Methods:** motivational interviewing, CBT, REBT, schema therapy, social and assertiveness skills, group work.
- **Stance:**
  - Link therapy to self-interest ("getting what you want without the legal costs").
  - Firm, consistent limits.
  - No moralising.
  - Expect some deception; verify important information.
- **⚠:** violence and legal risk; substance use; possible symptom exaggeration (Core 1 PSY-11).
- **Codes:** ICD-11 6D10.x + 6D11.2, 6D11.3 · ICD-10-CM F60.2.

**PD-ASP-M Modifier: antisocial pattern with cruelty and deep mistrust**
- **Adds:** brutality; hostility towards authority; expects betrayal; no guilt; fearless and callous; history of a chaotic or abusive childhood.
- **Extra objectives:**
  - When feeling belittled, respond assertively rather than aggressively in 3 logged situations per month.
  - Rate trust in 3 people on a 0–10 scale (rather than "trust/don't trust") by week 6.
  - Make 1 honest personal disclosure to 1 person within 3 months.
  - Link experiences of being victimised to current attitudes in at least 2 sessions.
- **Stance:** as for PD-AGG below.
- **⚠:** usually a forensic setting; possible risk to the therapist — keep safety arrangements in place.

**PD-AGG Aggressive / sadistic pattern (not an official category)**
- **Presentation:** uses intimidation, cruelty or violence to dominate; humiliates others in front of people; mistreats those under their authority; seems to enjoy others' suffering (including animals'); lies to cause harm; controls partners or family through fear; drawn to weapons, violence or cruelty.
- **ICD-11 mapping:** dissociality (often severe), sometimes disinhibition.
- **Goals:** stop aggression and humiliation of others; treat people under their authority fairly; influence others through negotiation rather than fear; allow family members independence; recognise the harm caused; develop at least one mutual relationship; channel aggressive interests safely.
- **Objectives:**
  - Describe at least 3 specific harms caused to others and state regret, by week 10.
  - Replace demeaning remarks with neutral or respectful ones; family (with consent) reports a 50% reduction over 8 weeks.
  - Agree 2 areas where family members make their own decisions without interference, within 6 weeks.
  - Identify 2 legal, safe outlets for aggression (e.g., a combat sport with rules) and use one weekly.
  - For 3 incidents, write an explanation of the other person's behaviour that doesn't assume malice.
  - Link own history of mistreatment to current behaviour in at least 2 sessions.
- **Stance:**
  - Early on, **avoid asking directly about feelings**, which the client may take as weakness.
  - Expect to earn respect.
  - Emphasise the practical gains of change.
  - Use MI (PDX-06); DBT skills group; referral to anger-management programmes.
- **⚠:** duty to protect potential victims; screen for domestic violence and child or animal abuse → mandatory reporting where required (Core 2 CHD-13). **Never use the label to explain away violence.**

**PD-BPD Borderline pattern** (strongest evidence base)
- **Presentation:** intense efforts to avoid real or imagined abandonment; stormy relationships that swing between idealising and devaluing; unstable sense of self; impulsive, self-damaging behaviour; recurrent suicidal behaviour or self-harm; rapid mood shifts; chronic emptiness; intense anger; brief paranoid thoughts or dissociation under stress.
- **ICD-11 mapping:** 6D11.5 borderline pattern specifier, usually with negative affectivity and disinhibition.
- **Goals:** stop suicidal and self-harming behaviour; build stable relationships; increase self-respect; improve problem-solving and communication; regulate emotions; reduce crisis-driven behaviour.
- **Objectives** (EB = element of an evidence-based protocol):
  - Agree treatment goals and the treatment approach in writing by session 3 **(EB)**.
  - Sign the agreed safety and contact policy by session 2 **(EB)**.
  - Complete a behaviour chain analysis for every episode of self-harm or suicidal behaviour, within 1 week of it occurring **(EB)**.
  - Reduce self-harm acts by at least 50% over 3 months, then to zero **(EB)**.
  - Complete a daily diary card on at least 6 days a week **(EB)**.
  - Use at least 2 distress-tolerance skills instead of self-harm or substance use in each crisis logged **(EB)**.
  - Express anger at a level of 6/10 or less, in words, in 3 logged conflicts per month **(EB)**.
  - In session, describe what another person may have been thinking and feeling in a conflict, on at least 4 occasions **(EB)**.
  - Reduce self-critical statements in session by half over 8 weeks (therapist counts) **(EB)**.
  - Describe 3 important people with both positive and negative qualities by week 12.
  - Write a statement of personal values and act on one value each week for 6 weeks (ACT).
  - In the ending phase, discuss feelings about termination in at least 3 sessions without crisis behaviour **(EB)**.
- **Interventions:** PDX-01 DBT, PDX-03 MBT, PDX-04 TFP, PDX-02 schema therapy (limited reparenting, empathic confrontation), PDX-10 frame management.
- **Schemas:** Abandonment/Instability, Mistrust/Abuse, Defectiveness/Shame, Dependence/Incompetence, Emotional Deprivation.
- **Couples work:** emotionally focused couple therapy for pursue–withdraw cycles; teach partners to reflect and validate each other.
- **⚠:**
  - Ongoing suicide risk: assess at every session and keep the safety plan current (Core 1 ASM-06).
  - Substance use.
  - Screen for PTSD / complex PTSD and childhood abuse.
  - Distinguish from bipolar II disorder and complex PTSD (ICD-11 6B41).
- **Codes:** ICD-11 6D10.x + 6D11.5 · ICD-10-CM F60.3.

**PD-BPD-P Modifier: borderline pattern with sullen defiance**
- **Adds:** negative and easily disappointed; impatient; defiant towards authority; torn between fear of being smothered and fear of being abandoned; very sensitive to criticism; brief psychotic-like episodes under stress; suicidal gestures.
- **Extra objectives:**
  - Wait at least 24 hours before acting on a decision made while angry, in 3 logged instances per month.
  - Receive 1 piece of feedback per week without leaving or retaliating, for 6 weeks.
  - Explore the pull between independence and closeness in at least 3 sessions using a decisional balance.
- **Add:** MI for ambivalence (PDX-06); psychiatric review for transient psychotic symptoms.

**PD-BPD-SD Modifier: borderline pattern with self-directed anger and guilt**
- **Adds:** anger and guilt turned inwards; hopelessness and helplessness; history of over-compliance and people-pleasing; frequent self-harm; moody and watchful for rejection.
- **Extra objectives:**
  - Identify 2 links between past mistreatment and current self-punishment by week 8.
  - Express anger outwardly and assertively, rather than at self, in 2 logged situations per month.
  - Map the "anger → guilt → apology" cycle on paper and identify 1 point to interrupt it, by week 6.
  - Say "no" to 1 request per week without apologising excessively, for 6 weeks.
  - Notice and log times of scanning for betrayal; discuss their effect on others in 2 sessions.
- **Methods:** DBT, schema therapy and mindfulness together.

**PD-HIS Histrionic pattern**
- **Presentation:** uncomfortable when not the centre of attention; may be inappropriately flirtatious; emotions that shift quickly and seem shallow to others; uses appearance to draw attention; speech that is vivid but vague; dramatic; easily influenced; believes relationships are closer than they are.
- **ICD-11 mapping:** negative affectivity, disinhibition; sometimes dissociality.
- **Goals:** replace attention-seeking with self-understanding; reduce manipulation; build genuine relationships; stabilise emotions; attend to detail; strengthen self-worth; become less suggestible.
- **Objectives:**
  - Agree 2 specific therapy goals by session 3.
  - Describe 1 conflict per session in concrete detail (who, what, when, what was said) for 4 weeks.
  - Notice and log urges to entertain or dramatise, and hold back from acting on them on at least half of occasions, over 6 weeks.
  - Share 1 vulnerable feeling with a partner or close friend each week for a month.
  - List at least 5 personal qualities others value that are not about appearance, by week 6.
  - Rate the closeness of 3 new relationships on a 0–10 scale and check the ratings with the therapist.
  - Spend 1 social occasion per week without seeking to be the centre of attention and rate comfort (0–10), for 6 weeks.
- **Schemas:** Emotional Deprivation, Abandonment/Instability, Approval-Seeking/Recognition-Seeking.
- **Methods:** CBT/REBT with attention to detail, mindfulness, couples work, schema therapy.
- **Stance:** warm but with clear boundaries; gently steer towards specifics; don't respond to flattery or crises with special treatment; watch for flirtatious transference and consult.
- **Codes:** ICD-11 6D10.x + relevant 6D11 qualifiers · ICD-10-CM F60.4.

**PD-HIS-D Modifier: histrionic pattern with exploitative features**
- **Adds:** charming but superficial; seeks thrills; impulsive; scheming; self-centred behind a caring front; dishonest; irresponsible; blames others.
- **Extra objectives:**
  - Complete assigned tasks honestly (no shortcuts or deception), verified at 4 consecutive reviews.
  - With consent, family describe in 1 session how deception has affected them.
  - Replace 1 thrill-seeking activity with a safe alternative each week for 6 weeks.
  - Complete a pros/cons check before impulsive decisions, at least weekly.

**PD-NAR Narcissistic pattern**
- **Presentation:** inflated sense of importance; fantasies of great success or power; believes they are special; needs admiration; feels entitled; takes advantage of others; limited empathy; envious or believes others envy them; arrogant.
- **ICD-11 mapping:** dissociality (self-centredness, lack of empathy); often negative affectivity (fragile self-worth).
- **Goals:** act rather than fantasise; increase empathy; reduce arrogance and entitlement; tolerate imperfection; stop exploiting and belittling others; set realistic goals; manage anger and envy.
- **Objectives:**
  - In session, correctly name another person's feelings in 3 described situations per month for 3 months.
  - Rephrase demands as requests; log at least 3 requests per week for 6 weeks.
  - With a partner, practise 1 attachment-focused conversation per week (EFT-informed) for 8 weeks.
  - Identify 1 goal they have been expecting to happen and list 3 steps to work towards it, by week 6.
  - Name 1 area in which they are average, and discuss how that feels, by week 8.
  - Receive feedback on 2 occasions without dismissing it, and write down what was useful, within 2 months.
  - Replace 30 minutes of daydreaming per day with a productive activity, 5 days a week, for 4 weeks.
- **Schemas:** Entitlement/Grandiosity, Defectiveness/Shame (the vulnerable core), Emotional Deprivation.
- **Methods:** schema therapy (vulnerable-child and self-aggrandiser modes), DBT skills for anger, mindfulness, EFT couples work, self-psychology.
- **Stance:**
  - Mirror and validate early on (self-psychology).
  - Avoid power struggles.
  - Confront with empathy only *after* the alliance is secure.
  - Expect cycles of idealisation and devaluation of the therapist.
- **Codes:** ICD-11 6D10.x + 6D11.2 (± 6D11.0) · ICD-10-CM F60.81.

**PD-NAR-C Modifier: narcissistic pattern with fragile self-worth**
- **Adds:** a sense of inferiority hidden under apparent superiority; self-worth dependent on achievement and praise; mixed feelings about others; alternates between taking charge and wanting others to lead; expects praise without effort; thin-skinned; blames others.
- **Extra objectives:**
  - Stay calm (rated ≤ 4/10 anger) in 3 previously provoking situations per month.
  - Have 1 conversation per week without trying to impress, and rate satisfaction.
  - Plan a weekly routine that includes at least 3 non-achievement activities, for 6 weeks.
  - Link the need for praise to early experiences in at least 2 sessions.
  - Repeat a self-acceptance statement (e.g., "I am worthwhile as a person, not only for what I achieve") daily for 4 weeks.
- **Self-psychology intervention:** when an effort falls short, name the disappointment and the hope behind it, then help turn the hope into a realistic aim. Example: "When your manager picked someone else's plan, it hit hard — you had hoped yours would be the one that made the difference."

**PD-NAR-U Modifier: narcissistic pattern with exploitative, rule-breaking features**
- **Adds:** lies when convenient; acts as if rules don't apply; weak conscience; disloyal; exploits people; contempt for those they take advantage of; domineering.
- **Extra objectives:**
  - Respond to therapy limits without argument at every session for 6 weeks.
  - List at least 5 long-term costs of exploiting or deceiving others by week 4.
  - Cooperate on 1 shared task each week without taking control, for 6 weeks.
  - Explore in 2 sessions how rigid ideas about masculinity or dominance shape behaviour.
- **⚠:** risk of fraud or exploitation of vulnerable people; legal issues.

**PD-PA Negativistic / passive-aggressive pattern (not an official category)**
- **Presentation:** quietly fails to follow through on commitments; feels unappreciated and misunderstood; sulky and argumentative; resents authority; envious; exaggerates misfortune; complains a lot; swings between hostility and apology.
- **ICD-11 mapping:** negative affectivity; sometimes dissociality.
- **Goals:** follow through reliably; cooperate more and oppose less; express anger directly; resolve the tension between wanting independence and wanting support; feel more content; complain less.
- **Objectives:**
  - Complete agreed homework on at least 3 of every 4 weeks for 3 months.
  - Arrive on time and attend all sessions for 8 weeks.
  - Express 1 disagreement per week directly and assertively, for 6 weeks.
  - Log complaints for 1 week, then reduce the daily count by half over the next month.
  - Describe 2 recent misfortunes in balanced terms (what went wrong and what went right).
  - Map the "defiance → regret" cycle and identify 1 alternative response, by week 6.
  - With a manager or other authority figure, carry out 1 request cooperatively each week and note the outcome.
- **Schemas:** Negativity/Pessimism, Mistrust/Abuse, Subjugation.
- **Methods:** **MI is central** (PDX-06); family and group work; assertiveness training; schema therapy.
- **Stance:**
  - Expect "yes, but…".
  - **Don't give too much advice** — eagerness to help can feed a pattern of defeating the helper.
  - Roll with resistance and hand responsibility back.
  - Name the pattern together, without blame.
  - Use supervision for your own frustration.

### Cluster C-type patterns (anxious / fearful)

**PD-AVD Avoidant pattern**
- **Presentation:** avoids work or social contact for fear of criticism or rejection; gets involved only when sure of being liked; holds back in close relationships for fear of embarrassment; preoccupied with being rejected; quiet in new situations because they feel inadequate; sees self as inferior or unappealing; reluctant to try new things.
- **ICD-11 mapping:** negative affectivity, detachment.
- **Goals:** reduce withdrawal and loneliness; build social skills; ease self-criticism; focus on what matters rather than on threat; take interpersonal risks; ruminate less about rejection; build closeness.
- **Objectives:**
  - Draw a diagram of what keeps the avoidance going and state commitment to change, by session 4.
  - Start 1 conversation per week and rate how it went (0–10), for 6 weeks.
  - Do 1 activity each week that involves another person, for 8 weeks.
  - Write a list of personal values and take 1 value-guided action each week even when anxious (ACT), for 6 weeks.
  - Log "I'm not good enough" thoughts daily for 2 weeks to establish a baseline, then write a balanced response to each.
  - Complete 1 step of a graded social exposure hierarchy each week, using relaxation, for 10 weeks.
  - Voice 1 disagreement or make 1 request that risks refusal, twice a month for 3 months.
  - Couples: identify how avoiding conflict creates distance, and share 1 preference with the partner each week.
  - Join a social-anxiety group within 3 months.
- **Schemas:** Defectiveness/Shame, Social Isolation/Alienation, Failure, Subjugation.
- **Methods:** CBT for social anxiety with exposure (Core 1 INT-03), schema therapy, ACT, social skills, couples work, group. **Evidence B.**
- **Stance:** gentle and accepting; never shaming; praise small risks; watch for quiet drop-out.
- **Codes:** ICD-11 6D10.x + 6D11.0, 6D11.1 · ICD-10-CM F60.6.

**PD-AVD-C Modifier: avoidant pattern with marked ambivalence**
- **Adds:** avoids people yet longs for them; constant inner conflict; torn between independence and attachment and afraid of both; distressed; bitter about past relationships.
- **Extra objectives:**
  - Practise a daily self-calming routine (e.g., relaxation or self-hypnosis recording, PDX-11) on at least 5 days a week for 6 weeks.
  - Set 1 personal boundary per fortnight in a close relationship and note how it felt.
  - Write 5 positive personal qualities by week 4 and add 1 per week thereafter.
  - Use "I" statements in 2 difficult conversations per month.
  - With consent, family agree 1 change that stops reinforcing avoidance.

**PD-AVD-H Modifier: avoidant pattern with suspiciousness**
- **Adds:** very wary; swings between panic and irritability; brooding and tense; strong fear of shame; highly sensitive to rejection; puts self down; feels misunderstood.
- **Extra objectives:**
  - Rate trust in the therapy process ≥ 6/10 by session 6.
  - Practise a 10-minute mindfulness exercise (observing thoughts) on 5 days a week for 6 weeks.
  - Use a body-focused awareness exercise (e.g., Gendlin's focusing) in 3 sessions.
  - Identify 2 past experiences that taught them to expect shame, by week 8.
  - Share 1 private concern with a trusted person within 2 months.

**PD-DEP Dependent pattern**
- **Presentation:** needs a great deal of advice and reassurance to make everyday decisions; wants others to take responsibility for major areas of life; finds it hard to disagree for fear of losing support; lacks confidence to start things alone; goes to great lengths to obtain care; feels helpless when alone; quickly seeks a new source of support when a relationship ends; worries about being left to cope alone.
- **ICD-11 mapping:** negative affectivity (submissiveness, separation insecurity).
- **Goals:** build confidence and competence; become more decisive and assertive; feel comfortable alone; know and meet own needs; cling less.
- **Objectives:**
  - List 5 situations in which deciding alone feels hard, by week 3.
  - Make 1 small decision per day without seeking reassurance, for 4 weeks; then 1 larger decision with limited consultation (no more than 1 person) by week 10.
  - Record compliments received and accept each one without dismissing it, for 4 weeks.
  - Take on 1 new responsibility at home or work by week 8.
  - Disagree with a significant other on 1 issue each fortnight for 2 months.
  - Decline 1 unwanted task per week for 6 weeks.
  - Do 1 enjoyable activity alone each week for 6 weeks.
  - With consent, partner agrees 1 change that supports independence rather than clinging.
- **Schemas:** Dependence/Incompetence, Abandonment/Instability, Subjugation, Self-Sacrifice.
- **Methods:** CBT, schema therapy, assertiveness training, couples work/EFT, Adlerian encouragement, group.
- **Stance:**
  - **Don't rescue** — hand decisions back.
  - Build independence step by step.
  - Plan the ending early and taper sessions (Core 2 CSK-43).
- **⚠:** screen for an abusive relationship (safety and exit planning). Expect strong anxiety around therapist breaks.
- **Codes:** ICD-11 6D10.x + 6D11.0 · ICD-10-CM F60.7.
- **India note:** close family interdependence is culturally normal. Judge whether dependence is *impairing* relative to the client's own cultural norms — not against Western ideals of independence.

**PD-DEP-S Modifier: dependent pattern with low mood and self-effacement**
- **Adds:** gives up own identity to stay close to others; low or frantic when separated; feels worthless; draws self-esteem from belonging to a person or group; cannot disagree.
- **Extra objectives:**
  - Write 3 sources of self-worth that don't depend on a partner or group, by week 6.
  - Identify triggers for fear of being alone and plan a coping response for each, by week 4.
  - List practical survival skills (income, food, housing, travel) and rate confidence in each; raise the lowest by 2 points in 3 months.
  - Choose and do 1 activity reflecting own interests each week, for 8 weeks.
  - Where relevant, complete a written safety and exit plan for an abusive relationship.

**PD-OCP Obsessive-compulsive (anankastic) pattern**
- **Presentation:** so focused on rules, lists and detail that the main point is lost; perfectionism gets in the way of finishing; work crowds out friends and leisure; rigid about morals and values; can't throw away worn-out or worthless items; reluctant to delegate; careful with money to the point of meanness; stubborn; emotionally restrained.
- **ICD-11 mapping:** anankastia.
- **Goals:** loosen focus on rules and detail; reduce perfectionism, guilt and self-criticism; become more flexible; relax more; express emotion; brighten mood; let go of hoarded items and money.
- **Objectives:**
  - Complete 1 task per week to a "good enough" standard within a set time limit, for 6 weeks.
  - Discard at least 1 unneeded item per week for 8 weeks (exposure).
  - Write down 3 beliefs that drive over-working, by week 4.
  - Delegate 1 task per week and accept the result without redoing it, for 6 weeks.
  - Spend a set amount purely for enjoyment once a fortnight for 2 months.
  - Keep 1 hour of leisure on at least 4 days a week for 6 weeks.
  - Stay calm (≤ 4/10 distress) when a routine is disrupted, in 2 logged instances per month.
  - In session, describe a current feeling in 1–2 sentences before explaining the facts, on at least 4 occasions.
  - Couples: identify 1 recurring power struggle and agree a shared approach by week 10.
- **Schemas:** Unrelenting Standards/Hypercriticalness, Punitiveness, Emotional Inhibition.
- **Methods:** experiential and person-centred work (for emotion), schema therapy, CBT, exposure (discarding, delegating), couples work, mindfulness. **Evidence B** (schema therapy).
- **Stance:** don't compete intellectually; focus on feelings over facts; gently point out perfectionism when it shows up *in* sessions (e.g., very detailed accounts).
- **Differential:** distinguish from OCD (unwanted obsessions and rituals — Core 1) and hoarding disorder.
- **Codes:** ICD-11 6D10.x + 6D11.4 · ICD-10-CM F60.5.

**PD-OCP-B Modifier: obsessive-compulsive pattern with indecision and ambivalence**
- **Adds:** chronic indecision leading to procrastination; circles repeatedly over mixed feelings about people; confused and distressed; fears losing control of thoughts or feelings; uses routines to feel in control.
- **Extra objectives:**
  - Make 1 decision per week using a 15-minute pros/cons limit and a "good enough" rule, for 6 weeks.
  - Cope with 1 planned schedule change per week, rating distress before and after.
  - Write a balanced description of 1 relationship they ruminate about, by week 6.
  - Reduce 1 control ritual by half over 8 weeks.

### Patterns outside current official systems

**PD-DPS Depressive personality pattern (not an official category; ego-syntonic)**
- **Presentation:** habitually gloomy and joyless; deep sense of inadequacy; puts self down; worries; critical of self and others; pessimistic; prone to guilt and regret. The world is experienced as the problem, rather than the mood.
- **ICD-11 mapping:** negative affectivity.
- **Goals:** lift mood; raise self-worth; ruminate less; become more hopeful; feel less guilt; complain less; build relationships; solve problems actively rather than resign.
- **Objectives:**
  - Explore the pros and cons of giving up a pessimistic outlook (MI) and state a decision, by week 4.
  - Record and challenge 1 automatic negative thought per day for 4 weeks.
  - Reduce self-critical remarks in session by half over 8 weeks (therapist counts).
  - Schedule 3 pleasant activities per week for 8 weeks.
  - Describe 1 difficult experience per fortnight in a way that shows it was bearable, funny or a chance to learn.
  - Have 1 conversation per week without complaining, for 6 weeks.
  - Write an unsent letter about an old hurt or resentment by week 10.
- **Methods:** CBT, behavioural activation, schema therapy, family work, MI, Adlerian encouragement.
- **Differential:** if criteria are met for dysthymia / persistent depressive disorder (ICD-11 6A72), code that instead. **Screen for suicide risk.**

**PD-INT Self-defeating / intropunitive pattern (not an official category)**
- **Presentation:**
  - Repeatedly ends up in situations or relationships that lead to disappointment or mistreatment.
  - Undermines own enjoyment; turns down help.
  - Feels guilty or low after good events.
  - Provokes rejection and then feels hurt.
  - Fails at tasks despite having the ability.
  - Drawn to people who treat them badly; uninterested in those who are kind.
  - Sacrifices self excessively.
  - *(Millon described this as a pain–pleasure reversal: enjoyment triggers guilt and a pull towards self-punishment.)*
- **ICD-11 mapping:** negative affectivity.
- **Goals:** see self as deserving respect; build mutual relationships; enjoy things without guilt; give and receive help; set boundaries; reach goals on time; understand where the pattern came from; process any past abuse.
- **Objectives:**
  - Explore in at least 3 sessions how care in childhood may have come mainly through illness or suffering.
  - Use a self-soothing activity instead of self-punishment in 3 logged situations per month.
  - Complete 1 important task on time each week for 6 weeks.
  - Say "no" or state a need at the risk of displeasing someone, twice a month for 3 months.
  - Express anger outwardly and assertively in 2 logged situations per month.
  - Accept 1 compliment per week and note 1 moment of enjoyment afterwards, for 6 weeks.
  - Act on a personal value rather than mood at least weekly (ACT), for 6 weeks.
  - Where relevant, complete a written safety and exit plan for an abusive relationship.
  - Where trauma is present, begin trauma-focused work once stabilised (Core 2 INT-14).
- **Methods:** schema therapy, DBT, mindfulness, social and assertiveness skills, MI, couples work, trauma-focused therapy.
- **⚠:** screen for current abuse and intimate-partner violence. The language caution applies — never describe a client as "wanting to suffer".

---

## PART 23 — PERSONALITY-FOCUSED INTERVENTION LIBRARY (PDX)
*(New in this Core. CBT, REBT, exposure, relaxation, family work and SFBT are in Cores 1–2.)*

### PDX-01 Dialectical Behaviour Therapy (DBT; Linehan)
- **Evidence:** A (borderline pattern; self-harm). **Level:** L2 with formal DBT training.
- **Full programme:**
  1. Weekly individual therapy
  2. Weekly skills-training group (about 2–2.5 hours)
  3. Brief, skills-focused coaching between sessions
  4. A consultation team for therapists
  - Usually at least a year, with a firm commitment from the client.
- **Order of priorities in each session:**
  1. Behaviour that threatens life
  2. Behaviour that interferes with therapy (the client's *or* the therapist's)
  3. Behaviour that seriously harms quality of life
  4. Learning new skills
- **Four skills areas (described in our words; Linehan's own skill names given for reference):**

| Area | What it teaches |
|---|---|
| **Mindfulness** | Balancing emotional and logical thinking ("wise mind"); observing and describing experience and taking part fully; doing so without judging, one thing at a time, and in ways that work |
| **Distress tolerance** | Getting through a crisis without making it worse: fast body-based ways to bring down intense arousal (e.g., cold water on the face, brief intense exercise, slowed breathing, paired muscle relaxation); distraction; soothing the senses; improving the moment; weighing pros and cons; accepting what cannot be changed right now ("radical acceptance"); pausing before acting |
| **Emotion regulation** | Naming emotions; checking whether the emotion fits the facts; acting opposite to an unhelpful urge ("opposite action"); building positive experiences and a sense of mastery; planning ahead for hard situations; looking after the body (illness, eating, sleep, exercise, avoiding mood-altering substances) to lower vulnerability |
| **Interpersonal effectiveness** | Asking for what you want or saying no clearly and confidently; keeping relationships healthy while doing so; keeping self-respect (fairness, honesty, sticking to your values). Linehan's skills for these are known as DEAR MAN, GIVE and FAST |

- **Tools:**
  - **Diary card:** daily ratings of urges and actions (self-harm, suicidal urges, substance use), emotions, and skills used — a natural app feature (design our own layout; do not copy manual forms).
  - **Behaviour chain analysis:** vulnerabilities → prompting event → each link (thoughts, feelings, body sensations, actions) → problem behaviour → consequences; then plan a solution at each link.
  - **Levels of validation** — from simply listening, through accurate reflection and naming the unspoken, to showing that the reaction makes sense given history and present circumstances, and treating the person as an equal.
  - **Dialectical stance:** acceptance *and* change together.
- **Adaptations:**
  - Skills groups alone can help anger, impulsivity and emotional instability in other patterns (antisocial, narcissistic, aggressive, self-defeating).
  - DBT-A for adolescents, with family members in skills training.
  - India: brief and group-based DBT-informed programmes are feasible; adapt examples to local culture.
- ⚠ **Copyright:** the DBT skills manual and handouts are published works. The app may describe and teach the skills in original wording but must not reproduce official handouts or worksheets without a licence.

### PDX-02 Schema Therapy (Young)
- **Evidence:** B (A for borderline pattern in some reviews); applicable across patterns. **Level:** L2/L3 with training.
- **18 early maladaptive schemas in 5 domains** (standard terminology):

| Domain | Schemas |
|---|---|
| Disconnection & rejection | Abandonment/Instability · Mistrust/Abuse · Emotional Deprivation · Defectiveness/Shame · Social Isolation/Alienation |
| Impaired autonomy & performance | Dependence/Incompetence · Vulnerability to Harm or Illness · Enmeshment/Undeveloped Self · Failure |
| Impaired limits | Entitlement/Grandiosity · Insufficient Self-Control/Self-Discipline |
| Other-directedness | Subjugation · Self-Sacrifice · Approval-Seeking/Recognition-Seeking |
| Over-vigilance & inhibition | Negativity/Pessimism · Emotional Inhibition · Unrelenting Standards/Hypercriticalness · Punitiveness |

- **Coping styles:** giving in to the schema (surrender), avoiding it, or overcompensating.
- **Modes (moment-to-moment states):**
  - *Child modes:* vulnerable, angry, impulsive/undisciplined, contented
  - *Coping modes:* compliant surrenderer, detached protector, overcompensator (e.g., self-aggrandiser, bully and attack)
  - *Internalised parent modes:* punitive, demanding
  - *Healthy adult*
- **Techniques:**
  1. **Limited reparenting:** meeting core emotional needs within professional limits — warmth, guidance, healthy limits — until the client can meet them for themselves.
  2. **Empathic confrontation:** acknowledge why the pattern made sense, then point out its present-day cost, including within the therapy relationship. Example: "It makes sense that you learned to leave before others could leave you — and when you cancel our sessions after we've had a good one, you lose the support you're asking for."
  3. **Cognitive techniques:** weighing evidence for and against a schema; flashcards; dialogues between the schema side and the healthy side.
  4. **Experiential techniques:** imagery rescripting of childhood memories; chair work between modes.
  5. **Breaking behavioural patterns:** homework to act against the schema.
- **Measures:** Young Schema Questionnaire (short form, 90 items); Schema Mode Inventory. ⚠ Check licensing before digitising items.
- **Therapist schemas:** notice your own (e.g., approval-seeking, unrelenting standards) when a client activates them.

### PDX-03 Mentalization-Based Treatment (MBT; Bateman & Fonagy)
- **Evidence:** A–B (borderline pattern). **Level:** L2/L3 with training.
- **Target:** the ability to make sense of one's own and others' behaviour in terms of thoughts, feelings and intentions — an ability that tends to break down under attachment-related stress.
- **When mentalizing breaks down** (high arousal, certainty about what others think, very concrete thinking):
  1. **Empathise and validate** the client's current experience.
  2. **Clarify**, and challenge if needed: "Can we slow down and go back? What happened just before you felt that?"
  3. **Gently broaden:** "What might have been going on for her at that moment?" · "How do you think I came across just then?"
- **Stance:** curious and not-knowing; avoid long interpretations while the client is highly aroused.
- **Sequence:** start in the here and now → as mentalizing improves, move to key attachment relationships (including with the therapist) → later, explore distorted pictures of parents and attachment history.
- **Outcome objective (example):** the client describes, in at least 3 sessions, how thinking about others' minds changed their reaction to a real situation.

### PDX-04 Transference-Focused Psychotherapy (TFP; Kernberg and colleagues)
- **Evidence:** B. **Level:** L3 (psychodynamic training).
- **Model:** the client's inner world contains split images of self and others (all-good vs all-bad, each tied to strong emotion), and these are re-enacted in the relationship with the therapist.
- **Frame:** a clear spoken agreement covering attendance, fees, safety, and limits on contact between sessions.
- **Techniques:**
  - Clarify → point out contradictions → interpret what is happening between client and therapist now.
  - Identify which self–other pairing is active, including role reversals.
  - **When the client is angry with the therapist:** explore it, connect it to other important relationships, and work towards a shared understanding.
  - **When the client regresses in session:** explore what it does to the relationship.
- **Aim:** bring split images together so the client can see themselves and others as mixed, whole people.

### PDX-05 Acceptance and Commitment Therapy (ACT; Hayes, Strosahl & Wilson)
- **Evidence:** B across conditions; C for personality problems specifically. Useful across all patterns because it targets *avoidance of inner experience* rather than particular symptoms.
- **Six processes:** acceptance · defusion (e.g., "I'm noticing the thought that…") · contact with the present moment · self-as-context · **values** · committed action.
- **Key exercises:**
  - Values clarification ("What do you want your life to be about?") — helpful for identity confusion.
  - Willingness to feel discomfort in the service of values (avoidant presentations).
  - **Acting on values rather than mood** (a common objective across pattern cards).
  - Metaphors — for example, driving a bus while unruly passengers shout directions, or dropping the rope in a tug-of-war with a monster.
- **Tools:** values worksheet, defusion exercises, committed-action tracker (well suited to the app).

### PDX-06 Motivational Interviewing (MI; Miller & Rollnick) for ego-syntonic patterns
- **Evidence:** A (substance use); B–C for personality problems. Central for antisocial, aggressive, negativistic, obsessive-compulsive and depressive presentations, and for anyone ambivalent about change.
- **Spirit:** partnership, acceptance, compassion, evoking the client's own reasons.
- **Core skills (OARS):** open questions, affirmations, reflections, summaries.
- **Change talk:** listen for, invite and reinforce statements of desire, ability, reasons and need (preparing for change), and of commitment, readiness and steps already taken (mobilising change).
- **Two-sided reflection (example):** "Part of you feels that shouting is the only way to be taken seriously — and another part hates how it's pushing your family away."
- **Other methods:** don't argue with resistance; highlight the gap between current behaviour and the client's goals; support confidence to change; weigh pros and cons.
- **Stages of change (Prochaska & DiClemente):** not yet considering → considering → preparing → acting → maintaining (with possible relapse). Match interventions to the stage.

### PDX-07 Emotionally Focused Couple Therapy (EFT; Johnson)
- **Evidence:** A (relationship distress). Use with couples affected by borderline, narcissistic, dependent, histrionic or avoidant patterns.
- **Stage 1 — de-escalation:**
  - Identify the **negative cycle** (e.g., one partner pursues, the other withdraws; one attacks, the other defends).
  - Bring out the attachment fears underneath (abandonment, rejection, not being good enough).
  - Reframe the cycle as the couple's shared enemy.
- **Stage 2 — restructuring bonds:** the withdrawn partner re-engages; the critical partner softens; both express attachment needs openly and respond to each other.
- **Stage 3 — consolidation:** new solutions and a new shared story of the relationship.
- **With personality difficulties:** explicitly teach partners to reflect and validate each other, since failures of validation drive much of the conflict.

### PDX-08 Self-psychology interventions (Kohut)
- For narcissistic presentations (especially with fragile self-worth) and paranoid presentations with grandiosity.
- **Mirroring:** reflect the client's hopes and sense of worth.
- **Idealising and twinship needs:** allow a period of idealising the therapist without deflating it too early.
- **Repair empathic failures** openly ("I think I missed how much that mattered to you").
- **Work with deflation:** connect disappointment to the underlying wish, then help reshape the wish into a realistic ambition.

### PDX-09 Pre-therapy contact reflections (Prouty)
- For very detached clients (schizoid or schizotypal presentations, psychosis) with limited contact with their surroundings. **Evidence C.**
- **Types of contact reflection (simple, concrete, unhurried):**
  - *Situational:* describing the immediate surroundings ("The fan is turning.")
  - *Facial:* naming what the face shows ("You're frowning.")
  - *Word-for-word:* repeating the client's words, even fragments
  - *Body:* describing or gently mirroring posture
  - *Reiterative:* returning to reflections that previously made contact
- **Aim:** restore contact with reality, with feelings and with other people before regular therapy begins.

### PDX-10 Managing the therapy frame in high-risk presentations
1. **Explicit agreement at the start:** attendance, payment, arriving sober, safety expectations, what happens if the agreement is broken, and the therapist's availability.
2. **Between-session contact:** for skills coaching or crises only, usually no more than about 10 minutes; longer needs become an extra appointment. Put it in writing and apply it consistently.
3. **Suicide and self-harm:**
   - The client agrees to contact the therapist or a crisis line *before* acting on urges.
   - Assess suicide risk throughout.
   - ⚠ *"No-harm contracts" have no evidence of preventing suicide and must never replace a collaborative **safety plan** (Core 1 ASM-06).*
4. **Understanding self-harm:**
   - First understand the pain fully.
   - Then explore what the behaviour *communicates* and what *reinforces* it (e.g., being taken seriously, relief from tension).
   - Then list reasons for living and turn them into goals.
5. **Behaviour that interferes with therapy** (missed sessions, wanting friendship with the therapist, hostility): name it, understand it, solve it together.
6. **Therapist reactions:** take anger, exasperation or feeling manipulated to supervision or the consultation team.
7. **Ending:** talk through thoughts and feelings about ending so that this relationship ends differently from painful past ones (especially important for borderline and dependent presentations).

### PDX-11 Clinical hypnosis and self-hypnosis (adjunct)
- **Evidence:** C for personality targets; B as an adjunct for anxiety and pain.
- **Level:** L2 plus recognised hypnosis training.
- **Uses:** relaxation, ego-strengthening and self-esteem imagery, rehearsing new behaviour (e.g., avoidant presentations).
- **Outline:** induction → deepening → ego-strengthening suggestions → a cue for later self-hypnosis → teaching self-hypnosis for daily practice.
- **⚠ Contraindications:** psychosis, severe dissociation, unprocessed trauma (unless the clinician has trauma competence). Never use hypnosis to "recover" memories.

### PDX-12 Adlerian interventions
- For dependent, depressive and histrionic presentations.
- **Encouragement** — recognise effort and progress rather than praising results.
- **Lifestyle assessment:** family constellation and early recollections.
- Explore social interest and mistaken private beliefs.
- **"Acting as if":** the client practises behaving as the person they want to become.
- **Measure:** BASIS-A Inventory (check licensing).

### PDX-13 Reusable skill objectives across patterns
| Skill | Useful for |
|---|---|
| Written pros/cons check before acting | Antisocial, exploitative histrionic, borderline (Core 2 CSK-32) |
| "Shades of grey" exercise — describe people who are mixed on a quality | Borderline, narcissistic, paranoid |
| Generating non-hostile explanations for others' behaviour | Paranoid, antisocial, aggressive, narcissistic |
| Empathy practice — name the other person's feeling and describe their situation | Narcissistic, antisocial, schizoid, obsessive-compulsive |
| Telling assertive, aggressive and passive responses apart + assertiveness log | Most patterns (Core 2 CSK-34) |
| Exploring meaning and purpose (e.g., spirituality, volunteering; after Frankl) | Borderline emptiness, hostile paranoid, ambivalent avoidant |
| Exploring rigid gender roles (e.g., links between rigid masculinity, aggression and emotional restriction) | Exploitative narcissistic, paranoid with grandiosity or hostility |
| Leaving an abusive relationship (safety plan + exit plan) | Dependent, self-defeating |

### PDX-14 Self-help reading (examples; check local availability)
- **DBT skills:** a DBT skills workbook for clients.
- **Schema therapy:** *Reinventing Your Life* (Young & Klosko).
- **Mindfulness:** *Wherever You Go, There You Are* (Kabat-Zinn); MBSR courses.
- **Self-esteem:** *Self-Esteem* (McKay & Fanning); *Ten Days to Self-Esteem* (Burns).
- **Assertiveness:** *Your Perfect Right* (Alberti & Emmons).
- **Couples:** *Hold Me Tight* (Johnson).
- **Meaning:** *Man's Search for Meaning* (Frankl).
- **Boundaries:** a boundaries workbook.

---

## APPENDIX F — DATA MODEL ADDITIONS (extends Core 1 DATA-01 and Core 2 Appendix D)

| Entity | Key fields |
|---|---|
| **ProblemLibrary** | problem_id (e.g., PD-BPD), name, cluster, official (bool), modifier_of, presentation[], ltg[], objectives[] {id, text, target_count, unit, setting, deadline_weeks, intervention_ids[], eb_flag}, interventions[] {id, text, modality, eb_flag, homework_ref, min_level}, icd11 {trait_domains[], borderline_pattern, alt_code}, icd10cm |
| **TreatmentPlanV2** | plan_id, client_id, primary_problem_id, modifier_ids[], secondary_problem_ids[], client_definitions[], ltg_selected[], objectives[] {text, target_count, unit, setting, deadline, status, linked_interventions[]}, recovery_overlay (bool), review_dates[], version |
| **InsightRating** | client_id, date, level (dystonic/ambivalent/syntonic), stage_of_change |
| **ICD11PersonalityRating** | client_id, date, severity (none/difficulty/mild/moderate/severe/unspecified), trait_domains {negative_affectivity, detachment, dissociality, disinhibition, anankastia: 0–3}, borderline_pattern (bool), rater |
| **LPFSRating** (optional DSM cross-walk) | client_id, date, identity_0_4, self_direction_0_4, empathy_0_4, intimacy_0_4 |
| **TraitProfile** | client_id, source (PID5BF+M/PID-5/clinician), domain scores, facet scores (if available) |
| **SchemaProfile** | client_id, source (questionnaire/clinician), schemas[] {name, score_1_6}, active_modes[] |
| **DiaryCard** (DBT-style) | client_id, date, urges {self_harm, suicide, substance: 0–5}, acts {…: bool}, emotions {…: 0–5}, skills_used[], notes |
| **ChainAnalysis** | client_id, target_behavior, vulnerabilities[], prompting_event, links[] {type, content}, consequences[], solutions[] |
| **FrameContract** | client_id, attendance, fees, sobriety, safety_terms, contact_policy {purpose, max_minutes}, signed_at |
| **CountertransferenceLog** | clinician_id, client_id, date, feeling, trigger, own_schema_activated, consultation_ref |
| **RecoveryPlan** | client_id, 10 principle objectives {status}, strengths_assessment_ref, peer_support_ref |

**Changes from v1:** subtype problems are now modifiers (`modifier_of`, `modifier_ids[]`); new `ICD11PersonalityRating` entity; objectives carry structured measurability fields; `definitions[]` renamed `presentation[]`.

**Product rules added:**
1. **Plan validator:** every objective needs at least 1 linked intervention and completed target/unit/setting/deadline fields. Evidence-based elements show an **EB badge**.
2. **Syntonic flag:** if insight = syntonic, suggest MI modules first and de-emphasise confrontation-heavy modules.
3. **ICD-11 first:** diagnosis entry defaults to ICD-11 severity + trait qualifiers, with official text fetched live from the WHO ICD API. Non-official patterns cannot be coded as diagnoses; exported legal or forensic reports show a language-caution warning.
4. **Borderline safety:** a diary card with self-harm urges ≥ 4 or any self-harm act alerts the clinician and opens the safety plan. The contact-policy timer is visible to the clinician.
5. **Competence gating:** DBT, MBT, TFP, schema therapy, hypnosis and pre-therapy modules require the matching training credential (L2/L3).
6. **Culture check:** paranoid and schizotypal items prompt the clinician to rule out culturally shared beliefs; dependent items prompt a comparison with the family's cultural norms of interdependence.
7. **Manual content:** DBT, schema therapy, MBT and similar modules teach skills in original wording and link to official manuals; no licensed handouts, forms or questionnaire items are reproduced without a licence.

---

## APPENDIX G — REFERENCES & VERSION LOG

### G.1 Key references (primary literature and official sources)
- **Classification:** World Health Organization. *ICD-11 for Mortality and Morbidity Statistics* — chapter 6, 6D10–6D11 (access via the WHO ICD API). · Tyrer, P., Mulder, R., Kim, Y.-R., & Crawford, M. J. (2019). The development of the ICD-11 classification of personality disorders. *Annu Rev Clin Psychol*, 15, 481–502. · American Psychiatric Association (2022). *DSM-5-TR*, Section III Alternative Model. · Krueger, R. F., et al. (2012). PID-5. *Psychol Med*, 42, 1879–1890. · Oltmanns, J. R., & Widiger, T. A. (2020). PID5BF+M. · Olajide, K., et al. (2018). SASPD.
- **Integrative / personality-guided therapy:** Millon, T. (1999). *Personality-Guided Therapy.* · Millon, T., & Davis, R. *Disorders of Personality.*
- **Recovery:** SAMHSA (2012). *SAMHSA's Working Definition of Recovery: 10 Guiding Principles.*
- **DBT:** Linehan, M. M. (1993; 2015). *Cognitive-Behavioral Treatment of Borderline Personality Disorder*; *DBT Skills Training Manual* (2nd ed.).
- **Schema therapy:** Young, J. E., Klosko, J. S., & Weishaar, M. E. (2003). *Schema Therapy.* · Bamelis, L. L. M., et al. (2014). *Am J Psychiatry*, 171, 305–322.
- **MBT:** Bateman, A., & Fonagy, P. (2016). *Mentalization-Based Treatment for Personality Disorders.*
- **TFP:** Yeomans, F. E., Clarkin, J. F., & Kernberg, O. F. (2015). *Transference-Focused Psychotherapy for Borderline Personality Disorder.*
- **ACT:** Hayes, S. C., Strosahl, K. D., & Wilson, K. G. (2012). *Acceptance and Commitment Therapy* (2nd ed.).
- **MI:** Miller, W. R., & Rollnick, S. (2013). *Motivational Interviewing* (3rd ed.). · Prochaska, J. O., & DiClemente, C. C. (1983).
- **EFT:** Johnson, S. M. (2004). *The Practice of Emotionally Focused Couple Therapy.*
- **Self-psychology:** Kohut, H. (1971). *The Analysis of the Self.*
- **Pre-therapy:** Prouty, G. (1994). *Theoretical Evolutions in Person-Centered/Experiential Therapy.*
- **Adlerian:** Adler, A.; Dinkmeyer, D., & Sperry, L. *Counseling and Psychotherapy: An Integrated, Individual Psychology Approach.*
- **Focusing:** Gendlin, E. T. (1978). *Focusing.* · **Meaning:** Frankl, V. E. (1946/2006).
- **Treatment-plan method:** the problem → goal → objective → intervention structure is a widely used planning convention in mental-health practice; the statement banks in this Core are original to YourCounselor AI.

### G.2 Version log
| Version | Change |
|---|---|
| v2.0 | Full rewrite in original wording. Statement library rebuilt from scratch: new presentation summaries (not criteria text), new goals, and new objective banks written to the measurability standard with default numbers. PD framework reorganised ICD-11-first (severity + trait domains + borderline pattern; schizotypal re-coded to 6A22). Millon-style subtypes converted to trait-blend modifiers with neutral descriptive names (IDs kept). DBT and other manualised skills described in original language with a licensing note. Dependency on a commercial treatment planner removed. |

*End of Core 3*
