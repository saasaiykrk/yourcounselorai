/// Shapes of the backend's JSON (see `app/main.py`).
library;

/// `GET /v1/me`.
class Me {
  const Me({
    required this.verificationStatus,
    this.level,
    this.role,
    this.registrationBody,
    this.isAdmin = false,
    this.guidedConsultation = false,
    this.fullName,
    this.gender,
    this.age,
    this.registrationNumber,
  });

  factory Me.fromJson(Map<String, dynamic> json) => Me(
    verificationStatus: json['verification_status'] as String? ?? 'none',
    level: json['level'] as String?,
    role: json['role'] as String?,
    registrationBody: json['registration_body'] as String?,
    isAdmin: json['is_admin'] == true,
    guidedConsultation: (json['features'] as Map?)?['consultation'] == true,
    fullName: json['full_name'] as String?,
    gender: json['gender'] as String?,
    age: (json['age_at_registration'] as num?)?.toInt(),
    registrationNumber: json['registration_number'] as String?,
  );

  /// none (no profile yet) · pending · verified · rejected
  final String verificationStatus;

  /// L1 / L2 / L3, set only by an admin after checking the register.
  final String? level;
  final String? role;
  final String? registrationBody;

  /// Set only in the database by another admin; shows the Admin area. The
  /// backend checks it again on every admin request.
  final bool isAdmin;

  /// The server has guided consultations switched on (`CONSULTATION_ENABLED`).
  final bool guidedConsultation;

  /// The clinician's own name, as given at registration.
  final String? fullName;

  /// The clinician's own gender and age (Account → Edit profile).
  final String? gender;
  final int? age;
  final String? registrationNumber;

  bool get needsProfile => verificationStatus == 'none';
  bool get isVerified => verificationStatus == 'verified' && level != null;
  bool get isRejected => verificationStatus == 'rejected';
}

/// `POST /v1/profile`.
class ProfileSubmission {
  const ProfileSubmission({
    required this.fullName,
    required this.gender,
    required this.age,
    required this.role,
    required this.registrationBody,
    required this.registrationNumber,
    required this.consentVersion,
  });

  /// The clinician's own details (never a client's). Seen only by admins checking the
  /// register; never sent to the AI.
  final String fullName;

  /// female · male · other · prefer_not_to_say
  final String gender;
  final int age;
  final String role;
  final String registrationBody;
  final String? registrationNumber;
  final String consentVersion;

  Map<String, dynamic> toJson() => {
    'full_name': fullName,
    'gender': gender,
    'age': age,
    'role': role,
    'registration_body': registrationBody,
    'registration_number': registrationNumber,
    'consent_version': consentVersion,
  };
}

/// `PATCH /v1/profile`: the clinician edits their own details. Never a level or status;
/// a changed role or registration sends the account back for verification.
class ProfileEdit {
  const ProfileEdit({
    required this.fullName,
    required this.gender,
    required this.age,
    required this.role,
    required this.registrationBody,
    required this.registrationNumber,
  });

  final String fullName;
  final String gender;
  final int age;
  final String role;
  final String registrationBody;
  final String? registrationNumber;

  Map<String, dynamic> toJson() => {
    'full_name': fullName,
    'gender': gender,
    'age': age,
    'role': role,
    'registration_body': registrationBody,
    'registration_number': registrationNumber,
  };
}

class ProfileEditResult {
  const ProfileEditResult({required this.verificationStatus, required this.reverify});

  factory ProfileEditResult.fromJson(Map<String, dynamic> j) => ProfileEditResult(
    verificationStatus: j['verification_status'] as String? ?? 'pending',
    reverify: j['reverify'] == true,
  );

  final String verificationStatus;

  /// True when the role or registration changed and an admin must check it again.
  final bool reverify;
}

/// `POST /v1/consult`. The text must already be cleaned on the phone.
class ConsultRequest {
  const ConsultRequest({required this.text, required this.mode, required this.redactionCounts, this.conversationId});

  final String text;

  /// auto or A–G.
  final String mode;

  /// Counts by type only (e.g. {"PHONE": 1}); never the values.
  final Map<String, int> redactionCounts;
  final String? conversationId;

  Map<String, dynamic> toJson() => {
    'text': text,
    'mode': mode,
    'conversation_id': conversationId,
    // The clinician ticked "no identifiers"; the app cannot send without it.
    'deid_attested': true,
    'client_redaction_counts': redactionCounts,
  };
}

