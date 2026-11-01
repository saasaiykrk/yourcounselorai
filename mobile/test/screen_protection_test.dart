// Case screens block screenshots and screen recording (Android FLAG_SECURE). Only a demo build made with
// ALLOW_SCREEN_CAPTURE=true skips it; normal and Play builds never do. Also: the version shown in Account
// is the app's real version.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:your_counselor/core/config.dart';
import 'package:your_counselor/core/security/screen_protection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('yourcounselor/screen_protection'),
      (call) async => calls.add(call.method),
    );
  });

  tearDown(() => ScreenProtection.captureAllowed = AppConfig.allowScreenCapture);

  test('normal builds block capture on case screens', () async {
    expect(AppConfig.allowScreenCapture, isFalse, reason: 'off unless the build turns it on');
    ScreenProtection.acquire();
    ScreenProtection.release();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['enable', 'disable']);
  });

  test('a demo build that allows capture never blocks it', () async {
    ScreenProtection.captureAllowed = true;
    ScreenProtection.acquire();
    ScreenProtection.release();
    await Future<void>.delayed(Duration.zero);
    expect(calls, isEmpty);
  });

  test('the version in Account is the app version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*([0-9.]+)\+', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(AppConfig.appVersion, version);
  });
}
