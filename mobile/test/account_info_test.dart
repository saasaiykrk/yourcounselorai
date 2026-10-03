// Account information links: each one opens its page, the draft legal pages say
// they are drafts, and "Contact" always shows the address even without a mail app.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:your_counselor/core/content/legal_content.dart';
import 'package:your_counselor/core/content/safety_content.dart';
import 'package:your_counselor/main.dart';
import 'package:your_counselor/router.dart';

Future<void> _pump(WidgetTester tester, String location) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: YourCounselorApp(router: buildRouter(initialLocation: location)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  const pages = {
    'How we protect client data': kPrivacyDoc,
    'Clinician Terms': kTermsDoc,
    'Data Processing Agreement': kDpaDoc,
  };

  for (final MapEntry(key: label, value: doc) in pages.entries) {
    testWidgets('Account → $label opens its page', (tester) async {
      await _pump(tester, '/account');
      await _open(tester, label);
      expect(find.text(doc.intro), findsOneWidget);
      expect(find.text(doc.sections.first.heading), findsOneWidget);
      expect(find.text(kDraftNotice), doc.draft ? findsOneWidget : findsNothing);
    });
  }

  testWidgets('the Clinician Terms carry the disclaimer', (tester) async {
    await _pump(tester, '/terms');
    await tester.scrollUntilVisible(find.text(kDisclaimer), 300);
    expect(find.text(kDisclaimer), findsOneWidget);
  });

  testWidgets('Contact shows the address when no mail app opens', (tester) async {
    // Like a phone with no mail app: the launcher reports that nothing opened.
    final launched = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async {
        launched.add((call.arguments as Map)['url'] as String);
        return false;
      },
    );
    await _pump(tester, '/account');
    await _open(tester, 'Contact the clinical safety team');
    expect(launched.single, startsWith('mailto:$kSafetyEmail?subject='));
    expect(find.text(kSafetyEmail), findsOneWidget);
    expect(find.textContaining('Never include client names'), findsOneWidget);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    await tester.tap(find.text('Copy address'));
    await tester.pumpAndSettle();
    expect(copied, kSafetyEmail);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('the profile step links to the Terms and the DPA', (tester) async {
    await _pump(tester, '/details');
    await _open(tester, 'Read the DPA');
    expect(find.text(kDpaDoc.intro), findsOneWidget);
  });
}
