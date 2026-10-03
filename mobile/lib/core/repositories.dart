/// The app's data layer. Screens and controllers call these interfaces; the
/// real implementations talk to the backend, the preview ones return samples.
library;

import 'api/api_client.dart';
import 'api/api_models.dart';
import 'demo/preview_data.dart';

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
      // The preview account is an admin so the Admin area can be reviewed.
      isAdmin: current == 'verified',
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
      role: 'psychologist',
      verificationStatus: 'pending',
      registrationBody: 'RCI',
      registrationNumber: 'A12345',
      createdAt: DateTime.now().subtract(const Duration(hours: 26)),
    ),
    AdminClinician(
      id: 'c2',
      email: 'trainee.one@example.test',
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
