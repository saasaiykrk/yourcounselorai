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

  Future<ConsultReply> consult(ConsultRequest request) async =>
      ConsultReply.fromJson(await _send('POST', '/v1/consult', body: request.toJson()));

  Future<void> reportIncident({required String turnId, required String category, required String note}) =>
      _send('POST', '/v1/incidents', body: {'turn_id': turnId, 'category': category, 'note': note});

  Future<Map<String, dynamic>> _send(String method, String path, {Map<String, dynamic>? body}) async {
    final token = await _token();
    if (token == null) throw const Unauthorized();
    try {
      final response = await _dio.request<Object?>(
        path,
        data: body,
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
    429 => const DailyLimitReached(),
    422 when detail is Map && detail['error'] == 'identifiers_detected' => IdentifiersDetected([
      for (final t in (detail['types'] as List? ?? const [])) '$t',
    ]),
    _ => ServerProblem(status),
  };
}
