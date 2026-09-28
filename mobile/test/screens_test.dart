// Renders every screen at phone size (any layout overflow fails the test)
// and checks the safety behaviours the design relies on.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:your_counselor/main.dart';
import 'package:your_counselor/router.dart';

const _phones = {'small (360x640)': Size(360, 640), 'standard (390x844)': Size(390, 844)};

const _routes = [
  '/welcome',
  '/sign-in',
  '/code',
  '/details',
  '/pending',
  '/consult',
  '/reply',
  '/safety',
  '/held-back',
  '/identifiers',
  '/limit',
  '/offline',
  '/account',
  '/gallery',
];

/// Finds a FilledButton (including FilledButton.icon) by its label.
Finder _filled(String label) =>
    find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is FilledButton));

VoidCallback? _onPressed(WidgetTester tester, String label) => tester.widget<FilledButton>(_filled(label)).onPressed;

Future<void> _pumpAt(WidgetTester tester, String location, Size size) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(YourCounselorApp(router: buildRouter(initialLocation: location)));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  for (final phone in _phones.entries) {
    group('renders on a ${phone.key} phone', () {
      for (final route in _routes) {
        testWidgets(route, (tester) async {
          await _pumpAt(tester, route, phone.value);
          expect(tester.takeException(), isNull);
          // Leave no periodic timers (code countdown) running between tests.
          await tester.pumpWidget(const SizedBox());
        });
      }

      testWidgets('/drafting', (tester) async {
        final router = buildRouter(initialLocation: '/drafting');
        tester.view.physicalSize = phone.value * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(YourCounselorApp(router: router));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Drafting your work-up'), findsOneWidget);
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '/reply');
      });
    });
  }

  testWidgets('splash moves on to welcome', (tester) async {
    await _pumpAt(tester, '/', const Size(390, 844));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets('send stays disabled until the clinician attests "no identifiers"', (tester) async {
    await _pumpAt(tester, '/consult', const Size(390, 844));
    await tester.tap(find.text('Check & send'));
    await tester.pumpAndSettle();

    expect(_onPressed(tester, 'Tick the box to send'), isNull);

    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(_onPressed(tester, 'Send securely'), isNotNull);
  });

  testWidgets('possible name can be removed and undone', (tester) async {
    await _pumpAt(tester, '/consult', const Size(390, 844));
    await tester.tap(find.text('Check & send'));
    await tester.pumpAndSettle();

    expect(find.text('We removed 3 items'), findsOneWidget);
    await tester.ensureVisible(find.text('Yes, remove'));
    await tester.tap(find.text('Yes, remove'));
    await tester.pumpAndSettle();
    expect(find.text('We removed 4 items'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('We removed 3 items'), findsOneWidget);
  });

  testWidgets('report needs a category before it can be sent', (tester) async {
    await _pumpAt(tester, '/reply', const Size(390, 844));
    await tester.ensureVisible(find.text('Report a problem with this reply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report a problem with this reply'));
    await tester.pumpAndSettle();

    expect(_onPressed(tester, 'Send report'), isNull);
    await tester.tap(find.text('Unsafe advice'));
    await tester.pump();
    expect(_onPressed(tester, 'Send report'), isNotNull);
  });

  testWidgets('professional details need consent and a registration number', (tester) async {
    await _pumpAt(tester, '/details', const Size(390, 844));
    expect(_onPressed(tester, 'Submit for verification'), isNull);

    await tester.enterText(find.byType(TextField), 'A12345');
    await tester.pump();
    expect(_onPressed(tester, 'Submit for verification'), isNull, reason: 'consent still missing');
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(_onPressed(tester, 'Submit for verification'), isNotNull);
  });

  testWidgets('crisis screen lists every register number', (tester) async {
    await _pumpAt(tester, '/safety', const Size(390, 844));
    for (final n in ['112', '14416', '1-800-891-4416', '1098', '181']) {
      expect(find.text(n), findsOneWidget);
    }
  });
}
