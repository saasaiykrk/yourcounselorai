// Guided consultation: API shapes, the question-by-question flow, identifier
// checks on answers, the safety stop, and the hand-off to the report screen.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:your_counselor/core/api/api_client.dart';
import 'package:your_counselor/core/api/api_exceptions.dart';
import 'package:your_counselor/core/api/api_models.dart';
import 'package:your_counselor/core/providers.dart';
import 'package:your_counselor/core/repositories.dart';
import 'package:your_counselor/main.dart';
import 'package:your_counselor/router.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final ResponseBody Function(RequestOptions) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    requests.add(o);
    return respond(o);
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

(ApiClient, _Adapter) _api(ResponseBody Function(RequestOptions) respond) {
  final adapter = _Adapter(respond);
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter;
  return (
    ApiClient(baseUrl: 'https://api.test', token: () async => 'tok', timeout: const Duration(seconds: 5), dio: dio),
    adapter,
  );
}

/// The server's public view of a consultation (app/consultation.py public_view).
const _view = {
  'id': 'k1',
  'stage': 'QUESTIONING',
  'question': {
    'field': 'risk_screening',
    'question': 'Has risk been screened?',
    'why': 'Safety must be known before any plan.',
    'options': ['Asked and absent', 'Risk present', 'Not yet asked'],
    'number': 2,
  },
  'brief_answer': '',
  'case_summary': '9-year-old boy with rituals.',
  'facts': {'age_gender': '9, male'},
  'unknown': ['prior_therapy'],
  'questions_asked': 2,
  'max_questions': 8,
  'transcript': [
    {'field': 'age_gender', 'question': 'How old?', 'why': '', 'answer': '9, male'},
  ],
  'report': null,
};

class _Profile implements ProfileRepository {
  _Profile({this.guided = true});

  final bool guided;

  @override
  Future<Me> me() async =>
      Me(verificationStatus: 'verified', level: 'L2', role: 'psychologist', guidedConsultation: guided);

  @override
  Future<void> submit(ProfileSubmission profile) async {}
}

/// The preview flow (three mandatory questions, then a sample report), recording every call.
class _Recording extends PreviewConsultationRepository {
  _Recording() : super(delay: Duration.zero);

  final starts = <String>[];
  final steps = <(String, String)>[];
  var reports = 0;

  @override
  Future<Consultation> start({required String text, required Map<String, int> redactionCounts}) {
    starts.add(text);
    return super.start(text: text, redactionCounts: redactionCounts);
  }

  @override
  Future<Consultation> reply(String id, {required String action, String text = '', required String messageId}) {
    steps.add((action, text));
    return super.reply(id, action: action, text: text, messageId: messageId);
  }

  @override
  Future<(Consultation, ConsultReply)> report(String id, {bool force = false}) {
    reports++;
    return super.report(id, force: force);
  }
}

/// Always answers with a safety stop until safety is confirmed.
class _SafetyStopRepo extends _Recording {
  @override
  Future<Consultation> start({required String text, required Map<String, int> redactionCounts}) async =>
      const Consultation(id: 'k1', stage: ConsultationStage.safetyStop);
}

Future<void> _pump(
  WidgetTester tester,
  String location, {
  required ConsultationRepository repo,
  bool guided = true,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(_Profile(guided: guided)),
        consultationRepositoryProvider.overrideWithValue(repo),
      ],
      child: YourCounselorApp(router: buildRouter(initialLocation: location)),
    ),
  );
  await tester.pumpAndSettle();
}

