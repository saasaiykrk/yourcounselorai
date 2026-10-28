// Renders every screen at phone size (any layout overflow fails the test)
// and checks the safety behaviours and navigation the design relies on.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:your_counselor/core/auth/auth_service.dart';
import 'package:your_counselor/core/config.dart';
import 'package:go_router/go_router.dart';
import 'package:your_counselor/core/api/api_exceptions.dart';
import 'package:your_counselor/core/api/api_models.dart';
import 'package:your_counselor/core/demo/preview_data.dart';
import 'package:your_counselor/core/providers.dart';
import 'package:your_counselor/core/repositories.dart';
import 'package:your_counselor/features/consult/check_sheet.dart';
import 'package:your_counselor/main.dart';
import 'package:your_counselor/router.dart';

const _phones = {'small (360x640)': Size(360, 640), 'standard (390x844)': Size(390, 844)};

const _routes = [
  '/welcome',
  '/sign-in',
  '/code',
  '/details',
  '/sign-up',
  '/pending',
  '/consult',
  '/reply',
  '/safety',
  '/held-back',
  '/identifiers',
  '/limit',
  '/offline',
  '/account',
  '/history',
  '/gallery',
  '/privacy',
  '/terms',
  '/dpa',
  '/consultation',
];

/// Consult repository that answers instantly with a chosen outcome.
class _FakeConsult implements ConsultRepository {
  _FakeConsult({this.error, this.gate = 'none', this.delivered = true});

  final ApiException? error;
  final String gate;
  final bool delivered;
  final sent = <ConsultRequest>[];
  final reports = <String>[];

  @override
  Future<ConsultReply> send(ConsultRequest request) async {
    sent.add(request);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (error != null) throw error!;
    return ConsultReply(
      turnId: 'turn-1',
      conversationId: 'conv-1',
      delivered: delivered,
      text: gate == 'none' ? kPreviewReplyMarkdown : kPreviewSafetyMarkdown,
      skillVersion: '2.1.1',
      meta: ReplyMeta(mode: 'A', gate: gate, ceiling: 'Low', level: 'L2'),
    );
  }

  @override
  Future<ConsultReply?> result(String requestId) async => null;

  @override
  Future<void> report({required String turnId, required String category, required String note}) async =>
      reports.add('$turnId:$category');
}

/// The text field with this hint.
Finder _field(String hint) => find.widgetWithText(TextField, hint);

/// Finds a FilledButton (including FilledButton.icon) by its label.
Finder _filled(String label) =>
    find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is FilledButton));

VoidCallback? _onPressed(WidgetTester tester, String label) => tester.widget<FilledButton>(_filled(label)).onPressed;

Future<GoRouter> _pumpAt(
  WidgetTester tester,
  String location, {
  Size size = const Size(390, 844),
  ConsultRepository? consult,
  AuthService? auth,
  ProfileRepository? profile,
  Future<void> Function(String email, ProfileSubmission details)? startSignup,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = buildRouter(initialLocation: location);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        consultRepositoryProvider.overrideWithValue(consult ?? _FakeConsult()),
        consultRecoveryProvider.overrideWithValue((within: Duration.zero, every: Duration.zero)),
        if (auth != null) authServiceProvider.overrideWithValue(auth),
        if (profile != null) profileRepositoryProvider.overrideWithValue(profile),
        if (startSignup != null) startSignupProvider.overrideWithValue(startSignup),
      ],
      child: YourCounselorApp(router: router),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
  return router;
}

class _RecordingAuth implements AuthService {
  final codesRequested = <String>[];
  final verified = <String>[];
  final reviewCodes = <String>[];
  bool _in = false;

  @override
  bool get isSignedIn => _in;

  @override
  Future<void> requestCode(String email) async => codesRequested.add(email);

  @override
  Future<void> verifyCode(String email, String code) async {
    verified.add(code);
    _in = true;
  }

  @override
  Future<void> signInWithReviewCode(String email, String code) async {
    reviewCodes.add(code);
    _in = true;
  }

  @override
  Future<String?> accessToken() async => _in ? 'dev-L2' : null;

  @override
  Future<void> signOut() async => _in = false;
}

