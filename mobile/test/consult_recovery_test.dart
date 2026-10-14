// The app lost its connection while a report was being written (for example, it went to the
// background): it must pick up the finished reply instead of showing "can't be reached", and must
// never start (and pay for) a second report for the same request.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:your_counselor/core/api/api_client.dart';
import 'package:your_counselor/core/api/api_exceptions.dart';
import 'package:your_counselor/core/api/api_models.dart';
import 'package:your_counselor/core/content/safety_content.dart';
import 'package:your_counselor/core/providers.dart';
import 'package:your_counselor/core/repositories.dart';
import 'package:your_counselor/features/consult/consult_controller.dart';
import 'package:your_counselor/features/consultation/consultation_controller.dart';

const _reply = ConsultReply(
  turnId: 'turn-1',
  conversationId: 'conv-1',
  delivered: true,
  text: 'MODE: A | the report',
  skillVersion: '2.1.1',
  meta: ReplyMeta(mode: 'A', gate: 'none', ceiling: 'Low', level: 'L2'),
);

class _Flaky implements ConsultRepository {
  _Flaky({required this.sendError, this.readyAfter, this.resultError});

  final ApiException sendError;
  final int? readyAfter; // the reply is ready on this poll (null: never)
  final ApiException? resultError;
  final sent = <String>[];
  final polled = <String>[];

  @override
  Future<ConsultReply> send(ConsultRequest request) async {
    sent.add(request.requestId!);
    throw sendError;
  }

  @override
  Future<ConsultReply?> result(String requestId) async {
    polled.add(requestId);
    if (resultError != null) throw resultError!;
    return readyAfter != null && polled.length >= readyAfter! ? _reply : null;
  }

  @override
  Future<void> report({required String turnId, required String category, required String note}) async {}
}

ProviderContainer _container(ConsultRepository repo, {Duration within = const Duration(seconds: 2)}) {
  final c = ProviderContainer(
    overrides: [
      consultRepositoryProvider.overrideWithValue(repo),
      consultRecoveryProvider.overrideWithValue((within: within, every: const Duration(milliseconds: 10))),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> _send(ProviderContainer c) => c
    .read(consultControllerProvider.notifier)
    .send(text: '34F, panic attacks.', mode: ConsultMode.auto, redactionCounts: const {});

void main() {
  test('a dropped connection picks up the finished reply, with no second report', () async {
    final repo = _Flaky(sendError: const NetworkProblem(), readyAfter: 3);
    final c = _container(repo);
    await _send(c);
    final state = c.read(consultControllerProvider);
    expect(state, isA<ConsultReplied>());
    expect((state as ConsultReplied).reply.text, 'MODE: A | the report');
    expect(repo.sent, hasLength(1), reason: 'never sent (or charged) twice');
    expect(repo.polled.toSet(), {repo.sent.single}, reason: 'looked up by the same request id');
  });

  test('a timed-out request is recovered the same way', () async {
    final repo = _Flaky(sendError: const NetworkProblem(timedOut: true), readyAfter: 1);
    final c = _container(repo);
    await _send(c);
    expect(c.read(consultControllerProvider), isA<ConsultReplied>());
  });

  test('if the reply never arrives, the connection problem is shown as before', () async {
    final repo = _Flaky(sendError: const NetworkProblem());
    final c = _container(repo, within: const Duration(milliseconds: 60));
    await _send(c);
    final state = c.read(consultControllerProvider);
    expect(state, isA<ConsultFailed>());
    expect((state as ConsultFailed).error, isA<NetworkProblem>());
    expect(repo.polled, isNotEmpty);
  });

  test('other errors are shown at once, without looking for a reply', () async {
    final repo = _Flaky(sendError: const DailyLimitReached());
    final c = _container(repo);
    await _send(c);
    expect((c.read(consultControllerProvider) as ConsultFailed).error, isA<DailyLimitReached>());
    expect(repo.polled, isEmpty);
  });

  test('a sign-in problem while looking stops the search', () async {
    final repo = _Flaky(sendError: const NetworkProblem(), resultError: const Unauthorized());
    final c = _container(repo);
    await _send(c);
    expect(c.read(consultControllerProvider), isA<ConsultFailed>());
    expect(repo.polled, hasLength(1));
  });

  test('guided report: a dropped connection picks up the saved report', () async {
    final repo = _Guided(readyAfter: 2);
    final c = ProviderContainer(
      overrides: [
        consultationRepositoryProvider.overrideWithValue(repo),
        consultRecoveryProvider.overrideWithValue((
          within: const Duration(seconds: 2),
          every: const Duration(milliseconds: 10),
        )),
      ],
    );
    addTearDown(c.dispose);
    final ctl = c.read(consultationControllerProvider.notifier);
    await ctl.resume('g1');
    final reply = await ctl.generateReport();
    expect(reply?.text, 'MODE: A | the report');
    expect(repo.reports, 1, reason: 'never asked to write (or pay for) a second report');
    expect(c.read(consultationControllerProvider).error, isNull);
  });

  test('API: the result is fetched by request id; not ready is null', () async {
    final seen = <String>[];
    var ready = false;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = _Adapter((o) {
        seen.add('${o.method} ${o.path}');
        return ready
            ? _json(200, {
                'turn_id': 't1',
                'conversation_id': 'c1',
                'status': 'delivered',
                'text': 'MODE: A | x',
                'skill_version': '2.1.1',
                'report': {'passed': true},
              })
            : _json(404, {'detail': 'not ready'});
      });
    final api = ApiClient(
      baseUrl: 'https://api.test',
      token: () async => 'tok',
      timeout: const Duration(seconds: 5),
      dio: dio,
    );
    expect(await api.consultResult('abc12345-x'), isNull);
    ready = true;
    expect((await api.consultResult('abc12345-x'))!.conversationId, 'c1');
    expect(seen, ['GET /v1/consult/result/abc12345-x', 'GET /v1/consult/result/abc12345-x']);
  });
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final ResponseBody Function(RequestOptions) respond;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async => respond(o);

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

/// Guided consultation whose report call loses its connection; the report is saved on the server.
class _Guided implements ConsultationRepository {
  _Guided({required this.readyAfter});

  final int readyAfter;
  int reports = 0;
  int gets = 0;

  Consultation _c({bool done = false}) => Consultation(
    id: 'g1',
    stage: done ? ConsultationStage.completed : ConsultationStage.ready,
    caseSummary: 'case',
    reply: done ? _reply : null,
  );

  @override
  Future<Consultation> get(String id) async {
    gets++;
    return _c(done: gets > readyAfter);
  }

  @override
  Future<(Consultation, ConsultReply)> report(String id, {bool force = false, bool useOwnKey = false}) async {
    reports++;
    throw const NetworkProblem();
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}
