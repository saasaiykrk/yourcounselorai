/// The app's data layer. Screens and controllers call these interfaces; the
/// real implementations talk to the backend, the preview ones return samples.
library;

import 'api/api_client.dart';
import 'api/api_exceptions.dart';
import 'api/api_models.dart';
import 'demo/preview_data.dart';

/// Guided consultation: case → questions → report. The server keeps the state.
abstract interface class ConsultationRepository {
  Future<Consultation> start({required String text, required Map<String, int> redactionCounts});

  Future<List<ConsultationSummary>> open();

  Future<Consultation> get(String id);

  Future<Consultation> reply(String id, {required String action, String text, required String messageId});

  Future<Consultation> editFacts(String id, Map<String, String?> facts);

  Future<(Consultation, ConsultReply)> report(String id, {bool force});
}

class ApiConsultationRepository implements ConsultationRepository {
  ApiConsultationRepository(this._api);

  final ApiClient _api;

  @override
  Future<Consultation> start({required String text, required Map<String, int> redactionCounts}) =>
      _api.startConsultation(text: text, redactionCounts: redactionCounts);

  @override
  Future<List<ConsultationSummary>> open() => _api.openConsultations();

  @override
  Future<Consultation> get(String id) => _api.consultation(id);

  @override
  Future<Consultation> reply(String id, {required String action, String text = '', required String messageId}) =>
      _api.consultationReply(id, action: action, text: text, messageId: messageId);

  @override
  Future<Consultation> editFacts(String id, Map<String, String?> facts) => _api.consultationFacts(id, facts);

  @override
  Future<(Consultation, ConsultReply)> report(String id, {bool force = false}) =>
      _api.consultationReport(id, force: force);
}

/// Preview: asks the four mandatory questions, then offers a sample report. In memory only.
class PreviewConsultationRepository implements ConsultationRepository {
  PreviewConsultationRepository({this.delay = const Duration(milliseconds: 700)});

  final Duration delay;
  static const _questions = [
    ConsultationQuestion(
      field: 'age_gender',
      question: "What is the client's age and gender?",
      why: 'Tools and guidance depend on age.',
    ),
    ConsultationQuestion(
      field: 'risk_screening',
      question: 'Has risk been screened (self-harm, wish to die, harm to others, abuse)? What was found?',
      why: 'Safety must be known before any plan.',
      options: ['Asked and absent', 'Risk present', 'Not yet asked'],
    ),
    ConsultationQuestion(
      field: 'duration_onset',
      question: 'How long has this been going on, and did it start suddenly or gradually?',
      why: 'Duration and onset shape severity and rule-outs.',
    ),
  ];
  Consultation? _c;

  Consultation _next(Map<String, String> facts, List<String> unknown, List<ConsultationExchange> transcript) {
    final asked = transcript.where((t) => t.question.isNotEmpty).length;
    final q = asked < _questions.length ? _questions[asked] : null;
    return Consultation(
      id: 'preview-consultation',
      stage: q == null ? ConsultationStage.ready : ConsultationStage.questioning,
      question: q == null
          ? null
          : ConsultationQuestion(
              field: q.field,
              question: q.question,
              why: q.why,
              options: q.options,
              number: asked + 1,
            ),
      caseType: 'Sample case (preview)',
      caseSummary: 'Sample case: ${facts['presenting_concern'] ?? ''}',
      facts: facts,
      unknown: unknown,
      infoNeeded: [
        for (final x in _questions.skip(asked))
          if (!facts.containsKey(x.field) && !unknown.contains(x.field)) x.field,
      ],
      questionsAsked: asked + (q == null ? 0 : 1),
      transcript: transcript,
    );
  }

  @override
  Future<Consultation> start({required String text, required Map<String, int> redactionCounts}) async {
    await Future<void>.delayed(delay);
    return _c = _next({'presenting_concern': text.length > 120 ? '${text.substring(0, 120)}…' : text}, [], []);
  }

  @override
  Future<List<ConsultationSummary>> open() async => [
    if (_c != null && _c!.stage != ConsultationStage.completed)
      ConsultationSummary(id: _c!.id, stage: _c!.stage, caseSummary: _c!.caseSummary, updatedAt: DateTime.now()),
  ];

  @override
  Future<Consultation> get(String id) async => _c ?? (throw const NotFound());