/// The contract line the inspector parsed, e.g. mode=A gate=none ceiling=Low level=L2.
class ReplyMeta {
  const ReplyMeta({this.mode, this.gate, this.ceiling, this.level});

  factory ReplyMeta.fromJson(Map<String, dynamic>? json) => ReplyMeta(
    mode: json?['mode'] as String?,
    gate: json?['gate'] as String?,
    ceiling: json?['ceiling'] as String?,
    level: json?['level'] as String?,
  );

  final String? mode;
  final String? gate;
  final String? ceiling;
  final String? level;

  /// Gate 1/2: immediate risk. The reply is a safety pathway, not a plan.
  bool get isSafetyGate => gate != null && gate != 'none' && gate!.isNotEmpty;
}

/// `POST /v1/consult` response.
class ConsultReply {
  const ConsultReply({
    required this.turnId,
    required this.conversationId,
    required this.delivered,
    required this.text,
    required this.skillVersion,
    required this.meta,
  });

  factory ConsultReply.fromJson(Map<String, dynamic> json) {
    final report = json['report'] as Map<String, dynamic>?;
    return ConsultReply(
      turnId: json['turn_id'] as String,
      conversationId: json['conversation_id'] as String,
      delivered: json['status'] == 'delivered',
      text: json['text'] as String? ?? '',
      skillVersion: json['skill_version'] as String? ?? '',
      meta: ReplyMeta.fromJson(report?['meta'] as Map<String, dynamic>?),
    );
  }

  final String turnId;
  final String conversationId;

  /// False when the inspector held the reply back; [text] is then the safe fallback.
  final bool delivered;

  /// Markdown, contract line already removed by the server.
  final String text;
  final String skillVersion;
  final ReplyMeta meta;
}

// --- admin -------------------------------------------------------------------

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

/// A clinician registration as the admin list shows it.
class AdminClinician {
  const AdminClinician({
    required this.id,
    required this.email,
    required this.role,
    required this.verificationStatus,
    this.registrationBody,
    this.registrationNumber,
    this.level,
    this.verificationNote,
    this.createdAt,
    this.fullName,
    this.gender,
    this.age,
  });

  factory AdminClinician.fromJson(Map<String, dynamic> j) => AdminClinician(
    id: '${j['id']}',
    email: j['email'] as String? ?? '',
    fullName: j['full_name'] as String?,
    gender: j['gender'] as String?,
    age: (j['age_at_registration'] as num?)?.toInt(),
    role: j['role'] as String? ?? '',
    verificationStatus: j['verification_status'] as String? ?? 'pending',
    registrationBody: j['registration_body'] as String?,
    registrationNumber: j['registration_number'] as String?,
    level: j['level'] as String?,
    verificationNote: j['verification_note'] as String?,
    createdAt: _date(j['created_at']),
  );

  final String id;
  final String email;
  final String role;
  final String verificationStatus;
  final String? registrationBody;
  final String? registrationNumber;
  final String? level;
  final String? verificationNote;
  final DateTime? createdAt;

  /// Asked at registration; older accounts may not have them.
  final String? fullName;
  final String? gender;
  final int? age;
}

/// A "Report a problem" item or an automatic held-back report. [inputDeid],
/// [outputShown] and [inspectorReports] are only filled when opened.
class AdminIncident {
  const AdminIncident({
    required this.id,
    required this.source,
    required this.category,
    required this.status,
    this.note,
    this.reviewerNote,
    this.level,
    this.turnStatus,
    this.requestedMode,
    this.createdAt,
    this.inputDeid,
    this.outputShown,
    this.inspectorReports,
  });

  factory AdminIncident.fromJson(Map<String, dynamic> j) => AdminIncident(
    id: '${j['id']}',
    source: j['source'] as String? ?? '',
    category: j['category'] as String? ?? '',
    status: j['status'] as String? ?? 'open',
    note: j['note'] as String?,
    reviewerNote: j['reviewer_note'] as String?,
    level: j['level'] as String?,
    turnStatus: j['turn_status'] as String?,
    requestedMode: j['requested_mode'] as String?,
    createdAt: _date(j['created_at']),
    inputDeid: j['input_deid'] as String?,
    outputShown: j['output_shown'] as String?,
    inspectorReports: j['inspector_reports'],
  );

