/// Sample content for the design build.
///
/// The screens are wired to these fixed examples until the real services
/// land: the Dart cleaner (plan Step 3, a port of `app/deid.py` tested
/// against `fixtures/deid_vectors.json`) and the backend API client.
/// Nothing here is clinical guidance; the reply text is placeholder copy.
library;

import '../widgets/surfaces.dart';

const kSampleCase =
    'Priya, 34F, panic attacks for 3 months, 2–3 per week, fear of dying during episodes. '
    'Call 98765 43210. Works at Sunrise Traders. Came with her sister Asha. '
    'PHQ-9 8, GAD-7 14. Risk asked, denies suicidal ideation and self-harm.';

/// One run of cleaned text: plain text, or a tag such as `[PHONE]`.
class CleanSegment {
  const CleanSegment(this.text, {this.isTag = false, this.possibleName = false});

  final String text;
  final bool isTag;

  /// A capitalised word the cleaner could not be sure about.
  final bool possibleName;
}

class CleanPreview {
  const CleanPreview({required this.segments, required this.removed});

  final List<CleanSegment> segments;

  /// Plain-language counts, e.g. {"name": 1, "phone number": 1}.
  final Map<String, int> removed;

  int get removedTotal => removed.values.fold(0, (a, b) => a + b);

  String get possibleName => segments.firstWhere((s) => s.possibleName, orElse: () => const CleanSegment('')).text;
}

CleanPreview previewCleaner({required bool removePossibleName}) {
  return CleanPreview(
    segments: [
      const CleanSegment('[NAME]', isTag: true),
      const CleanSegment(', 34F, panic attacks for 3 months, 2–3 per week, fear of dying during episodes. Call '),
      const CleanSegment('[PHONE]', isTag: true),
      const CleanSegment('. Works at '),
      const CleanSegment('[ORG]', isTag: true),
      const CleanSegment('. Came with her sister '),
      removePossibleName ? const CleanSegment('[NAME]', isTag: true) : const CleanSegment('Asha', possibleName: true),
      const CleanSegment('. PHQ-9 8, GAD-7 14. Risk asked, denies suicidal ideation and self-harm.'),
    ],
    removed: {removePossibleName ? 'names' : 'name': removePossibleName ? 2 : 1, 'phone number': 1, 'workplace': 1},
  );
}

class AuditRow {
  const AuditRow(this.item, this.status, this.tone, this.comment);

  final String item;
  final String status;
  final Tone tone;
  final String comment;
}

const kPreviewAudit = <AuditRow>[
  AuditRow('Risk asked', 'Done', Tone.brand, 'Asked and absent; date not recorded'),
  AuditRow("Client's own words", 'Partial', Tone.check, '"Feels like dying" only'),
  AuditRow('Consent, informants, setting', 'Missing', Tone.crisis, 'Not documented'),
];

/// Sections 4–17 of a full plan, as named in the clinical-assist templates.
const kReplySections = <String>[
  'Differential considerations',
  'Severity & functional impairment',
  'Recommended assessment plan',
  'Therapy modalities to consider',
  'Best-suited therapy',
  'Therapy goals',
  "Therapist's role & actions",
  'Client tasks & lifestyle',
  'Family guidance',
  'Session-wise treatment plan',
  'Worksheets & clinical tools',
  'Progress monitoring',
  'Red flags, referral & ethics',
  'Final clinical summary',
];
