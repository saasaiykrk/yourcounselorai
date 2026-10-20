// Account → Delete account: what goes and what stays, a typed DELETE, then the server call,
// sign-out and the welcome screen. An admin is told why not; nothing happens without the typed word.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:your_counselor/core/api/api_client.dart';
import 'package:your_counselor/core/api/api_exceptions.dart';
import 'package:your_counselor/core/api/api_models.dart';
import 'package:your_counselor/core/auth/auth_service.dart';
import 'package:your_counselor/core/providers.dart';
import 'package:your_counselor/core/repositories.dart';
import 'package:your_counselor/main.dart';
import 'package:your_counselor/router.dart';

class _Profile implements ProfileRepository {
  _Profile([this.status = 'verified']);

  final String status;

  @override
  Future<Me> me() async => Me(
    verificationStatus: status,
    level: status == 'verified' ? 'L2' : null,
    role: 'psychologist',
    registrationBody: 'RCI',
    fullName: 'Dr Test',
  );

  @override
  Future<void> submit(ProfileSubmission profile) async {}

  @override
  Future<ProfileEditResult> edit(ProfileEdit profile) async => throw UnimplementedError();
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);

  final int status;
  final Object body;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _, Future<void>? _) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<(GoRouter, DevAuthService)> _pump(
  WidgetTester tester,
  Future<void> Function() delete, {
  String status = 'verified',
  String from = '/account',
}) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final auth = DevAuthService('dev-L2');
  await auth.verifyCode('a@b.c', '123456');
  final router = buildRouter(initialLocation: from);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(_Profile(status)),
        authServiceProvider.overrideWithValue(auth),
        deleteAccountProvider.overrideWithValue(delete),
      ],
      child: YourCounselorApp(router: router),
    ),
  );
  await tester.pumpAndSettle();
  return (router, auth);
}

Finder get _button => find.byKey(const ValueKey('delete-account'));

bool _enabled(WidgetTester tester) => tester.widget<FilledButton>(_button).onPressed != null;

Future<void> _open(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text('Delete account'), 200);
  await tester.tap(find.text('Delete account'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('says what goes and what stays; only a typed DELETE deletes, then signs out', (tester) async {
    var calls = 0;
    final (router, auth) = await _pump(tester, () async => calls++);
    await _open(tester);
    expect(find.text('What is deleted'), findsOneWidget);
    expect(find.text('What is kept'), findsOneWidget);
    expect(find.textContaining('tax law'), findsOneWidget);

    expect(_enabled(tester), isFalse);
    await tester.enterText(find.byKey(const ValueKey('delete-confirm')), 'delete it');
    await tester.pump();
    expect(_enabled(tester), isFalse, reason: 'only the exact word');
    await tester.enterText(find.byKey(const ValueKey('delete-confirm')), 'DELETE');
    await tester.pump();
    expect(_enabled(tester), isTrue);

    await tester.tap(_button);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(auth.isSignedIn, isFalse);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/welcome');
    expect(find.text('Your account has been deleted.'), findsOneWidget);
  });

  testWidgets('a refusal is shown and the account stays signed in', (tester) async {
    final (_, auth) = await _pump(
      tester,
      () async => throw const BillingRefused(
        code: 'admin_account',
        message: "Admin accounts can't be deleted from the app. Ask another admin to remove admin access first.",
        status: 409,
      ),
    );
    await _open(tester);
    await tester.enterText(find.byKey(const ValueKey('delete-confirm')), 'DELETE');
    await tester.pump();
    await tester.tap(_button);
    await tester.pumpAndSettle();
    expect(find.textContaining("Admin accounts can't be deleted"), findsOneWidget);
    expect(auth.isSignedIn, isTrue);
    expect(find.text('Type DELETE to confirm'), findsOneWidget, reason: 'still on the delete screen');
  });

  testWidgets('a clinician still being verified can delete too', (tester) async {
    await _pump(tester, () async {}, status: 'pending', from: '/pending');
    await _open(tester);
    expect(find.text('Type DELETE to confirm'), findsOneWidget);
  });

  test('the request carries the typed confirmation; an admin 409 becomes its message', () async {
    final ok = _Adapter(200, {'deleted': true});
    final api = ApiClient(
      baseUrl: 'https://api.test',
      token: () async => 'tok',
      timeout: const Duration(seconds: 5),
      dio: Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = ok,
    );
    await api.deleteAccount();
    expect(ok.requests.single.method, 'POST');
    expect(ok.requests.single.path, '/v1/account/delete');
    expect(ok.requests.single.data, {'confirm': 'DELETE'});

    final admin = _Adapter(409, {
      'detail': {'error': 'admin_account', 'message': 'Ask another admin.'},
    });
    final refused = ApiClient(
      baseUrl: 'https://api.test',
      token: () async => 'tok',
      timeout: const Duration(seconds: 5),
      dio: Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = admin,
    );
    expect(
      refused.deleteAccount,
      throwsA(isA<BillingRefused>().having((e) => e.message, 'message', 'Ask another admin.')),
    );
  });
}
