# Consultation Report — fixed template (Mode R)

Used only for the app's **guided consultation** report (`Requested mode: R`). Every consultation report has
exactly these headings, in this order, with these titles — no section is ever dropped, renamed, merged or
reordered. When information for a section was not provided, keep the section and write what is missing and
how to obtain it; never invent case details. Match the depth and tone of
`references/example-consult-report-ocd.md`, building all content from the case summary you are given.

**Source labels.** The Case Snapshot holds only what the clinician provided (write *(not provided)* for gaps,
*(unknown — clinician did not know)* for answers the clinician did not know). Sections 1–2 are your analysis
(working formulation, never a diagnosis). Sections 3–13 are recommendations. Mark any assumption *(assumed)*
and list it under **Assumptions made**.

**Level rules.** L1 (counsellor / trainee): in Section 1 replace the ICD-11 table with
"Areas for the supervisor or a psychologist to assess" — no diagnostic labels or codes — and make discussing
with the supervisor a next step in Section 12. L2/L3: full Section 1.

**Codes and numbers.** ICD-11 codes only if `icd11_lookup` returned them this turn; otherwise write
"code to confirm at icd.who.int". Phone numbers only from `crisis-resources.md`. No medication advice beyond
the prescriber-review line.

**Links (Section 14).** Use only these sites; otherwise give the resource title without a link:
iocdf.org · spacetreatment.net · nice.org.uk · bfrb.org · healthychildren.org · who.int · icd.who.int ·
nimhans.ac.in · telemanas.mohfw.gov.in

```
## Consultation Report — {short de-identified case descriptor, e.g. "Childhood OCD traits & digital dependence"}

### Case Snapshot
| Field | Details |
| --- | --- |
| Age / Gender | … |
| Education / Occupation | … |
| Presenting concern | … |
| Duration | … |
| Prior therapy | … |
| Medications | … |
| Medical / physical | … |
| Family | … |
| Help requested | … |

**Risk screening:** {status as provided: asked and absent / risk present (with what was done) / not yet asked}.
{If not yet asked or unclear: "Confirm before Session 1 — ask about self-harm, wish to die, abuse, harm to
others. If any are present, follow the Safety & Risk Protocol before this plan."}

**Assumptions made:** {list, or "None"}. If any is wrong, revisit Section 1.

*Snapshot = information you provided · Sections 1–2 = analysis · Sections 3–13 = recommendations.*

### 1. Psychological Case Pattern Analysis
{Overall pattern in 2–3 sentences — "a working formulation, not a diagnosis".}
#### ICD-11 (WHO) categories to consider
| ICD-11 code and title | Fit with this case | Status |   {Consider / Rule out / Not met — with the tool that confirms}
#### Behaviour → likely function → treatment target
| Observed behaviour | Likely function (to confirm) | Treatment target |
**Why this matters:** {the one clinical distinction that changes treatment}
#### Formulation (5 Ps)
- **Presenting:** · **Predisposing:** · **Precipitating:** · **Perpetuating:** · **Protective:**
#### Rule out before finalising (differentials)
- {each with the trigger for referral}
**Confidence:** {High / Moderate / Low} — {reason}

### 2. Severity Classification
**Provisional: {Mild / Moderate / Severe}.** {reason from functioning} Confirm with {named measure}; the score
sets the baseline. {Severity bands table for that measure if commonly used.}
**When to escalate:** {thresholds and who to refer to}
**Confidence:** {High / Moderate / Low} — {reason}

### 3. Recommended Psychometric Tools
| Tool | What it measures | Who completes it | When | Notes for the clinician |
**Why this matters:** {…}

### 4. Therapy Modalities to Consider
| Modality | What it targets here | Evidence strength |

### 5. Best-Suited Therapy Recommendation
**Primary approach:** {…} **Order of priority:** {…}
#### Step 1 — {…}   {numbered steps with exact scripts, ladders/tables where relevant}

### 6. Therapist's Role & Actions
#### Key actions
#### Common mistakes to avoid
| Mistake | Why it backfires | Do this instead |

### 7. Client's Actions and Lifestyle Adjustments
{short, concrete, age-appropriate tasks}

### 8. Guardian/Parent Guidance
{For a minor: parent/guardian guidance. For an adult: guidance for family or support persons, with the
client's consent — or "Not applicable — {reason}" plus what the family should avoid.}
| Do | Don't |

### 9. Session-Wise Treatment Plan ({N} Weeks)
{Session length and format; phases with week-by-week Session / Homework / Parent or family task / Check.}

### 10. Suggested Worksheets & Tools
| Worksheet / tool | Purpose | Used by | From week |

### 11. Progress Monitoring & Tracking Tools
| Measure | How often | Target by Week {N} |
**At every session, ask:** {…}

### 12. Final Summary & Next Steps
**Summary:** {2–3 sentences}
**Next steps this week:** {numbered}
**Refer if:** {each trigger → who}

### 13. Weekly Therapy Summary
| Week | Focus | Techniques | Client homework | Parent/family task | Measure |

### 14. Helpful Resource Links
- {approved sites only — see above} · include Tele-MANAS (India) 14416
*Verify links before sharing with clients.*

### 15. Disclaimer
In any situation involving risk to life or safety, contact emergency services (India: 112) or Tele-MANAS 14416.

> **This tool is for professional use only. It does not diagnose or replace therapy. AI-generated information is intended to support, not replace, the judgment of a qualified mental-health professional. For emergencies or acute safety concerns, contact appropriate licensed professionals or emergency services.**
```

If the case summary shows imminent risk that the clinician has not said is being managed, do not write this
report: give the Gate 1 output from `mode-templates.md` instead (contract line `mode=R gate=gate1`).
