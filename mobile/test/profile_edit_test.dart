// Account → Edit profile: name, gender and age change directly; a changed role or
// registration number sends the account back for verification (after a warning).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:your_counselor/core/api/api_models.dart';
import 'package:your_counselor/core/providers.dart';
import 'package:your_counselor/core/repositories.dart';
import 'package:your_counselor/main.dart';
import 'package:your_counselor/router.dart';

class _Profile implements ProfileRepository {
  Me current = const Me(
    verificationStatus: 'verified',
    level: 'L2',
    role: 'psychologist',
    registrationBody: 'RCI',
    registrationNumber: 'A12345',
    fullName: 'Dr Old Name',
    gender: 'female',
    age: 34,
    mobile: '+919876543210',
  );
  final edits = <ProfileEdit>[];

  @override
  Future<Me> me() async => current;

  @override
  Future<void> submit(ProfileSubmission profile) async {}

  @override
  Future<ProfileEditResult> edit(ProfileEdit p) async {
    edits.add(p);
    final reverify =
        p.role != current.role ||
        p.registrationBody != current.registrationBody ||
        p.registrationNumber != current.registrationNumber;
    current = Me(
      verificationStatus: reverify ? 'pending' : current.verificationStatus,
      level: reverify ? null : current.level,
      role: p.role,
      registrationBody: p.registrationBody,
      registrationNumber: p.registrationNumber,
      fullName: p.fullName,
      gender: p.gender,
      age: p.age,
      mobile: p.mobile,
    );
    return ProfileEditResult(verificationStatus: current.verificationStatus, reverify: reverify);
  }
}

Future<GoRouter> _pump(WidgetTester tester, _Profile profile) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = buildRouter(initialLocation: '/account');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [profileRepositoryProvider.overrideWithValue(profile)],
      child: YourCounselorApp(router: router),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Edit profile'));
  await tester.pumpAndSettle();
  return router;
}

Finder _field(String label) => find.byKey(ValueKey('profile-$label'));

void main() {
  test('me reads the editable details; an edit never carries a level or consent', () {
    final me = Me.fromJson({
      'verification_status': 'verified',
      'level': 'L2',
      'gender': 'male',
      'age_at_registration': 41,
      'registration_number': 'B777',
      'mobile': '+919876543210',
    });
    expect((me.gender, me.age, me.registrationNumber, me.mobile), ('male', 41, 'B777', '+919876543210'));
    final json = const ProfileEdit(
      fullName: 'A B',
      gender: 'male',
      age: 41,
      role: 'psychologist',
      registrationBody: 'RCI',
      registrationNumber: 'B777',
      mobile: '+919876543210',
    ).toJson();
    expect(json.keys.toSet(), {
      'full_name',
      'gender',
      'age',
      'role',
      'registration_body',
      'registration_number',
      'mobile',
    });
  });

  testWidgets('changing the name keeps the verification', (tester) async {
    final profile = _Profile();
    final router = await _pump(tester, profile);
    expect(find.text('Edit profile'), findsWidgets);
    final name = tester.widget<TextField>(_field('name'));
    expect(name.controller!.text, 'Dr Old Name', reason: 'prefilled from the profile');

    await tester.enterText(_field('name'), 'Dr New Name');
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('Send for verification again?'), findsNothing);
    expect(profile.edits.single.fullName, 'Dr New Name');
    expect(profile.edits.single.registrationNumber, 'A12345');
    expect(router.state.uri.path, '/account');
    expect(find.text('Profile saved.'), findsOneWidget);
  });

  testWidgets('changing the registration number warns, then sends it back for verification', (tester) async {
    final profile = _Profile();
    final router = await _pump(tester, profile);
    await tester.enterText(_field('registration'), 'A99999');
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('Send for verification again?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(profile.edits, isEmpty);

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Send for verification'));
    await tester.pumpAndSettle();
    expect(profile.edits.single.registrationNumber, 'A99999');
    expect(router.state.uri.path, '/pending');
  });

  testWidgets('the mobile number is prefilled, checked and saved in one form', (tester) async {
    final profile = _Profile();
    await _pump(tester, profile);
    expect(tester.widget<TextField>(_field('mobile')).controller!.text, '98765 43210');
    expect(find.text('+91'), findsOneWidget, reason: 'the saved number is split into country and number');
    await tester.enterText(_field('mobile'), '12345');
    await tester.pump();
    expect(find.text('A 10-digit mobile number, like 98765 43210'), findsOneWidget);
    await tester.ensureVisible(find.text('Save changes'));
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save changes')).onPressed, isNull);
    await tester.enterText(_field('mobile'), '091234 56789');
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(profile.edits.single.mobile, '+919123456789');
  });

  testWidgets('an account from before the mobile number must add one to save', (tester) async {
    final profile = _Profile()
      ..current = const Me(
        verificationStatus: 'verified',
        level: 'L2',
        role: 'psychologist',
        registrationBody: 'RCI',
        registrationNumber: 'A12345',
        fullName: 'Dr Old Name',
        gender: 'female',
        age: 34,
      );
    await _pump(tester, profile);
    await tester.ensureVisible(find.text('Save changes'));
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save changes')).onPressed, isNull);
  });

  testWidgets('fits a 320px phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(_Profile())],
        child: YourCounselorApp(router: buildRouter(initialLocation: '/account/profile')),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
