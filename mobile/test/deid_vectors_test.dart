// The Dart cleaner must pass every shared vector, exactly like app/deid.py
// does in tests/test_deid.py. Never delete a vector to make this pass.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:your_counselor/core/deid/cleaner.dart';

void main() {
  final vectors = jsonDecode(File('../fixtures/deid_vectors.json').readAsStringSync()) as Map<String, dynamic>;

  group('must_redact', () {
    for (final v in (vectors['must_redact'] as List).cast<Map<String, dynamic>>()) {
      test(v['id'], () {
        final r = clean(v['text'] as String);
        for (final t in (v['types'] as List).cast<String>()) {
          expect(r.text, contains('[$t]'), reason: '${v['id']}: expected [$t] in ${r.text}');
        }
        for (final g in (v['gone'] as List).cast<String>()) {
          expect(r.text, isNot(contains(g)), reason: '${v['id']}: "$g" survived');
        }
        expect(r.isClean, isFalse);
      });
    }
  });

  group('must_keep', () {
    for (final v in (vectors['must_keep'] as List).cast<Map<String, dynamic>>()) {
      test(v['id'], () {
        final r = clean(v['text'] as String);
        expect(r.text, v['text'], reason: '${v['id']}: over-redacted');
        expect(r.isClean, isTrue);
      });
    }
  });

  test('possible name is a warning, not a redaction', () {
    final r = clean('Client came with Priya, her cousin, to the session.');
    expect(r.warnings, contains('Priya'));
    expect(r.isClean, isTrue);
  });

  test('counts are by type only', () {
    expect(clean('Call 9876543210 or mail a.b@c.com').counts, {'PHONE': 1, 'EMAIL': 1});
  });

  test('removeName replaces whole words only', () {
    expect(removeName('Asha met Ashadeep and Asha.', 'Asha'), '[NAME] met Ashadeep and [NAME].');
  });
}
