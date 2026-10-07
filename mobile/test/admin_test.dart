// Admin area: API request shapes, the approve / triage flows, and that only
// admins see the way in.
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

class _Profile implements ProfileRepository {
  _Profile({required this.admin});

  final bool admin;

  @override
  Future<Me> me() async => Me(verificationStatus: 'verified', level: 'L3', role: 'psychologist', isAdmin: admin);

  @override
  Future<void> submit(ProfileSubmission profile) async {}

  @override
  Future<ProfileEditResult> edit(ProfileEdit profile) async =>
      const ProfileEditResult(verificationStatus: 'verified', reverify: false);
}

Future<void> _pump(WidgetTester tester, String location, {required bool admin, AdminRepository? repo}) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(_Profile(admin: admin)),
        adminRepositoryProvider.overrideWithValue(repo ?? PreviewAdminRepository()),
      ],
      child: YourCounselorApp(router: buildRouter(initialLocation: location)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String name) async {
  await tester.tap(find.descendant(of: find.byType(TabBar), matching: find.text(name)));
  await tester.pumpAndSettle();
}

void main() {
  group('API', () {
    test('lists pending registrations with the status as a query parameter', () async {
      final (api, adapter) = _api(
        (_) => _json(200, {
          'clinicians': [
            {
              'id': 'c1',
              'email': 'a@example.test',
              'role': 'psychologist',
              'verification_status': 'pending',
              'registration_body': 'RCI',
              'registration_number': 'A1',
              'created_at': '2026-10-03T10:00:00+00:00',
            },
          ],
        }),
      );
      final list = await api.adminClinicians('pending');
      expect(adapter.requests.single.path, '/v1/admin/clinicians');
      expect(adapter.requests.single.queryParameters, {'status': 'pending'});
      expect(adapter.requests.single.headers['Authorization'], 'Bearer tok');
      expect(list.single.email, 'a@example.test');
      expect(list.single.createdAt, isNotNull);
    });

    test('approve sends the level and the evidence note; reject sends no level', () async {
      final (api, adapter) = _api((_) => _json(200, {'ok': true}));
      await api.adminDecide('c1', approve: true, level: 'L2', note: 'RCI register');
      await api.adminDecide('c2', approve: false, note: 'Not on register');
      expect(adapter.requests[0].method, 'PATCH');
      expect(adapter.requests[0].path, '/v1/admin/clinicians/c1');
      expect(adapter.requests[0].data, {
        'verification_status': 'verified',
        'level': 'L2',
        'evidence_note': 'RCI register',
      });
      expect((adapter.requests[1].data as Map)['level'], isNull);
      expect((adapter.requests[1].data as Map)['verification_status'], 'rejected');
    });

    test('"All" reports sends no status filter', () async {
      final (api, adapter) = _api((_) => _json(200, {'incidents': []}));
      await api.adminIncidents(null);
      expect(adapter.requests.single.queryParameters, isEmpty);
    });

    test('non-admins get NotVerified (403)', () async {
      final (api, _) = _api((_) => _json(403, {'detail': 'admin only'}));
      await expectLater(api.adminClinicians('pending'), throwsA(isA<NotVerified>()));
    });

    test('me reads the admin flag', () {
      expect(Me.fromJson({'verification_status': 'verified', 'level': 'L3', 'is_admin': true}).isAdmin, isTrue);
      expect(Me.fromJson({'verification_status': 'verified', 'level': 'L3'}).isAdmin, isFalse);
    });
  });

  group('screens', () {
    testWidgets('Account shows the Admin link only to admins', (tester) async {
      await _pump(tester, '/account', admin: false);
      expect(find.textContaining('Admin:'), findsNothing);
      await _pump(tester, '/account', admin: true);
      expect(find.textContaining('Admin:'), findsOneWidget);
    });

    testWidgets('overview counts what needs attention and opens the right list', (tester) async {
      await _pump(tester, '/admin', admin: true);
      expect(find.text('Waiting for approval'), findsWidgets);
      expect(find.text('Open reports'), findsWidgets);
      expect(find.text('Verified clinicians'), findsOneWidget);
      // Two sample registrations wait; one sample report was held back automatically.
      expect(find.text('2'), findsWidgets);
      await tester.tap(find.text('Verified clinicians'));
      await tester.pumpAndSettle();
      expect(find.text('Search name, email or registration no.'), findsOneWidget);
      expect(find.text('None yet.'), findsOneWidget, reason: 'opened on Verified');
    });

    testWidgets('registrations can be searched', (tester) async {
      await _pump(tester, '/admin', admin: true);
      await _openTab(tester, 'Registrations');
      await tester.enterText(find.byType(TextField), 'A12345');
      await tester.pump();
      expect(find.text('Sample Psychologist Two'), findsOneWidget);
      expect(find.text('Sample Trainee One'), findsNothing);
      await tester.enterText(find.byType(TextField), 'nobody');
      await tester.pump();
      expect(find.textContaining('No registrations match'), findsOneWidget);
    });

    testWidgets('approve a registration with a level and a note', (tester) async {
      final repo = PreviewAdminRepository();
      await _pump(tester, '/admin', admin: true, repo: repo);
      await _openTab(tester, 'Registrations');
      expect(find.text('Sample Psychologist Two'), findsOneWidget);
      expect(find.text('psychologist.two@example.test'), findsOneWidget);
      expect(find.text('Male · 38 yrs'), findsOneWidget);
      expect(find.text('Sample Trainee One'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Approve').first);
      await tester.pumpAndSettle();
      // A note is required.
      await tester.tap(find.text('Approve as L2'));
      await tester.pumpAndSettle();
      expect(find.text('Say how you checked the registration.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'RCI register, 3 Oct 2026');
      await tester.tap(find.text('Approve as L2'));
      await tester.pumpAndSettle();

      expect(find.text('Sample Psychologist Two'), findsNothing, reason: 'no longer waiting');
      expect((await repo.clinicians('verified')).single.level, 'L2');
      expect(tester.takeException(), isNull);
    });

    testWidgets('change the level of a verified clinician, with a reason', (tester) async {
      final repo = PreviewAdminRepository();
      final pending = await repo.clinicians('pending');
      final psych = pending.firstWhere((c) => c.role == 'psychologist');
      await repo.decide(psych.id, approve: true, level: 'L2', note: 'RCI register');
      await _pump(tester, '/admin', admin: true, repo: repo);
      await _openTab(tester, 'Registrations');
      await tester.tap(find.text('Verified'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Change level'));
      await tester.tap(find.text('Change level'));
      await tester.pumpAndSettle();
      expect(find.text('Change level · now L2'), findsOneWidget);
      // The same level is not a change.
      await tester.enterText(find.byType(TextField).last, 'Now a consultant psychiatrist');
      await tester.tap(find.text('Change to L2'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a different level.'), findsOneWidget);

      await tester.tap(find.text('L3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change to L3'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Level changed to L3'), findsOneWidget);
      expect((await repo.clinicians('verified')).single.level, 'L3');
      expect(tester.takeException(), isNull);
    });

    testWidgets('reject needs no level', (tester) async {
      final repo = PreviewAdminRepository();
      await _pump(tester, '/admin', admin: true, repo: repo);
      await _openTab(tester, 'Registrations');
      await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Reject').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Reject').last);
      await tester.pumpAndSettle();
      expect(find.text('Level'), findsNothing);
      await tester.enterText(find.byType(TextField).last, 'Not on the register');
      await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
      await tester.pumpAndSettle();
      expect((await repo.clinicians('rejected')).single.level, isNull);
    });

    testWidgets('triage a report: open it, set a status and a note, save', (tester) async {
      final repo = PreviewAdminRepository();
      await _pump(tester, '/admin', admin: true, repo: repo);
      await _openTab(tester, 'Reports');
      await tester.tap(find.text('Held back by safety check'));
      await tester.pumpAndSettle();

      expect(find.text('Case as sent (de-identified)'), findsOneWidget);
      expect(find.textContaining('34F, low mood'), findsOneWidget);
      // Safety-check results are shown readably, not as raw JSON.
      expect(find.text('MISSING_DISCLAIMER'), findsOneWidget);
      expect(find.text('Show raw report'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Your review'), 200, scrollable: find.byType(Scrollable).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Triaged').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Disclaimer missing on retry');
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Save review'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save review'));
      await tester.pumpAndSettle();

      expect(find.text('Saved as Triaged.'), findsOneWidget);
      final saved = await repo.incident('i1');
      expect(saved.status, 'triaged');
      expect(saved.reviewerNote, 'Disclaimer missing on retry');
    });

    for (final size in [const Size(360, 640), const Size(320, 640)]) {
      testWidgets('admin lists fit on a ${size.width.toInt()}px phone', (tester) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              profileRepositoryProvider.overrideWithValue(_Profile(admin: true)),
              adminRepositoryProvider.overrideWithValue(PreviewAdminRepository()),
            ],
            child: YourCounselorApp(router: buildRouter(initialLocation: '/admin')),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _openTab(tester, 'Registrations');
        expect(tester.takeException(), isNull);
        await _openTab(tester, 'Reports');
        expect(tester.takeException(), isNull);
      });
    }
  });
}
