// ApiClient against a fake HTTP layer: request shape, auth header, and how
// every backend error becomes the right ApiException.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:your_counselor/core/api/api_client.dart';
import 'package:your_counselor/core/api/api_exceptions.dart';
import 'package:your_counselor/core/api/api_models.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

(ApiClient, _FakeAdapter) _client(ResponseBody Function(RequestOptions) respond, {String? token = 'tok'}) {
  final adapter = _FakeAdapter(respond);
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter;
  return (
    ApiClient(baseUrl: 'https://api.test', token: () async => token, timeout: const Duration(seconds: 5), dio: dio),
    adapter,
  );
}

const _request = ConsultRequest(text: '34F, low mood', mode: 'A', redactionCounts: {'PHONE': 1});

void main() {
  test('consult sends the cleaned text, attestation and bearer token', () async {
    final (api, adapter) = _client(
      (_) => _json(200, {
        'turn_id': 't1',
        'conversation_id': 'c1',
        'status': 'delivered',
        'text': '### 1. Audit\nBody',
        'skill_version': '2.1.1',
        'report': {
          'passed': true,
          'meta': {'mode': 'A', 'gate': 'none', 'ceiling': 'Low', 'level': 'L2'},
        },
      }),
    );
    final reply = await api.consult(_request);

    final req = adapter.requests.single;
    expect(req.path, '/v1/consult');
    expect(req.method, 'POST');
    expect(req.headers['Authorization'], 'Bearer tok');
    final body = req.data as Map<String, dynamic>;
    expect(body['text'], '34F, low mood');
    expect(body['deid_attested'], isTrue);
    expect(body['client_redaction_counts'], {'PHONE': 1});
    expect(body.containsKey('level'), isFalse, reason: 'the level only ever comes from the server');

    expect(reply.delivered, isTrue);
    expect(reply.conversationId, 'c1');
    expect(reply.meta.ceiling, 'Low');
    expect(reply.meta.isSafetyGate, isFalse);
  });

  test('no token means signed out, without calling the server', () async {
    final (api, adapter) = _client((_) => _json(200, {}), token: null);
    await expectLater(api.me(), throwsA(isA<Unauthorized>()));
    expect(adapter.requests, isEmpty);
  });

  final cases = <String, (int, Object, Matcher)>{
    '401': (401, {'detail': 'invalid token'}, isA<Unauthorized>()),
    '403': (403, {'detail': 'registration not yet verified'}, isA<NotVerified>()),
    '404': (404, {'detail': 'conversation not found'}, isA<NotFound>()),
    '429': (429, {'detail': 'daily limit reached'}, isA<DailyLimitReached>()),
    '500': (500, {'detail': 'boom'}, isA<ServerProblem>()),
    '422 attestation': (422, {'detail': 'de-identification attestation required'}, isA<ServerProblem>()),
  };
  for (final c in cases.entries) {
    test('HTTP ${c.key} maps correctly', () async {
      final (api, _) = _client((_) => _json(c.value.$1, c.value.$2));
      await expectLater(api.consult(_request), throwsA(c.value.$3));
    });
  }

  test('422 identifiers_detected carries the types only', () async {
    final (api, _) = _client(
      (_) => _json(422, {
        'detail': {
          'error': 'identifiers_detected',
          'types': ['PHONE', 'NAME'],
        },
      }),
    );
    await expectLater(
      api.consult(_request),
      throwsA(isA<IdentifiersDetected>().having((e) => e.types, 'types', ['PHONE', 'NAME'])),
    );
  });

  test('timeouts and lost connections are network problems', () {
    DioException ex(DioExceptionType t) => DioException(requestOptions: RequestOptions(), type: t);
    expect(
      mapDioException(ex(DioExceptionType.receiveTimeout)),
      isA<NetworkProblem>().having((e) => e.timedOut, 't', true),
    );
    expect(
      mapDioException(ex(DioExceptionType.connectionError)),
      isA<NetworkProblem>().having((e) => e.timedOut, 't', false),
    );
  });

  test('gate replies are recognised', () {
    expect(const ReplyMeta(gate: 'gate1').isSafetyGate, isTrue);
    expect(const ReplyMeta(gate: 'none').isSafetyGate, isFalse);
    expect(const ReplyMeta().isSafetyGate, isFalse);
  });

  test('me parses verification status and level', () {
    final me = Me.fromJson({'verification_status': 'verified', 'level': 'L2', 'role': 'psychologist'});
    expect(me.isVerified, isTrue);
    expect(Me.fromJson({'id': 'x', 'verification_status': 'none'}).needsProfile, isTrue);
  });
}
