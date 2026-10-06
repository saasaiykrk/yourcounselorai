/// Fixed safety wording and option lists shared by the screens.
///
/// These mirror the backend so the app and server never disagree:
/// - [kDisclaimer] matches `DISCLAIMER` in `app/inspector.py`.
/// - [kCrisisLines] come from `skill/clinical-assist/references/crisis-resources.md`
///   (the single source of truth); `test/safety_content_test.dart` fails if they drift.
/// - [ReportCategory.apiValue] matches `IncidentIn.category` in `app/main.py`.
library;

const kDisclaimer =
    'This tool is for professional use only. It does not diagnose or replace therapy. '
    'AI-generated information is intended to support, not replace, the judgment of a '
    'qualified mental-health professional. For emergencies or acute safety concerns, '
    'contact appropriate licensed professionals or emergency services.';

class CrisisLine {
  const CrisisLine(this.service, this.number);

  final String service;

  /// As written in the register, e.g. `1-800-891-4416`.
  final String number;

  String get dialString => number.replaceAll('-', '');
}

const kCrisisLines = <CrisisLine>[
  CrisisLine('Emergency', '112'),
  CrisisLine('Tele-MANAS', '14416'),
  CrisisLine('Tele-MANAS toll-free', '1-800-891-4416'),
  CrisisLine('Child Helpline', '1098'),
  CrisisLine('Women Helpline', '181'),
];

/// Printed at the top of every downloaded report (PDF), before the clinical content.
/// Handling rules for the file itself; the clinical disclaimer [kDisclaimer] ends the document.
const kPdfPrecautions = <String>[
  'For the treating clinician\'s professional use only. It is not a diagnosis, a prescription or a '
      'medico-legal record, and it does not replace your own assessment and clinical judgement.',
  'It contains de-identified information only. Do not add names, contact details or any other '
      'identifier to this file or to anything you attach it to.',
  'Keep it secure: store it only on a protected device or folder, do not send it by ordinary email '
      'or messaging apps, and delete it when you no longer need it.',
  'Verify every suggestion before use: diagnostic codes, tools and timelines are to be confirmed by you. '
      'Do not share it with the client or others without your clinical judgement.',
  'If there is any immediate risk to the client, follow your local crisis pathway; do not wait for or '
      'rely on this document.',
];

/// The register asks app screens to state when the numbers were last checked.
const kCrisisVerifiedNote = 'Numbers verified to 24 Sep 2026; confirm your local pathway.';

enum ConsultMode {
  auto('auto', 'Auto', 'We pick the best format from what you wrote.'),
  fullPlan(
    'A',
    'Full plan',
    'Complete work-up: audit, safety, formulation, therapy and session plan. Takes 1–2 minutes.',
  ),
  quick('B', 'Quick review', 'Short audit, safety screen and next steps.'),
  differential('C', 'Differential', 'Considerations to rule in or out, with what to ask next.'),
  sessionPlan('D', 'Session plan', 'A structured plan for your next session.'),
  diagnosisReview('E', 'Diagnosis review', 'A second look at your own working diagnosis.'),
  notes('F', 'Notes', 'Draft documentation: SOAP, risk note, referral letter.'),
  auditOnly('G', 'Audit only', 'Checks your case history and mental status exam for gaps.');

  const ConsultMode(this.apiCode, this.label, this.hint);

  final String apiCode;
  final String label;
  final String hint;
}

enum ReportCategory {
  unsafe('unsafe', 'Unsafe advice'),
  wrongClinical('wrong_clinical', 'Clinically wrong'),
  missingSafety('missing_safety', 'A safety step is missing'),
  identifierLeak('identifier_leak', 'It shows a client identifier'),
  crisisNumber('crisis_number', 'Wrong crisis number'),
  other('other', 'Something else');

  const ReportCategory(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

/// Gender choices at registration (the clinician's own), matching the profile API.
const kGenders = {'female': 'Female', 'male': 'Male', 'other': 'Other', 'prefer_not_to_say': 'Prefer not to say'};

enum ClinicianRole {
  trainee('counsellor_trainee', 'Counsellor or trainee', 'Supervised wording, no diagnostic labels', 'none'),
  psychologist('psychologist', 'Psychologist', 'RCI registration needed', 'RCI'),
  psychiatrist('psychiatrist', 'Psychiatrist', 'NMC or State Medical Council', 'NMC');

  const ClinicianRole(this.apiValue, this.label, this.detail, this.registrationBody);

  final String apiValue;
  final String label;
  final String detail;
  final String registrationBody;

  bool get needsRegistration => registrationBody != 'none';
}
