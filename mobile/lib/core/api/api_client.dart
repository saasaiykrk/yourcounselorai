import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'api_exceptions.dart';
import 'api_models.dart';
import 'billing_models.dart';
import 'calendar_models.dart';
import '../education/education_repository.dart';

/// Returns the bearer token for the signed-in clinician, or null.
typedef TokenProvider = Future<String?> Function();

/// The only way the app talks to the YourCounselor backend.
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

  /// Account → Delete account. The server deletes the sign-in and personal details for good.
  Future<void> deleteAccount() => _send('POST', '/v1/account/delete', body: {'confirm': 'DELETE'});

  Future<ConsultReply> consult(ConsultRequest request) async =>
      ConsultReply.fromJson(await _send('POST', '/v1/consult', body: request.toJson()));

  /// A reply that finished on the server while the phone was disconnected; null until it is ready.
  Future<ConsultReply?> consultResult(String requestId) async {
    try {
      return ConsultReply.fromJson(await _send('GET', '/v1/consult/result/${Uri.encodeComponent(requestId)}'));
    } on NotFound {
      return null;
    }
  }

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
  /// [useOwnKey]: write it with the clinician's own Anthropic key (never falls back to the platform key).
  Future<(Consultation, ConsultReply)> consultationReport(
    String id, {
    bool force = false,
    bool useOwnKey = false,
  }) async {
    final data = await _send(
      'POST',
      '/v1/consultations/${Uri.encodeComponent(id)}/report',
      body: {'force': force, if (useOwnKey) 'use_own_key': true},
    );
    final reply = ConsultReply.fromJson(data['reply'] as Map<String, dynamic>);
    return (Consultation.fromJson(data['consultation'] as Map<String, dynamic>), reply);
  }

  // --- plans, payments and the clinician's own Anthropic key ---

  Future<BillingPlans> billingPlans() async => BillingPlans.fromJson(await _send('GET', '/v1/billing/plans'));

  Future<BillingStatus> billingStatus() async => BillingStatus.fromJson(await _send('GET', '/v1/billing/me'));

  /// Starts a purchase. The server prices it; the app never sends an amount.
  /// [item]: a single print's education page (slug).
  Future<OrderStart> createOrder({required String plan, String? reportType, String? item, String? period}) async =>
      OrderStart.fromJson(
        await _send(
          'POST',
          '/v1/billing/orders',
          body: {'plan': plan, 'report_type': reportType, 'item': ?item, 'period': ?period},
        ),
      );

  /// Checkout finished: the server checks the signature AND asks Razorpay before granting anything.
  Future<BillingOrder> verifyPayment(
    String orderId, {
    required String razorpayOrderId,
    required String paymentId,
    required String signature,
  }) async => BillingOrder.fromJson(
    (await _send(
          'POST',
          '/v1/billing/orders/${Uri.encodeComponent(orderId)}/verify',
          body: {
            'razorpay_order_id': razorpayOrderId,
            'razorpay_payment_id': paymentId,
            'razorpay_signature': signature,
          },
        ))['order']
        as Map<String, dynamic>,
  );

  Future<void> cancelOrder(String orderId) =>
      _send('POST', '/v1/billing/orders/${Uri.encodeComponent(orderId)}/cancel');

  /// One order; the server also asks Razorpay about a payment still being confirmed.
  Future<BillingOrder> order(String orderId) async => BillingOrder.fromJson(
    (await _send('GET', '/v1/billing/orders/${Uri.encodeComponent(orderId)}'))['order'] as Map<String, dynamic>,
  );

  Future<List<BillingOrder>> orders() async => [
    for (final o in ((await _send('GET', '/v1/billing/orders'))['orders'] as List? ?? const []))
      BillingOrder.fromJson(o as Map<String, dynamic>),
  ];

  Future<List<LedgerEntry>> ledger() async => [
    for (final l in ((await _send('GET', '/v1/billing/ledger'))['ledger'] as List? ?? const []))
      LedgerEntry.fromJson(l as Map<String, dynamic>),
  ];

  /// Sends the key once over TLS; the server checks it with Anthropic and stores it encrypted.
  /// Only the last 4 characters ever come back.
  Future<OwnKeyCheck> saveOwnKey(String apiKey) async =>
      OwnKeyCheck.fromJson(await _send('PUT', '/v1/billing/byok', body: {'api_key': apiKey}));

  Future<OwnKeyCheck> checkOwnKey() async => OwnKeyCheck.fromJson(await _send('POST', '/v1/billing/byok/check'));

  Future<void> removeOwnKey() => _send('DELETE', '/v1/billing/byok');

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

  // --- Education (free for every signed-in user) ---

  /// The teaching pages, each with a fresh signed link.
  Future<EducationCatalog> education() async => EducationCatalog.fromJson(await _send('GET', '/v1/education'));

  // --- calendar and online booking (the consultant's own) ---

  Future<CalendarHome> calendar() async => CalendarHome.fromJson(await _send('GET', '/v1/calendar'));

  Future<void> saveCalendarSettings(BookingSettings s) => _send('PUT', '/v1/calendar/settings', body: s.toJson());

  /// The booking page's photo: a JPEG, PNG or WebP of at most 400 KB (the server checks its bytes).
  Future<void> uploadBookingPhoto(Uint8List image) =>
      _send('PUT', '/v1/calendar/photo', body: {'image': base64Encode(image)});

  Future<void> removeBookingPhoto() => _send('DELETE', '/v1/calendar/photo');

  /// The saved photo, or null if there is none.
  Future<Uint8List?> bookingPhoto() async {
    final token = await _token();
    if (token == null) throw const Unauthorized();
    try {
      final r = await _dio.get<List<int>>(
        '/v1/calendar/photo',
        options: Options(responseType: ResponseType.bytes, headers: {'Authorization': 'Bearer $token'}),
      );
      return r.data == null ? null : Uint8List.fromList(r.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw mapDioException(e);
    }
  }

  Future<void> saveAvailability(List<WorkWindow> windows) => _send(
    'PUT',
    '/v1/calendar/availability',
    body: {
      'windows': [for (final w in windows) w.toJson()],
    },
  );

  /// Whole days off, [from]–[to] inclusive, in the consultant's timezone. Returns how many existing
  /// appointments fall inside (they are kept; the consultant decides).
  Future<int> addTimeOff({required DateTime from, required DateTime to, String label = ''}) async => _intOf(
    (await _send(
      'POST',
      '/v1/calendar/time-off',
      body: {'date_from': isoDate(from), 'date_to': isoDate(to), 'label': label},
    ))['conflicts'],
  );

  Future<void> deleteTimeOff(int id) => _send('DELETE', '/v1/calendar/time-off/$id');

  Future<List<Appointment>> appointments(DateTime start, DateTime end) async => [
    for (final a
        in ((await _send(
                  'GET',
                  '/v1/calendar/appointments',
                  query: {'start': isoDate(start), 'end': isoDate(end)},
                ))['appointments']
                as List? ??
            const []))
      Appointment.fromJson(a as Map<String, dynamic>),
  ];

  /// Free times from [start] for [days] days ([ignore]: the appointment being moved).
  Future<List<FreeDay>> freeSlots(DateTime start, {int days = 7, String? ignore}) async => [
    for (final d
        in ((await _send(
                  'GET',
                  '/v1/calendar/slots',
                  query: {'start': isoDate(start), 'days': days, 'ignore': ?ignore},
                ))['days']
                as List? ??
            const []))
      FreeDay.fromJson(d as Map<String, dynamic>),
  ];

  /// [startsLocal]: a wall time in the consultant's timezone, "2026-10-13T18:00".
  Future<Appointment> addAppointment({
    required String startsLocal,
    String? firstName,
    String? email,
    String? tag,
  }) async => Appointment.fromJson(
    (await _send(
          'POST',
          '/v1/calendar/appointments',
          body: {'starts_local': startsLocal, 'first_name': ?firstName, 'email': ?email, 'tag': ?tag},
        ))['appointment']
        as Map<String, dynamic>,
  );

  /// First Session · Follow-up · Online, or null to clear it.
  Future<Appointment> setAppointmentTag(String id, String? tag) async => Appointment.fromJson(
    (await _send('PUT', '/v1/calendar/appointments/${Uri.encodeComponent(id)}/tag', body: {'tag': tag}))['appointment']
        as Map<String, dynamic>,
  );

  Future<Appointment> rescheduleAppointment(
    String id, {
    required String startsLocal,
    bool outsideHours = false,
  }) async => Appointment.fromJson(
    (await _send(
          'POST',
          '/v1/calendar/appointments/${Uri.encodeComponent(id)}/reschedule',
          body: {'starts_local': startsLocal, 'outside_hours': outsideHours},
        ))['appointment']
        as Map<String, dynamic>,
  );

  /// [action]: confirm · reject · cancel · complete.
  Future<Appointment> appointmentAction(String id, String action) async => Appointment.fromJson(
    (await _send('POST', '/v1/calendar/appointments/${Uri.encodeComponent(id)}/$action'))['appointment']
        as Map<String, dynamic>,
  );

  static int _intOf(Object? v) => (v as num?)?.toInt() ?? 0;

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
  final error = detail is Map ? detail['error'] as String? : null;
  final message = detail is Map ? detail['message'] as String? : null;
  if (status == 402 && error == 'payment_required') {
    return PaymentRequired(
      message: message ?? 'You have no report credits left.',
      reportType: detail['report_type'] as String?,
      plan: detail['plan'] as String?,
      price: (detail['price'] as num?)?.toInt(),
      currency: detail['currency'] as String? ?? 'INR',
    );
  }
  if (status == 402 && error == 'plan_required') {
    return PlanRequired(
      feature: detail['feature'] as String? ?? '',
      message: message ?? 'Your plan does not include this. See the plans.',
      plan: detail['plan'] as String?,
      price: (detail['price'] as num?)?.toInt(),
    );
  }
  if (status == 424 && error == 'byok_failed') {
    return OwnKeyFailed(
      code: detail['code'] as String? ?? 'provider_error',
      message: message ?? 'Your Anthropic API key could not be used.',
      retry: detail['retry'] == true,
    );
  }
  if (error != null && message != null && error != 'identifiers_detected') {
    return BillingRefused(code: (detail['code'] as String?) ?? error, message: message, status: status);
  }
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