/// Opens the check panel from the consult screen, attests, and sends.
Future<void> _checkAndSend(WidgetTester tester) async {
  await tester.tap(find.text('Check & send'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byType(Checkbox));
  await tester.tap(find.byType(Checkbox));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Send securely'));
  await tester.pump();
}

void main() {
  for (final phone in _phones.entries) {
    group('renders on a ${phone.key} phone', () {
      for (final route in _routes) {
        testWidgets(route, (tester) async {
          await _pumpAt(tester, route, size: phone.value);
          await tester.pump(const Duration(milliseconds: 500));
          expect(tester.takeException(), isNull);
          // Leave no periodic timers (code countdown) running between tests.
          await tester.pumpWidget(const SizedBox());
        });
      }
    });
  }

  testWidgets('splash moves on to welcome when signed out', (tester) async {
    await _pumpAt(tester, '/');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('I already have an account · Sign in'), findsOneWidget);
  });

  testWidgets('create account: details first, then the code, nothing sent before Send code', (tester) async {
    final auth = _RecordingAuth();
    final started = <(String, ProfileSubmission)>[];
    final router = await _pumpAt(tester, '/', auth: auth, startSignup: (e, d) async => started.add((e, d)));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/sign-up');
    expect(find.text('Create your account'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('signup-email')), 'new@clinic');
    await tester.pump();
    expect(find.text('An email like name@clinic.in'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('signup-email')), ' new@clinic.in ');
    await tester.enterText(_field('As on your registration'), 'Dr New Clinician');
    await tester.enterText(_field('Years'), '29');
    await tester.enterText(_field('98765 43210'), '98765 43210');
    await tester.ensureVisible(find.text('Male'));
    await tester.tap(find.text('Male'));
    await tester.enterText(_field('As shown on the register'), 'B4567');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(_onPressed(tester, 'Send code'), isNull, reason: 'consent still missing');
    expect(started, isEmpty);
    expect(auth.codesRequested, isEmpty);
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();

    expect(started.single.$1, 'new@clinic.in');
    expect(
      (started.single.$2.fullName, started.single.$2.mobile, started.single.$2.registrationNumber),
      ('Dr New Clinician', '+919876543210', 'B4567'),
    );
    expect(auth.codesRequested, ['new@clinic.in'], reason: 'the code is sent after the details are saved');
    expect(router.state.uri.path, '/code');
    expect(find.textContaining('new@clinic.in'), findsOneWidget);
  });

  testWidgets('create account: no code is sent if the details could not be saved', (tester) async {
    final auth = _RecordingAuth();
    await _pumpAt(tester, '/sign-up', auth: auth, startSignup: (_, _) async => throw const DailyLimitReached());
    await tester.enterText(find.byKey(const ValueKey('signup-email')), 'new@clinic.in');
    await tester.enterText(_field('As on your registration'), 'Dr New Clinician');
    await tester.enterText(_field('Years'), '29');
    await tester.enterText(_field('98765 43210'), '98765 43210');
    await tester.ensureVisible(find.text('Male'));
    await tester.tap(find.text('Male'));
    await tester.enterText(_field('As shown on the register'), 'B4567');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(find.text('Too many sign-ups from this network. Please try again in an hour.'), findsOneWidget);
    expect(auth.codesRequested, isEmpty);
  });

  testWidgets('send stays disabled until the clinician attests "no identifiers"', (tester) async {
    await _pumpAt(tester, '/consult');
    await tester.tap(find.text('Check & send'));
    await tester.pumpAndSettle();

    expect(_onPressed(tester, 'Tick the box to send'), isNull);
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(_onPressed(tester, 'Send securely'), isNotNull);
  });

  testWidgets('check panel shows what the real cleaner removed', (tester) async {
    await _pumpAt(tester, '/consult');
    await tester.tap(find.text('Check & send'));
    await tester.pumpAndSettle();

    expect(find.text('We removed 3 items'), findsOneWidget);
    expect(find.text('1 phone number'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(CheckSheet), matching: find.textContaining('98765', findRichText: true)),
      findsNothing,
      reason: 'the phone number must not appear in the text to be sent',
    );
    await tester.ensureVisible(find.text('Yes, remove'));
    await tester.tap(find.text('Yes, remove'));
    await tester.pumpAndSettle();
    expect(find.text('We removed 4 items'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('We removed 3 items'), findsOneWidget);
  });

  testWidgets('full consult: cleaned text is sent, reply shown, draft cleared', (tester) async {
    final consult = _FakeConsult();
    final router = await _pumpAt(tester, '/consult', consult: consult);
    await tester.ensureVisible(find.text('Check & send'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check & send'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Yes, remove'));
    await tester.tap(find.text('Yes, remove'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send securely'));
    await tester.pump();
    expect(router.state.uri.path, '/drafting');

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/reply');
    expect(find.text('Clinical work-up'), findsOneWidget);

    final sent = consult.sent.single;
    expect(sent.text, isNot(contains('98765 43210')));
    expect(sent.text, isNot(contains('Priya')));
    expect(sent.text, isNot(contains('Asha')));
    expect(sent.redactionCounts, {'NAME': 2, 'PHONE': 1, 'ORG': 1});
    expect(sent.toJson()['deid_attested'], isTrue);

    router.go('/consult');
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, isEmpty, reason: 'draft must be wiped after a delivered reply');
  });

  testWidgets('a follow-up continues the same conversation', (tester) async {
    final consult = _FakeConsult();
    final router = await _pumpAt(tester, '/consult', consult: consult);
    await _checkAndSend(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/reply');

    await tester.enterText(find.byType(TextField).last, 'Shorten the plan to 6 sessions');
    await tester.tap(find.byTooltip('Check and send follow-up'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send securely'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(consult.sent.last.conversationId, 'conv-1');
  });

  final outcomes = <String, (_FakeConsult, String)>{
    'held back reply': (_FakeConsult(delivered: false), '/held-back'),
    'risk (gate 1) reply': (_FakeConsult(gate: 'gate1'), '/safety'),
    'server found an identifier': (_FakeConsult(error: const IdentifiersDetected(['PHONE'])), '/identifiers'),
    'daily limit': (_FakeConsult(error: const DailyLimitReached()), '/limit'),
    'no connection': (_FakeConsult(error: const NetworkProblem()), '/offline'),
    'timeout': (_FakeConsult(error: const NetworkProblem(timedOut: true)), '/offline'),
    'signed out': (_FakeConsult(error: const Unauthorized()), '/sign-in'),
    'not verified': (_FakeConsult(error: const NotVerified()), '/pending'),
  };
  for (final e in outcomes.entries) {
    testWidgets('${e.key} opens ${e.value.$2}', (tester) async {
      final router = await _pumpAt(tester, '/consult', consult: e.value.$1);
      await _checkAndSend(tester);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, e.value.$2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('draft survives a failed send', (tester) async {
    final router = await _pumpAt(tester, '/consult', consult: _FakeConsult(error: const NetworkProblem()));
    await _checkAndSend(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/offline');
    await tester.tap(find.text('Back to my text'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, kSampleCase);
  });

  testWidgets('identifier screen names the type, never the value', (tester) async {
    final router = await _pumpAt(
      tester,
      '/consult',
      consult: _FakeConsult(error: const IdentifiersDetected(['PHONE'])),
    );
    await _checkAndSend(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/identifiers');
    expect(find.text('Phone number'), findsOneWidget);
  });

  testWidgets('report needs a category and reaches the repository', (tester) async {
    final consult = _FakeConsult();
    await _pumpAt(tester, '/consult', consult: consult);
    await _checkAndSend(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Report a problem with this reply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report a problem with this reply'));
    await tester.pumpAndSettle();
    expect(_onPressed(tester, 'Send report'), isNull);
    await tester.tap(find.text('Unsafe advice'));
    await tester.pump();
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();
    expect(consult.reports, ['turn-1:unsafe']);
  });

  testWidgets('professional details need name, gender, age, mobile, consent and a registration number', (tester) async {
    await _pumpAt(tester, '/details');
    expect(_onPressed(tester, 'Submit for verification'), isNull);

    await tester.enterText(_field('As on your registration'), 'Dr Sample Clinician');
    await tester.enterText(_field('Years'), '34');
    await tester.enterText(_field('98765 43210'), '98765 43210');
    await tester.enterText(_field('As shown on the register'), 'A12345');
    await tester.pump();
    expect(_onPressed(tester, 'Submit for verification'), isNull, reason: 'gender and consent still missing');
    await tester.ensureVisible(find.text('Female'));
    await tester.tap(find.text('Female'));
    await tester.pump();
    expect(_onPressed(tester, 'Submit for verification'), isNull, reason: 'consent still missing');
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(_onPressed(tester, 'Submit for verification'), isNotNull);

    await tester.enterText(_field('Years'), '15');
    await tester.pump();
    expect(find.text('18 to 100'), findsOneWidget);
    expect(_onPressed(tester, 'Submit for verification'), isNull, reason: 'age must be 18 to 100');
    await tester.enterText(_field('Years'), '34');
    await tester.enterText(_field('As on your registration'), ' ');
    await tester.pump();
    expect(_onPressed(tester, 'Submit for verification'), isNull, reason: 'name is required');
    await tester.enterText(_field('As on your registration'), 'Dr Sample Clinician');
    await tester.enterText(_field('98765 43210'), '12345');
    await tester.pump();
    expect(find.text('A mobile number like 98765 43210'), findsOneWidget);
    expect(_onPressed(tester, 'Submit for verification'), isNull, reason: 'a mobile number is required');
  });

  test('registration sends name, gender and age', () {
    const p = ProfileSubmission(
      fullName: 'Dr Sample Clinician',
      gender: 'female',
      age: 34,
      role: 'psychologist',
      registrationBody: 'RCI',
      registrationNumber: 'A12345',
      consentVersion: '2026-10-v3',
      mobile: '+919876543210',
    );
    expect(p.toJson(), containsPair('full_name', 'Dr Sample Clinician'));
    expect(p.toJson(), containsPair('gender', 'female'));
    expect(p.toJson(), containsPair('age', 34));
    expect(p.toJson(), containsPair('mobile', '+919876543210'));
  });

  testWidgets('the store reviewer uses the normal screens with a fixed code; nothing is emailed', (tester) async {
    AppConfig.reviewEmail = 'playreview@yourcounselor.in';
    addTearDown(() => AppConfig.reviewEmail = '');
    final auth = _RecordingAuth();
    final router = await _pumpAt(tester, '/sign-in', auth: auth);
    await tester.enterText(find.byType(TextField), ' PlayReview@YourCounselor.in ');
    await tester.pump();
    expect(find.text('Password'), findsNothing, reason: 'the same screen as everyone else');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/code');
    expect(auth.codesRequested, isEmpty, reason: 'no email is sent to the reviewer');
    await tester.enterText(find.byType(TextField), '482913');
    await tester.pump();
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    expect(auth.reviewCodes, ['482913'], reason: 'checked as the account password in Supabase');
    expect(auth.verified, isEmpty);
    expect(router.state.uri.path, '/details');

    // everyone else still gets an emailed code
    AppConfig.reviewEmail = 'playreview@yourcounselor.in';
    final auth2 = _RecordingAuth();
    final router2 = await _pumpAt(tester, '/sign-in', auth: auth2);
    await tester.enterText(find.byType(TextField), 'doctor@clinic.in');
    await tester.pump();
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(auth2.codesRequested, ['doctor@clinic.in']);
    expect(router2.state.uri.path, '/code');
  });

  testWidgets('sign-in flow: email, code, details, pending, verified', (tester) async {
    final router = await _pumpAt(tester, '/sign-in');
    await tester.enterText(find.byType(TextField), 'doctor@clinic.in');
    await tester.pump();
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/code');

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/details', reason: 'new clinicians fill in their registration');

    await tester.enterText(_field('As on your registration'), 'Dr Sample Clinician');
    await tester.enterText(_field('Years'), '34');
    await tester.enterText(_field('98765 43210'), '+91 98765 43210');
    await tester.ensureVisible(find.text('Prefer not to say'));
    await tester.tap(find.text('Prefer not to say'));
    await tester.enterText(_field('As shown on the register'), 'A12345');
    FocusManager.instance.primaryFocus?.unfocus(); // close the keyboard: its selection handle covers the box
    await tester.pump();
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Submit for verification'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/pending');

    await tester.tap(find.text('Check status'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/consult');
  });

  testWidgets('with "Skip verification" on, a new registration goes straight to consults', (tester) async {
    final router = await _pumpAt(tester, '/details', profile: _ApprovedAtOnce());
    await tester.enterText(_field('As on your registration'), 'Dr Sample Clinician');
    await tester.enterText(_field('Years'), '34');
    await tester.enterText(_field('98765 43210'), '98765 43210');
    await tester.ensureVisible(find.text('Female'));
    await tester.tap(find.text('Female'));
    await tester.enterText(_field('As shown on the register'), 'A12345');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Submit for verification'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/consult', reason: 'no "waiting for verification" screen');
  });

  testWidgets('email code field is announced to screen readers', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpAt(tester, '/code');
    expect(find.bySemanticsLabel(RegExp(r'^6-digit code')), findsOneWidget);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('crisis numbers screen lists every register number', (tester) async {
    await _pumpAt(tester, '/safety');
    for (final n in ['112', '14416', '1-800-891-4416', '1098', '181']) {
      expect(find.text(n), findsOneWidget);
    }
  });
}

/// The server approves at once (the admin's "Skip verification" switch is on).
class _ApprovedAtOnce extends PreviewProfileRepository {
  var _submitted = false;

  @override
  Future<void> submit(ProfileSubmission profile) async => _submitted = true;

  @override
  Future<Me> me() async => _submitted
      ? const Me(verificationStatus: 'verified', level: 'L2', role: 'psychologist', registrationBody: 'RCI')
      : const Me(verificationStatus: 'none');
}