  final String id;
  final String source;
  final String category;
  final String status;
  final String? note;
  final String? reviewerNote;
  final String? level;
  final String? turnStatus;
  final String? requestedMode;
  final DateTime? createdAt;
  final String? inputDeid;
  final String? outputShown;
  final Object? inspectorReports;

  bool get automatic => source == 'inspector';
}

// --- consult history -------------------------------------------------------------

/// One past consult in a History list. Text is the de-identified case as sent.
class ConsultSummary {
  const ConsultSummary({
    required this.id,
    required this.preview,
    required this.turns,
    required this.modes,
    this.title,
    this.lastStatus,
    this.createdAt,
    this.lastAt,
    this.hiddenAt,
  });

  factory ConsultSummary.fromJson(Map<String, dynamic> j) => ConsultSummary(
    id: '${j['id']}',
    title: j['title'] as String?,
    preview: j['preview'] as String? ?? '',
    turns: (j['turns'] as num?)?.toInt() ?? 0,
    modes: [for (final m in (j['modes'] as List? ?? const [])) '$m'],
    lastStatus: j['last_status'] as String?,
    createdAt: _date(j['created_at']),
    lastAt: _date(j['last_at']),
    hiddenAt: _date(j['hidden_at']),
  );

  final String id;
  final String? title;
  final String preview;
  final int turns;
  final List<String> modes;
  final String? lastStatus;
  final DateTime? createdAt;
  final DateTime? lastAt;

  /// Only in admin views: when the clinician removed it from their History.
  final DateTime? hiddenAt;
}

class ConsultTurn {
  const ConsultTurn({
    required this.input,
    required this.reply,
    required this.mode,
    required this.status,
    this.createdAt,
    this.id = '',
    this.level,
    this.skillVersion = '',
  });

  factory ConsultTurn.fromJson(Map<String, dynamic> j) => ConsultTurn(
    id: '${j['id'] ?? ''}',
    input: j['input_deid'] as String? ?? '',
    reply: j['output_shown'] as String? ?? '',
    mode: j['requested_mode'] as String? ?? '',
    status: j['status'] as String? ?? '',
    level: j['level'] as String?,
    skillVersion: j['skill_version'] as String? ?? '',
    createdAt: _date(j['created_at']),
  );

  final String id;
  final String input;
  final String reply;
  final String mode;
  final String status;
  final String? level;
  final String skillVersion;
  final DateTime? createdAt;

  bool get delivered => status == 'delivered';
}

class ConsultDetail {
  const ConsultDetail({required this.id, required this.turns, this.title, this.createdAt, this.hiddenAt});

  factory ConsultDetail.fromJson(Map<String, dynamic> j) => ConsultDetail(
    id: '${j['id']}',
    title: j['title'] as String?,
    createdAt: _date(j['created_at']),
    hiddenAt: _date(j['hidden_at']),
    turns: [for (final t in (j['turns'] as List? ?? const [])) ConsultTurn.fromJson(t as Map<String, dynamic>)],
  );

  final String id;
  final String? title;
  final DateTime? createdAt;
  final DateTime? hiddenAt;
  final List<ConsultTurn> turns;
}

// --- guided consultation ---------------------------------------------------------------

/// Where a guided consultation is (the server decides; the app only shows it).
enum ConsultationStage {
  questioning,
  ready,
  generating,
  completed,
  safetyStop;

  static ConsultationStage fromApi(String? s) => switch (s) {
    'INFORMATION_SUFFICIENT' => ready,
    'REPORT_GENERATION' => generating,
    'COMPLETED' => completed,
    'SAFETY_STOP' => safetyStop,
    _ => questioning,
  };
}

/// The one open question, with why it is asked and any quick replies.
class ConsultationQuestion {
  const ConsultationQuestion({
    required this.field,
    required this.question,
    this.why = '',
    this.options = const [],
    this.number = 0,
    this.clarify = false,
  });

  factory ConsultationQuestion.fromJson(Map<String, dynamic> j) => ConsultationQuestion(
    field: j['field'] as String? ?? '',
    question: j['question'] as String? ?? '',
    why: j['why'] as String? ?? '',
    options: [for (final o in (j['options'] as List? ?? const [])) '$o'],
    number: (j['number'] as num?)?.toInt() ?? 0,
    clarify: j['clarify'] as bool? ?? false,
  );

  final String field;
  final String question;
  final String why;
  final List<String> options;
  final int number;

