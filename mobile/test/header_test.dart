// The consult header with a real verified profile: the wordmark must stay on
// one line on narrow phones and with large system text.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:your_counselor/main.dart';
import 'package:your_counselor/core/api/api_models.dart';
import 'package:your_counselor/core/providers.dart';
import 'package:your_counselor/core/repositories.dart';
import 'package:your_counselor/core/widgets/brand.dart';
import 'package:your_counselor/router.dart';

class _VerifiedL3 implements ProfileRepository {
  @override
  Future<Me> me() async =>
      const Me(verificationStatus: 'verified', level: 'L3', role: 'psychologist', registrationBody: 'RCI');

  @override
  Future<void> submit(ProfileSubmission profile) async {}

  @override
  Future<ProfileEditResult> edit(ProfileEdit profile) async =>
      const ProfileEditResult(verificationStatus: 'verified', reverify: false);
}

void main() {
  for (final width in [320.0, 360.0, 390.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('header fits on one line at ${width.toInt()}px, text x$scale', (tester) async {
        tester.view.physicalSize = Size(width, 700) * 3;
        tester.view.devicePixelRatio = 3;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [profileRepositoryProvider.overrideWithValue(_VerifiedL3())],
            child: YourCounselorApp(router: buildRouter(initialLocation: '/consult')),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));

        expect(tester.takeException(), isNull);
        final wordmark = tester.getSize(find.byType(BrandWordmark));
        expect(wordmark.height, lessThan(40), reason: '"Your Counselor" must not wrap to two lines');
        expect(find.text('L3'), findsOneWidget, reason: 'server-verified level is shown');
      });
    }
  }
}
