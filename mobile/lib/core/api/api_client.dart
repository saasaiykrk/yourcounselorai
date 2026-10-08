import 'package:dio/dio.dart';

import 'api_exceptions.dart';
import 'api_models.dart';

/// Returns the bearer token for the signed-in clinician, or null.
typedef TokenProvider = Future<String?> Function();

/// The only way the app talks to the Your Counselor backend.
///
/// Never logs request or response bodies: they carry case text (CLAUDE.md rule 5).
class ApiClient {
  ApiClient({required String baseUrl, required this._token, required Duration timeout, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 30),
              receiveTimeout: timeout,
              contentType: 'application/json',
              responseType: ResponseType.json,
            ),
          );

  final Dio _dio;
  final TokenProvider _token;

  Future<Me> me() async => Me.fromJson(await _send('GET', '/v1/me'));

  Future<void> submitProfile(ProfileSubmission profile) => _send('POST', '/v1/profile', body: profile.toJson());

  Future<ProfileEditResult> editProfile(ProfileEdit profile) async =>
      ProfileEditResult.fromJson(await _send('PATCH', '/v1/profile', body: profile.toJson()));

  Future<ConsultReply> consult(ConsultRequest request) async =>
      ConsultReply.fromJson(await _send('POST', '/v1/consult', body: request.toJson()));

  Future<void> reportIncident({required String turnId, required String category, required String note}) =>
      _send('POST', '/v1/incidents', body: {'turn_id': turnId, 'category': category, 'note': note});

  // --- consult history (the clinician's own) ---

  Future<List<ConsultSummary>> history({String? query, String? mode}) async {
    final q = query?.trim();
    final data = await _send('GET', '/v1/history', query: {if (q != null && q.isNotEmpty) 'q': q, 'mode': ?mode});
    return [
      for (final c in (data['consults'] as List? ?? const [])) ConsultSummary.fromJson(c as Map<String, dynamic>),
    ];
  }

  Future<ConsultDetail> historyConsult(String id) async =>
      ConsultDetail.fromJson(await _send('GET', '/v1/history/${Uri.encodeComponent(id)}'));

  /// Sets (or clears, with null/empty) a consult's label. Throws [IdentifiersDetected]
  /// when the label looks like it holds a name or other identifier.
  Future<String?> labelConsult(String id, String? title) async =>
      (await _send('PATCH', '/v1/history/${Uri.encodeComponent(id)}', body: {'title': title}))['title'] as String?;

  /// Removes a consult from History. The server keeps it for audit until retention ends.
  Future<void> deleteConsult(String id) => _send('DELETE', '/v1/history/${Uri.encodeComponent(id)}');

  // --- guided consultation (the server keeps the state; every text is cleaned on the phone first) ---

  Future<Consultation> startConsultation({required String text, required Map<String, int> redactionCounts}) async =>
      Consultation.fromJson(
        await _send(
          'POST',
          '/v1/consultations',
          // snapshot: this app shows the Case Snapshot form (CR-001) before any question.
          body: {'text': text, 'deid_attested': true, 'client_redaction_counts': redactionCounts, 'snapshot': true},
        ),
      );

  Future<List<ConsultationSummary>> openConsultations() async {
    final data = await _send('GET', '/v1/consultations');
    return [
      for (final c in (data['consultations'] as List? ?? const []))
        ConsultationSummary.fromJson(c as Map<String, dynamic>),
    ];
  }

  Future<Consultation> consultation(String id) async =>
      Consultation.fromJson(await _send('GET', '/v1/consultations/${Uri.encodeComponent(id)}'));

  /// [action]: answer · dont_know · skip · finish · safety_managed · safety_absent.
  /// The same [messageId] is never processed twice by the server.
  Future<Consultation> consultationReply(
    String id, {
    required String action,
    String text = '',
    required String messageId,
  }) async => Consultation.fromJson(
    await _send(
      'POST',
      '/v1/consultations/${Uri.encodeComponent(id)}/reply',
      body: {'action': action, 'text': text, 'deid_attested': true, 'client_msg_id': messageId},
    ),
  );

  Future<Consultation> consultationFacts(String id, Map<String, String?> facts) async => Consultation.fromJson(
    await _send('PATCH', '/v1/consultations/${Uri.encodeComponent(id)}/facts', body: {'facts': facts}),
  );

  /// Fills or corrects Case Snapshot fields. [done]: the form is complete, go on;
  /// [skipRemaining]: every empty field becomes "Skipped" and the report is next.
  /// Text values must already be cleaned on the phone.
  Future<Consultation> consultationSnapshot(
    String id,
    Map<String, SnapshotEntry> fields, {
    bool done = false,
    bool skipRemaining = false,
  }) async => Consultation.fromJson(
    await _send(
      'PATCH',
      '/v1/consultations/${Uri.encodeComponent(id)}/snapshot',
      body: {
        'fields': {for (final e in fields.entries) e.key: e.value.toJson()},
        'done': done,
        'skip_remaining': skipRemaining,
        'deid_attested': true,
      },
    ),
  );

  /// Writes the Consultation Report (or returns the one already written).
  Future<(Consultation, ConsultReply)> consultationReport(String id, {bool force = false}) async {
    final data = await _send('POST', '/v1/consultations/${Uri.encodeComponent(id)}/report', body: {'force': force});
    final reply = ConsultReply.fromJson(data['reply'] as Map<String, dynamic>);
    return (Consultation.fromJson(data['consultation'] as Map<String, dynamic>), reply);
  }

  // --- admin (the backend re-checks admin rights on every call) ---

  Future<List<ConsultSummary>> adminClinicianConsults(String clinicianId) async {
    final data = await _send('GET', '/v1/admin/clinicians/${Uri.encodeComponent(clinicianId)}/consults');
    return [
      for (final c in (data['consults'] as List? ?? const [])) ConsultSummary.fromJson(c as Map<String, dynamic>),
    ];
  }

  Future<ConsultDetail> adminConsult(String id) async =>
      ConsultDetail.fromJson(await _send('GET', '/v1/admin/consults/${Uri.encodeComponent(id)}'));

  /// Records an admin's PDF download of one delivered reply (audit log) before the phone builds it.
  Future<void> adminRecordPdfDownload(String consultId, String turnId) =>
      _send('POST', '/v1/admin/consults/${Uri.encodeComponent(consultId)}/pdf', body: {'turn_id': turnId});

  Future<List<AdminClinician>> adminClinicians(String status) async {
    final data = await _send('GET', '/v1/admin/clinicians', query: {'status': status});
    return [
      for (final c in (data['clinicians'] as List? ?? const [])) AdminClinician.fromJson(c as Map<String, dynamic>),
    ];
  }

  /// Approve ([level] required) or reject a registration. [note] says how the register was checked.
  Future<void> adminDecide(String clinicianId, {required bool approve, String? level, required String note}) => _send(
    'PATCH',
    '/v1/admin/clinicians/${Uri.encodeComponent(clinicianId)}',
    body: {
      'verification_status': approve ? 'verified' : 'rejected',
      'level': approve ? level : null,
      'evidence_note': note,
    },
  );

  Future<List<AdminIncident>> adminIncidents(String? status) async {
    final data = await _send('GET', '/v1/admin/incidents', query: {'status': ?status});
    return [
      for (final i in (data['incidents'] as List? ?? const [])) AdminIncident.fromJson(i as Map<String, dynamic>),
    ];
  }

  Future<AdminIncident> adminIncident(String id) async =>
      AdminIncident.fromJson(await _send('GET', '/v1/admin/incidents/${Uri.encodeComponent(id)}'));

  Future<void> adminUpdateIncident(String id, {required String status, required String reviewerNote}) => _send(
    'PATCH',
    '/v1/admin/incidents/${Uri.encodeComponent(id)}',
    body: {'status': status, 'reviewer_note': reviewerNote},
  );

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) async {
    final token = await _token();
    if (token == null) throw const Unauthorized();
    try {
      final response = await _dio.request<Object?>(
        path,
        data: body,
        queryParameters: query,
        options: Options(method: method, headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data;
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}

/// Turns a transport or HTTP failure into an [ApiException]. Public for tests.
ApiException mapDioException(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return const NetworkProblem(timedOut: true);
    case DioExceptionType.connectionError:
      return const NetworkProblem();
    case DioExceptionType.badResponse:
      return mapStatus(e.response?.statusCode, e.response?.data);
    case DioExceptionType.cancel:
    case DioExceptionType.badCertificate:
    case DioExceptionType.unknown:
      return e.response == null ? const NetworkProblem() : mapStatus(e.response?.statusCode, e.response?.data);
  }
}

/// Maps an HTTP status and FastAPI error body (`{"detail": …}`) to an [ApiException].
ApiException mapStatus(int? status, Object? body) {
  final detail = body is Map ? body['detail'] : null;
  return switch (status) {
    401 => const Unauthorized(),
    403 => const NotVerified(),
    404 => const NotFound(),
    409 => Conflict(detail is String ? detail : null),
    429 => const DailyLimitReached(),
    422 when detail is Map && detail['error'] == 'identifiers_detected' => IdentifiersDetected([
      for (final t in (detail['types'] as List? ?? const [])) '$t',
    ]),
    _ => ServerProblem(status),
  };
}
