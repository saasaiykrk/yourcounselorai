// End-to-end: the app's ApiClient against a real backend started in dev mode.
//
//   DEV_MODE=1 uvicorn app.main:app --port 8000        (from the repo root)
//   YC_BACKEND_URL=http://127.0.0.1:8000 flutter test test/backend_integration_test.dart
//
// Skipped when YC_BACKEND_URL is not set (for example in CI).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:your_counselor/core/api/api_client.dart';
import 'package:your_counselor/core/api/api_exceptions.dart';
import 'package:your_counselor/core/api/api_models.dart';
import 'package:your_counselor/core/deid/cleaner.dart';
import 'package:your_counselor/features/consult/reply_sections.dart';

void main() {
  final url = Platform.environment['YC_BACKEND_URL'];
  final skip = url == null ? 'set YC_BACKEND_URL to run against a dev-mode backend' : null;

  ApiClient client([String token = 'dev-L2']) =>
      ApiClient(baseUrl: url ?? '', token: () async => token, timeout: const Duration(seconds: 60));

  setUpAll(() => HttpOverrides.global = null); // real network for this file only

  test('me returns a verified dev clinician', () async {
    final me = await client().me();
    expect(me.isVerified, isTrue);
    expect(me.level, 'L2');
  }, skip: skip);

  test('a cleaned case is delivered, inspected and parseable', () async {
    final cleaned = clean('34F, panic attacks for 3 months, call 9876543210. PHQ-9 8, GAD-7 14. Risk asked, denies.');
    expect(cleaned.text, isNot(contains('9876543210')));
    final reply = await client().consult(
      ConsultRequest(text: cleaned.text, mode: 'A', redactionCounts: cleaned.counts),
    );
    expect(reply.delivered, isTrue);
    expect(reply.skillVersion, isNotEmpty);
    expect(reply.text, isNot(startsWith('<!--yc')), reason: 'server strips the contract line');
    final parsed = parseReply(reply.text);
    expect(parsed.sections, isNotEmpty);
    expect(parsed.hasDisclaimer, isTrue);

    await client().reportIncident(turnId: reply.turnId, category: 'other', note: 'integration test');
  }, skip: skip);

  test('the server rejects text the phone did not clean', () async {
    await expectLater(
      client().consult(const ConsultRequest(text: 'Client phone 9876543210', mode: 'auto', redactionCounts: {})),
      throwsA(isA<IdentifiersDetected>().having((e) => e.types, 'types', ['PHONE'])),
    );
  }, skip: skip);

  test('a bad token is rejected', () async {
    await expectLater(client('not-a-real-token').me(), throwsA(isA<ApiException>()));
  }, skip: skip);
}