  /// True when this follows up an unclear or contradictory answer (at most once per field).
  final bool clarify;
}

/// A question already answered ("(don't know)" and "(skipped)" included).
class ConsultationExchange {
  const ConsultationExchange({required this.question, required this.answer});

  factory ConsultationExchange.fromJson(Map<String, dynamic> j) =>
      ConsultationExchange(question: j['question'] as String? ?? '', answer: j['answer'] as String? ?? '');

  /// Empty when the clinician added information without a question.
  final String question;
  final String answer;
}

/// `/v1/consultations…` state: compact, de-identified, held by the server.
class Consultation {
  const Consultation({
    required this.id,
    required this.stage,
    this.question,
    this.briefAnswer = '',
    this.caseType = '',
    this.caseSummary = '',
    this.facts = const {},
    this.unknown = const [],
    this.infoNeeded = const [],
    this.questionsAsked = 0,
    this.maxQuestions = 8,
    this.transcript = const [],
    this.reply,
  });

  factory Consultation.fromJson(Map<String, dynamic> j) => Consultation(
    id: '${j['id']}',
    stage: ConsultationStage.fromApi(j['stage'] as String?),
    question: j['question'] is Map<String, dynamic>
        ? ConsultationQuestion.fromJson(j['question'] as Map<String, dynamic>)
        : null,
    briefAnswer: j['brief_answer'] as String? ?? '',
    caseType: j['case_type'] as String? ?? '',
    caseSummary: j['case_summary'] as String? ?? '',
    facts: {for (final e in ((j['facts'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
    unknown: [for (final u in (j['unknown'] as List? ?? const [])) '$u'],
    infoNeeded: [for (final n in (j['info_needed'] as List? ?? const [])) '$n'],
    questionsAsked: (j['questions_asked'] as num?)?.toInt() ?? 0,
    maxQuestions: (j['max_questions'] as num?)?.toInt() ?? 8,
    transcript: [
      for (final t in (j['transcript'] as List? ?? const [])) ConsultationExchange.fromJson(t as Map<String, dynamic>),
    ],
    reply: j['reply'] is Map<String, dynamic> ? ConsultReply.fromJson(j['reply'] as Map<String, dynamic>) : null,
  );

  final String id;
  final ConsultationStage stage;
  final ConsultationQuestion? question;

  /// The AI's short answer when the clinician asked something during the intake.
  final String briefAnswer;

  /// The kind of case the AI identified (a planning label, not a diagnosis).
  final String caseType;
  final String caseSummary;

  /// What the clinician has told us so far, by field (e.g. age_gender).
  final Map<String, String> facts;

  /// Fields the clinician did not know or skipped.
  final List<String> unknown;

  /// What the report still needs for this case, most important first (field keys).
  final List<String> infoNeeded;
  final int questionsAsked;
  final int maxQuestions;
  final List<ConsultationExchange> transcript;

  /// The finished report, once written.
  final ConsultReply? reply;
}

/// An unfinished consultation in the "Continue" list.
class ConsultationSummary {
  const ConsultationSummary({
    required this.id,
    required this.stage,
    this.caseSummary = '',
    this.questionsAsked = 0,
    this.updatedAt,
  });

  factory ConsultationSummary.fromJson(Map<String, dynamic> j) => ConsultationSummary(
    id: '${j['id']}',
    stage: ConsultationStage.fromApi(j['stage'] as String?),
    caseSummary: j['case_summary'] as String? ?? '',
    questionsAsked: (j['questions_asked'] as num?)?.toInt() ?? 0,
    updatedAt: _date(j['updated_at']),
  );

  final String id;
  final ConsultationStage stage;
  final String caseSummary;
  final int questionsAsked;
  final DateTime? updatedAt;
}

/// Plain-language label for a fact key, e.g. age_gender → "Age / gender".
String consultationFieldLabel(String field) => switch (field) {
  'presenting_concern' => 'Presenting concern',
  'age_gender' => 'Age / gender',
  'duration_onset' => 'Duration and onset',
  'risk_screening' => 'Risk screening',
  'education_occupation' => 'Education / occupation',
  'help_requested' => 'Help requested',
  'prior_therapy' => 'Prior therapy',
  _ => field.isEmpty ? 'Detail' : (field[0].toUpperCase() + field.substring(1)).replaceAll('_', ' '),
};