  @override
  Future<Consultation> reply(String id, {required String action, String text = '', required String messageId}) async {
    await Future<void>.delayed(delay);
    final c = _c ?? (throw const NotFound());
    if (action == 'finish') {
      return _c = Consultation(
        id: c.id,
        stage: ConsultationStage.ready,
        caseType: c.caseType,
        caseSummary: c.caseSummary,
        facts: c.facts,
        unknown: c.unknown,
        questionsAsked: c.questionsAsked,
        transcript: c.transcript,
      );
    }
    final q = c.question;
    final facts = {...c.facts};
    final unknown = [...c.unknown];
    final answer = switch (action) {
      'dont_know' => "(don't know)",
      'skip' => '(skipped)',
      _ => text,
    };
    if (q != null && action == 'answer') facts[q.field] = text;
    if (q != null && action != 'answer') unknown.add(q.field);
    return _c = _next(facts, unknown, [
      ...c.transcript,
      ConsultationExchange(question: q?.question ?? '', answer: answer),
    ]);
  }

  @override
  Future<Consultation> editFacts(String id, Map<String, String?> facts) async {
    final c = _c ?? (throw const NotFound());
    final next = {...c.facts};
    facts.forEach((k, v) => v == null || v.trim().isEmpty ? next.remove(k) : next[k] = v.trim());
    return _c = Consultation(
      id: c.id,
      stage: c.stage,
      question: c.question,
      caseSummary: c.caseSummary,
      facts: next,
      unknown: c.unknown,
      questionsAsked: c.questionsAsked,
      transcript: c.transcript,
    );
  }

  @override
  Future<(Consultation, ConsultReply)> report(String id, {bool force = false}) async {
    await Future<void>.delayed(delay * 3);
    final c = _c ?? (throw const NotFound());
    final reply = ConsultReply(
      turnId: 'preview-report',
      conversationId: c.id,
      delivered: true,
      text: kPreviewConsultReportMarkdown,
      skillVersion: '2.2.0',
      meta: const ReplyMeta(mode: 'R', gate: 'none', ceiling: 'Moderate', level: 'L2'),
    );
    _c = Consultation(
      id: c.id,
      stage: ConsultationStage.completed,
      facts: c.facts,
      transcript: c.transcript,
      reply: reply,
    );
    return (_c!, reply);
  }
}

abstract interface class ProfileRepository {
  Future<Me> me();

  Future<void> submit(ProfileSubmission profile);
}

abstract interface class ConsultRepository {
  Future<ConsultReply> send(ConsultRequest request);

  Future<void> report({required String turnId, required String category, required String note});
}

class ApiProfileRepository implements ProfileRepository {
  ApiProfileRepository(this._api);

  final ApiClient _api;

  @override
  Future<Me> me() => _api.me();

  @override
  Future<void> submit(ProfileSubmission profile) => _api.submitProfile(profile);
}

class ApiConsultRepository implements ConsultRepository {
  ApiConsultRepository(this._api);

  final ApiClient _api;

  @override
  Future<ConsultReply> send(ConsultRequest request) => _api.consult(request);

  @override
  Future<void> report({required String turnId, required String category, required String note}) =>
      _api.reportIncident(turnId: turnId, category: category, note: note);
}

/// Preview: walks through signup → pending → verified without a server.
class PreviewProfileRepository implements ProfileRepository {
  var _status = 'none';

  @override
  Future<Me> me() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final current = _status;
    // Each status check after submitting moves one step, so the pending screen can be tried.
    if (_status == 'pending') _status = 'verified';
    return Me(
      verificationStatus: current,
      level: current == 'verified' ? 'L2' : null,
      role: 'psychologist',
      registrationBody: 'RCI',
      fullName: current == 'none' ? null : 'Preview Clinician',
      // The preview account is an admin so the Admin area can be reviewed.
      isAdmin: current == 'verified',
      guidedConsultation: current == 'verified',
    );
  }

  @override
  Future<void> submit(ProfileSubmission profile) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _status = 'pending';
  }
}

/// Preview: returns the sample reply after a short "drafting" pause.
class PreviewConsultRepository implements ConsultRepository {
  PreviewConsultRepository({this.delay = const Duration(seconds: 4)});

  final Duration delay;
  var _turn = 0;

  @override
  Future<ConsultReply> send(ConsultRequest request) async {
    await Future<void>.delayed(delay);
    final risk = request.text.toLowerCase().contains(kPreviewRiskPhrase);
    _turn++;
    return ConsultReply(
      turnId: 'preview-turn-$_turn',
      conversationId: request.conversationId ?? 'preview-conversation',
      delivered: true,
      text: risk ? kPreviewSafetyMarkdown : kPreviewReplyMarkdown,
      skillVersion: '2.1.1',
      meta: ReplyMeta(mode: 'A', gate: risk ? 'gate1' : 'none', ceiling: risk ? 'NA' : 'Low', level: 'L2'),
    );
  }

