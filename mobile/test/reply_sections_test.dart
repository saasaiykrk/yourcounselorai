// The reply parser against the skill's real worked examples
// (fixtures/golden/*.md), the same files the inspector tests use.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:your_counselor/features/consult/reply_sections.dart';

/// The server strips the contract line before sending; do the same here.
String _golden(String name) =>
    File('../fixtures/golden/$name').readAsStringSync().replaceFirst(RegExp(r'^\s*<!--\s*yc[^>]*-->\s*\n?'), '');

void main() {
  test('full plan (Mode A) splits into its 17 numbered sections', () {
    final parsed = parseReply(_golden('mode_a_panic.md'));
    expect(parsed.sections, hasLength(17));
    expect(parsed.sections.first.heading, '1. Case History & MSE Audit');
    expect(parsed.sections[1].number, '2');
    expect(parsed.sections[1].provisional, isFalse);
    expect(parsed.sections[2].provisional, isTrue, reason: 'Low ceiling marks sections 3+ provisional');
    expect(parsed.sections[2].title, isNot(startsWith('PROVISIONAL')));
    expect(parsed.hasDisclaimer, isTrue);
    expect(
      parsed.sections.last.body,
      isNot(contains('This tool is for professional use only')),
      reason: 'the disclaimer is shown in a fixed place, not inside a collapsible section',
    );
  });

  test('gate 1 reply keeps its safety heading', () {
    final parsed = parseReply(_golden('gate1_minor.md'));
    expect(parsed.sections, isNotEmpty);
    expect(parsed.sections.first.title, contains('Acute risk'));
    expect(parsed.hasDisclaimer, isTrue);
  });

  test('quick review (Mode B) parses without losing text', () {
    final source = _golden('mode_b_ocd.md');
    final parsed = parseReply(source);
    final rebuilt = [parsed.intro, for (final s in parsed.sections) '${s.heading}\n${s.body}'].join('\n');
    for (final word in ['Safety', 'OCD']) {
      if (source.contains(word)) expect(rebuilt, contains(word));
    }
  });

  test('text with no headings becomes the intro', () {
    final parsed = parseReply('Just a short answer.');
    expect(parsed.sections, isEmpty);
    expect(parsed.intro, 'Just a short answer.');
  });
}