/// From the Consult tab: check the sample case, tick "no identifiers", start.
Future<void> _startFromConsultTab(WidgetTester tester) async {
  await tester.tap(find.text('Check & start'));
  await tester.pumpAndSettle();
  for (final yes in find.text('Yes, remove').evaluate().toList()) {
    await tester.ensureVisible(find.byWidget(yes.widget).first);
    await tester.tap(find.byWidget(yes.widget).first);
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(find.byType(Checkbox));
  await tester.tap(find.byType(Checkbox));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Send securely'));
  await tester.pumpAndSettle();
}

Future<void> _answer(WidgetTester tester, String text) async {
  await tester.enterText(find.widgetWithText(TextField, 'Your answer'), text);
  await tester.tap(find.byTooltip('Send answer'));
  await tester.pumpAndSettle();
}

void main() {
  group('API', () {
    test('parses the server view', () {
      final c = Consultation.fromJson(_view);
      expect(c.stage, ConsultationStage.questioning);
      expect(c.question!.options, ['Asked and absent', 'Risk present', 'Not yet asked']);
      expect(c.question!.number, 2);
      expect(c.facts, {'age_gender': '9, male'});
      expect(c.unknown, ['prior_therapy']);
      expect(c.transcript.single.answer, '9, male');
      expect(ConsultationStage.fromApi('INFORMATION_SUFFICIENT'), ConsultationStage.ready);
      expect(ConsultationStage.fromApi('SAFETY_STOP'), ConsultationStage.safetyStop);
    });

    test('me reads whether guided consultation is switched on', () {
      expect(
        Me.fromJson({
          'verification_status': 'verified',
          'level': 'L2',
          'features': {'consultation': true},
        }).guidedConsultation,
        isTrue,
      );
      expect(Me.fromJson({'verification_status': 'verified', 'level': 'L2'}).guidedConsultation, isFalse);
    });

    test('start, reply and report send what the server expects', () async {
      final (api, adapter) = _api((o) {
        if (o.path.endsWith('/report')) {
          return _json(200, {
            'consultation': {..._view, 'stage': 'COMPLETED', 'question': null},
            'reply': {
              'turn_id': 't1',
              'conversation_id': 'k1',
              'status': 'delivered',
              'text': '## Consultation Report',
              'skill_version': '2.2.0',
              'report': {
                'meta': {'mode': 'R', 'gate': 'none', 'ceiling': 'Moderate', 'level': 'L2'},
              },
            },
          });
        }
        return _json(200, _view);
      });
      await api.startConsultation(text: 'cleaned case', redactionCounts: {'PHONE': 1});
      await api.consultationReply('k1', action: 'answer', text: '9, male', messageId: 'm-1');
      final (c, reply) = await api.consultationReport('k1', force: true);

      expect(adapter.requests[0].path, '/v1/consultations');
      expect(adapter.requests[0].data, {
        'text': 'cleaned case',
        'deid_attested': true,
        'client_redaction_counts': {'PHONE': 1},
      });
      expect(adapter.requests[1].path, '/v1/consultations/k1/reply');
      expect(adapter.requests[1].data, {
        'action': 'answer',
        'text': '9, male',
        'deid_attested': true,
        'client_msg_id': 'm-1',
      });
      expect(adapter.requests[2].data, {'force': true});
      expect(c.stage, ConsultationStage.completed);
      expect(reply.meta.mode, 'R');
    });

    test('409 becomes Conflict', () {
      expect(mapStatus(409, {'detail': 'more information is needed before the report'}), isA<Conflict>());
      expect(
        mapStatus(409, {
          'detail': {'error': 'busy'},
        }),
        isA<Conflict>(),
      );
    });
  });

  group('screens', () {
    testWidgets('Consult tab offers Guided only when the server has it on', (tester) async {
      await _pump(tester, '/consult', repo: _Recording(), guided: false);
      expect(find.text('Guided'), findsNothing);
      expect(find.text('Check & send'), findsOneWidget);

      await _pump(tester, '/consult', repo: _Recording());
      expect(find.text('Guided'), findsOneWidget);
      expect(find.text('Guided consultation'), findsOneWidget);
      expect(find.text('Check & start'), findsOneWidget);
      await tester.tap(find.text('Direct'));
      await tester.pumpAndSettle();
      expect(find.text('Check & send'), findsOneWidget);
    });

    testWidgets('case → questions → ready → report', (tester) async {
      final repo = _Recording();
      await _pump(tester, '/consult', repo: repo);
      await _startFromConsultTab(tester);

      // Only cleaned text reaches the server.
      expect(repo.starts.single, isNot(contains('98765')));
      expect(repo.starts.single, contains('[PHONE]'));
      expect(find.text("What is the client's age and gender?"), findsOneWidget);
      expect(find.textContaining('Why we ask'), findsOneWidget);

      await _answer(tester, '34, female');
      expect(find.textContaining('Has risk been screened'), findsOneWidget);
      await tester.tap(find.text('Asked and absent')); // quick reply
      await tester.pumpAndSettle();
      expect(find.textContaining('How long has this been going on'), findsOneWidget);
      await tester.tap(find.text("Don't know"));
      await tester.pumpAndSettle();

      expect(find.text('Your consultation is ready'), findsOneWidget);
      expect(find.textContaining('Not known: Duration and onset'), findsOneWidget);
      expect(repo.steps, [('answer', '34, female'), ('answer', 'Asked and absent'), ('dont_know', '')]);

      await tester.ensureVisible(find.text('Generate report'));
      await tester.tap(find.text('Generate report'));
      await tester.pumpAndSettle();
      expect(repo.reports, 1);
      expect(find.text('Consultation report'), findsOneWidget);
      expect(find.textContaining('GUIDED CONSULTATION'), findsOneWidget);
    });

    testWidgets('an answer with an identifier goes through the check panel first', (tester) async {
      final repo = _Recording();
      await _pump(tester, '/consult', repo: repo);
      await _startFromConsultTab(tester);

      await _answer(tester, 'Her mother can be reached on 9876543210');
      expect(find.text('Check before sending'), findsOneWidget);
      expect(repo.steps, isEmpty); // nothing sent yet
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send securely'));
      await tester.pumpAndSettle();
      expect(repo.steps.single.$2, isNot(contains('9876543210')));
      expect(repo.steps.single.$2, contains('[PHONE]'));
    });

    testWidgets('a safety stop shows the crisis numbers and waits for the clinician', (tester) async {
      final repo = _SafetyStopRepo();
      await _pump(tester, '/consult', repo: repo);
      await _startFromConsultTab(tester);

      expect(find.text('SAFETY FIRST'), findsOneWidget);
      expect(find.textContaining('14416'), findsWidgets);
      expect(find.widgetWithText(TextField, 'Your answer'), findsNothing); // no questions while paused
      await tester.ensureVisible(find.text('Immediate safety is being managed — continue'));
      await tester.tap(find.text('Immediate safety is being managed — continue'));
      await tester.pumpAndSettle();
      expect(repo.steps.single.$1, 'safety_managed');
    });

    testWidgets('generate now asks first and names what is missing', (tester) async {
      final repo = _Recording();
      await _pump(tester, '/consult', repo: repo);
      await _startFromConsultTab(tester);

      await tester.tap(find.text('Report now'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Not answered yet'), findsOneWidget);
      expect(find.textContaining('Age / gender'), findsOneWidget);
      await tester.tap(find.text('Keep answering'));
      await tester.pumpAndSettle();
      expect(repo.reports, 0);
    });

    for (final size in const [Size(360, 640), Size(390, 844)]) {
      testWidgets('consultation screens fit a ${size.width.toInt()}-wide phone', (tester) async {
        await _pump(tester, '/consult', repo: _Recording(), size: size);
        await _startFromConsultTab(tester);
        expect(tester.takeException(), isNull);
        await _answer(tester, '34, female');
        await tester.tap(find.text('Asked and absent'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Skip'));
        await tester.pumpAndSettle();
        expect(find.text('Your consultation is ready'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