  @override
  Future<void> report({required String turnId, required String category, required String note}) async {}
}

/// The admin area. Only shown to admins; the backend refuses everyone else.
abstract interface class AdminRepository {
  Future<List<AdminClinician>> clinicians(String status);

  Future<List<ConsultSummary>> clinicianConsults(String clinicianId);

  Future<ConsultDetail> consult(String id);

  /// Writes an admin's PDF download of one delivered reply to the audit log.
  Future<void> recordPdfDownload(String consultId, String turnId);

  Future<void> decide(String clinicianId, {required bool approve, String? level, required String note});

  Future<List<AdminIncident>> incidents(String? status);

  Future<AdminIncident> incident(String id);

  Future<void> updateIncident(String id, {required String status, required String reviewerNote});
}

class ApiAdminRepository implements AdminRepository {
  ApiAdminRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<AdminClinician>> clinicians(String status) => _api.adminClinicians(status);

  @override
  Future<List<ConsultSummary>> clinicianConsults(String clinicianId) => _api.adminClinicianConsults(clinicianId);

  @override
  Future<ConsultDetail> consult(String id) => _api.adminConsult(id);

  @override
  Future<void> recordPdfDownload(String consultId, String turnId) => _api.adminRecordPdfDownload(consultId, turnId);

  @override
  Future<void> decide(String clinicianId, {required bool approve, String? level, required String note}) =>
      _api.adminDecide(clinicianId, approve: approve, level: level, note: note);

  @override
  Future<List<AdminIncident>> incidents(String? status) => _api.adminIncidents(status);

  @override
  Future<AdminIncident> incident(String id) => _api.adminIncident(id);

  @override
  Future<void> updateIncident(String id, {required String status, required String reviewerNote}) =>
      _api.adminUpdateIncident(id, status: status, reviewerNote: reviewerNote);
}

/// Preview: invented registrations and reports, changed in memory only.
class PreviewAdminRepository implements AdminRepository {
  final _clinicians = <AdminClinician>[
    AdminClinician(
      id: 'c1',
      email: 'psychologist.two@example.test',
      fullName: 'Sample Psychologist Two',
      gender: 'male',
      age: 38,
      role: 'psychologist',
      verificationStatus: 'pending',
      registrationBody: 'RCI',
      registrationNumber: 'A12345',
      createdAt: DateTime.now().subtract(const Duration(hours: 26)),
    ),
    AdminClinician(
      id: 'c2',
      email: 'trainee.one@example.test',
      fullName: 'Sample Trainee One',
      gender: 'female',
      age: 24,
      role: 'counsellor_trainee',
      verificationStatus: 'pending',
      registrationBody: 'none',
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
    ),
  ];

  final _incidents = <AdminIncident>[
    AdminIncident(
      id: 'i1',
      source: 'inspector',
      category: 'blocked',
      status: 'open',
      note: '["MISSING_DISCLAIMER"]',
      level: 'L2',
      turnStatus: 'blocked',
      requestedMode: 'A',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      inputDeid: '34F, low mood for 3 months, poor sleep. Full plan please.',
      outputShown: 'This reply was held back by the safety check.',
      inspectorReports: const [
        {
          'passed': false,
          'blocks': ['MISSING_DISCLAIMER'],
        },
      ],
    ),
  ];

  @override
  Future<List<AdminClinician>> clinicians(String status) async =>
      _clinicians.where((c) => c.verificationStatus == status).toList();

  final _history = PreviewHistoryRepository();

  @override
  Future<List<ConsultSummary>> clinicianConsults(String clinicianId) => _history.list();

  @override
  Future<ConsultDetail> consult(String id) => _history.get(id);

  /// (consult id, turn id) of each PDF download, in order.
  final pdfDownloads = <(String, String)>[];

  @override
  Future<void> recordPdfDownload(String consultId, String turnId) async => pdfDownloads.add((consultId, turnId));

  @override
  Future<void> decide(String clinicianId, {required bool approve, String? level, required String note}) async {
    final i = _clinicians.indexWhere((c) => c.id == clinicianId);
    if (i < 0) return;
    final c = _clinicians[i];
    _clinicians[i] = AdminClinician(
      id: c.id,
      email: c.email,
      role: c.role,
      verificationStatus: approve ? 'verified' : 'rejected',
      registrationBody: c.registrationBody,
      registrationNumber: c.registrationNumber,
      level: approve ? level : null,
      verificationNote: note,
      createdAt: c.createdAt,
      fullName: c.fullName,
      gender: c.gender,
      age: c.age,
    );
  }

