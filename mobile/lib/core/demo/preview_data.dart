/// Sample content for preview builds (`APP_MODE=preview`, the default).
///
/// Nothing here is clinical guidance: the reply sections are placeholder copy
/// shaped like a real Mode A reply so the reply screen can be reviewed
/// without a server. Real replies come from the backend.
library;

import '../content/safety_content.dart';

const kSampleCase =
    'Ms. Priya Nair, 34F, panic attacks for 3 months, 2–3 per week, fear of dying during episodes. '
    'Call 98765 43210. She works at Sunrise Traders. Came with her sister Asha. '
    'PHQ-9 8, GAD-7 14. Risk asked, denies suicidal ideation and self-harm.';

/// Preview only: typing this phrase shows the risk (Gate 1) reply.
const kPreviewRiskPhrase = 'wants to end it';

const _placeholderSections = [
  'Differential Considerations',
  'Severity & Functional Impairment',
  'Recommended Assessment Plan',
  'Therapy Modalities to Consider',
  'Best-Suited Therapy Recommendation',
  'Therapy Goals (proposed — agree with client)',
  "Therapist's Role & Actions",
  'Client Tasks & Lifestyle Adjustments',
  'Parent/Guardian/Family Guidance',
  'Session-Wise Treatment Plan & Weekly Summary',
  'Worksheets & Clinical Tools',
  'Progress Monitoring & Treatment-Response Decisions',
  'Red Flags, Referral & Ethical Considerations',
  'Final Clinical Summary',
];

final String kPreviewReplyMarkdown = [
  '### 1. Case History & MSE Audit',
  '',
  '**1a. Procedural audit**',
  '',
  '| Procedure | Status | Comment |',
  '|---|---|---|',
  '| Risk explicitly asked | ✔ | Asked and absent; date not recorded |',
  "| Client's own words for chief complaint | ◐ | \"Feels like dying\" only |",
  '| Consent · informants · setting | ✘ | Not documented |',
  '',
  '### 2. Safety & Risk Screen',
  '',
  '[Sample text. The real reply states the current risk status and what to confirm next.]',
  '',
  '### 3. PROVISIONAL — Low confidence · Pattern Analysis & Formulation',
  '',
  '[Sample text. The real reply gives the formulation here.]',
  for (final (i, title) in _placeholderSections.indexed) ...[
    '',
    '### ${i + 4}. PROVISIONAL — Low confidence · $title',
    '',
    '[Sample text for this section.]',
  ],
  '',
  '> **$kDisclaimer**',
].join('\n');

final String kPreviewSafetyMarkdown = [
  '### ⚠ Acute risk — routine planning paused',
  '',
  '[Sample text. The real reply summarises the risk indicators and the immediate steps for the clinician.]',
  '',
  '**Before continuing:** confirm the client is safe right now and record what you did.',
  '',
  '> **$kDisclaimer**',
].join('\n');
