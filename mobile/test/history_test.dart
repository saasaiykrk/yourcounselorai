// Consult history: the clinician's own past consults (search, filter, open,
// label, delete), the admin consult views, and the API request shapes.
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

/// Preview history, but labels with digits are refused like the server does.
class _History extends PreviewHistoryRepository {
  @override
  Future<String?> label(String id, String? title) async {
    if (title != null && RegExp(r'\d{6,}').hasMatch(title)) throw const IdentifiersDetected(['PHONE']);
    return super.label(id, title);
  }
}

class _Profile implements ProfileRepository {
  @override
  Future<Me> me() async => const Me(verificationStatus: 'verified', level: 'L2', role: 'psychologist', isAdmin: true);

  @override
  Future<void> submit(ProfileSubmission profile) async {}
}

Future<void> _pump(WidgetTester tester, String location, {HistoryRepository? history, Size? size}) async {
  tester.view.physicalSize = (size ?? const Size(390, 844)) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(_Profile()),
        historyRepositoryProvider.overrideWithValue(history ?? _History()),
        adminRepositoryProvider.overrideWithValue(PreviewAdminRepository()),
      ],
      child: YourCounselorApp(router: buildRouter(initialLocation: location)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('API', () {
    test('history sends the search and mode as query parameters, and only when set', () async {
      final (api, adapter) = _api((_) => _json(200, {'consults': []}));
      await api.history(query: '  panic ', mode: 'B');
      await api.history();
      expect(adapter.requests[0].path, '/v1/history');
      expect(adapter.requests[0].queryParameters, {'q': 'panic', 'mode': 'B'});
      expect(adapter.requests[1].queryParameters, isEmpty);
    });

    test('label and delete use PATCH and DELETE on the consult', () async {
      final (api, adapter) = _api((_) => _json(200, {'ok': true, 'title': 'exam review'}));
      expect(await api.labelConsult('c1', 'exam review'), 'exam review');
      await api.deleteConsult('c1');
      expect(adapter.requests[0].method, 'PATCH');
      expect(adapter.requests[0].data, {'title': 'exam review'});
      expect(adapter.requests[1].method, 'DELETE');
      expect(adapter.requests[1].path, '/v1/history/c1');
    });

    test('a refused label surfaces as IdentifiersDetected', () async {
      final (api, _) = _api(
        (_) => _json(422, {
          'detail': {
            'error': 'identifiers_detected',
            'types': ['POSSIBLE_NAME'],
          },
        }),
      );
      await expectLater(api.labelConsult('c1', 'x'), throwsA(isA<IdentifiersDetected>()));
    });

    test('summaries and details parse', () {
      final s = ConsultSummary.fromJson({
        'id': 'c1',
        'title': null,
        'preview': '34F low mood',
        'turns': 2,
        'modes': ['A', 'B'],
        'last_status': 'delivered',
        'last_at': '2026-10-03T10:00:00+00:00',
      });
      expect(s.turns, 2);
      expect(s.modes, ['A', 'B']);
      expect(s.title, isNull);
      final d = ConsultDetail.fromJson({
        'id': 'c1',
        'turns': [
          {'input_deid': 'case', 'output_shown': '### 1. Audit', 'requested_mode': 'A', 'status': 'blocked'},
        ],
      });
      expect(d.turns.single.delivered, isFalse);
    });
  });

  group('History tab', () {
    testWidgets('is in the bottom bar and lists past consults, newest first', (tester) async {
      await _pump(tester, '/consult');
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.text('Your past consults. Only you can see them.'), findsOneWidget);
      final panic = tester.getTopLeft(find.textContaining('panic attacks')).dy;
      final sleep = tester.getTopLeft(find.text('Sleep and low mood')).dy;
      expect(panic, lessThan(sleep), reason: 'newest first');
    });

    testWidgets('search and mode filter', (tester) async {
      await _pump(tester, '/history');
      await tester.enterText(find.byType(TextField), 'panic');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.textContaining('panic attacks'), findsOneWidget);
      expect(find.text('Sleep and low mood'), findsNothing);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Full plan'));
      await tester.pumpAndSettle();
      expect(find.text('Sleep and low mood'), findsOneWidget);
      expect(find.textContaining('panic attacks'), findsNothing);

      await tester.enterText(find.byType(TextField), 'nothing like this');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('No consults match.'), findsOneWidget);
    });

    testWidgets('open a consult, label it (identifiers refused), then delete it', (tester) async {
      final history = _History();
      await _pump(tester, '/history', history: history);
      await tester.tap(find.textContaining('panic attacks'));
      await tester.pumpAndSettle();
      expect(find.textContaining('19M, panic attacks'), findsOneWidget, reason: 'case as sent');

      // Label with a phone number is refused, with an explanation.
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add or change label'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Label'), 'call 9876543210');
      await tester.tap(find.text('Save label'));
      await tester.pumpAndSettle();
      expect(find.textContaining('This looks like it contains phone number'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Label'), 'exam panic review');
      await tester.tap(find.text('Save label'));
      await tester.pumpAndSettle();
      expect(find.text('exam panic review'), findsOneWidget, reason: 'shown as the title');

      // Delete, with confirmation.
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete from history'));
      await tester.pumpAndSettle();
      expect(find.textContaining('12-month retention'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('History'), findsWidgets, reason: 'back on the list');
      expect(find.text('exam panic review'), findsNothing);
      expect((await history.list()).map((c) => c.id), ['h1']);
    });

    for (final size in [const Size(320, 640), const Size(360, 640)]) {
      testWidgets('fits on a ${size.width.toInt()}px phone', (tester) async {
        await _pump(tester, '/history', size: size);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Sleep and low mood'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('admin', () {
    testWidgets('verified clinicians have a Consults button; the consult view shows the audit notice', (tester) async {
      final admin = PreviewAdminRepository();
      final pending = await admin.clinicians('pending');
      await admin.decide(pending.first.id, approve: true, level: 'L2', note: 'RCI register');
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileRepositoryProvider.overrideWithValue(_Profile()),
            adminRepositoryProvider.overrideWithValue(admin),
          ],
          child: YourCounselorApp(router: buildRouter(initialLocation: '/admin')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(TabBar), matching: find.text('Registrations')));
      await tester.pumpAndSettle();
      expect(find.text('Consults'), findsNothing, reason: 'not for pending registrations');
      await tester.tap(find.text('Verified'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Consults'));
      await tester.pumpAndSettle();
      expect(find.textContaining('recorded in the audit log'), findsOneWidget);
      await tester.tap(find.text('Sleep and low mood'));
      await tester.pumpAndSettle();
      expect(find.textContaining('34F, low mood'), findsOneWidget);
      expect(find.textContaining('recorded in the audit log'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
