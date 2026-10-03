/// Shapes of the backend's JSON (see `app/main.py`).
library;

/// `GET /v1/me`.
class Me {
  const Me({required this.verificationStatus, this.level, this.role, this.registrationBody, this.isAdmin = false});

  factory Me.fromJson(Map<String, dynamic> json) => Me(
    verificationStatus: json['verification_status'] as String? ?? 'none',
    level: json['level'] as String?,
    role: json['role'] as String?,
    registrationBody: json['registration_body'] as String?,
    isAdmin: json['is_admin'] == true,
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

  bool get needsProfile => verificationStatus == 'none';
  bool get isVerified => verificationStatus == 'verified' && level != null;
  bool get isRejected => verificationStatus == 'rejected';
}

/// `POST /v1/profile`.
class ProfileSubmission {
  const ProfileSubmission({
    required this.role,
    required this.registrationBody,
    required this.registrationNumber,
    required this.consentVersion,
  });

  final String role;
  final String registrationBody;
  final String? registrationNumber;
  final String consentVersion;

  Map<String, dynamic> toJson() => {
    'role': role,
    'registration_body': registrationBody,
    'registration_number': registrationNumber,
    'consent_version': consentVersion,
  };
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
  });

  factory AdminClinician.fromJson(Map<String, dynamic> j) => AdminClinician(
    id: '${j['id']}',
    email: j['email'] as String? ?? '',
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