  @override
  Future<List<AdminIncident>> incidents(String? status) async =>
      _incidents.where((i) => status == null || i.status == status).toList();

  @override
  Future<AdminIncident> incident(String id) async => _incidents.firstWhere((i) => i.id == id);

  @override
  Future<void> updateIncident(String id, {required String status, required String reviewerNote}) async {
    final i = _incidents.indexWhere((x) => x.id == id);
    if (i < 0) return;
    final x = _incidents[i];
    _incidents[i] = AdminIncident(
      id: x.id,
      source: x.source,
      category: x.category,
      status: status,
      note: x.note,
      reviewerNote: reviewerNote,
      level: x.level,
      turnStatus: x.turnStatus,
      requestedMode: x.requestedMode,
      createdAt: x.createdAt,
      inputDeid: x.inputDeid,
      outputShown: x.outputShown,
      inspectorReports: x.inspectorReports,
    );
  }
}

/// The clinician's own past consults (read-only).
abstract interface class HistoryRepository {
  Future<List<ConsultSummary>> list({String? query, String? mode});

  Future<ConsultDetail> get(String id);

  Future<String?> label(String id, String? title);

  Future<void> delete(String id);
}

class ApiHistoryRepository implements HistoryRepository {
  ApiHistoryRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<ConsultSummary>> list({String? query, String? mode}) => _api.history(query: query, mode: mode);

  @override
  Future<ConsultDetail> get(String id) => _api.historyConsult(id);

  @override
  Future<String?> label(String id, String? title) => _api.labelConsult(id, title);

  @override
  Future<void> delete(String id) => _api.deleteConsult(id);
}

/// Preview: invented, de-identified sample consults, changed in memory only.
class PreviewHistoryRepository implements HistoryRepository {
  final _items = <ConsultDetail>[
    ConsultDetail(
      id: 'h1',
      title: 'Sleep and low mood',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      turns: [
        ConsultTurn(
          id: 'h1-1',
          level: 'L2',
          skillVersion: 'preview',
          input: '34F, low mood for 3 months, poor sleep, lost interest in work. Full plan please.',
          reply: kPreviewReplyMarkdown,
          mode: 'A',
          status: 'delivered',
          createdAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ],
    ),
    ConsultDetail(
      id: 'h2',
      createdAt: DateTime.now().subtract(const Duration(hours: 6)),
      turns: [
        ConsultTurn(
          id: 'h2-1',
          level: 'L2',
          skillVersion: 'preview',
          input: '19M, panic attacks before exams, no medical history. Quick review.',
          reply: kPreviewReplyMarkdown,
          mode: 'B',
          status: 'delivered',
          createdAt: DateTime.now().subtract(const Duration(hours: 6)),
        ),
      ],
    ),
  ];

  ConsultSummary _summary(ConsultDetail d) => ConsultSummary(
    id: d.id,
    title: d.title,
    preview: d.turns.first.input,
    turns: d.turns.length,
    modes: {for (final t in d.turns) t.mode}.toList(),
    lastStatus: d.turns.last.status,
    createdAt: d.createdAt,
    lastAt: d.turns.last.createdAt,
  );

  @override
  Future<List<ConsultSummary>> list({String? query, String? mode}) async {
    final q = query?.trim().toLowerCase() ?? '';
    final rows = _items
        .where((d) {
          final matchesQ =
              q.isEmpty ||
              (d.title ?? '').toLowerCase().contains(q) ||
              d.turns.any((t) => t.input.toLowerCase().contains(q));
          final matchesMode = mode == null || d.turns.any((t) => t.mode == mode);
          return matchesQ && matchesMode;
        })
        .map(_summary)
        .toList();
    rows.sort((a, b) => (b.lastAt ?? DateTime(0)).compareTo(a.lastAt ?? DateTime(0)));
    return rows;
  }

  @override
  Future<ConsultDetail> get(String id) async =>
      _items.firstWhere((d) => d.id == id, orElse: () => throw const NotFound());

  @override
  Future<String?> label(String id, String? title) async {
    final t = title?.trim();
    final i = _items.indexWhere((d) => d.id == id);
    final d = _items[i];
    _items[i] = ConsultDetail(
      id: d.id,
      title: t == null || t.isEmpty ? null : t,
      createdAt: d.createdAt,
      turns: d.turns,
    );
    return _items[i].title;
  }

  @override
  Future<void> delete(String id) async => _items.removeWhere((d) => d.id == id);
}
