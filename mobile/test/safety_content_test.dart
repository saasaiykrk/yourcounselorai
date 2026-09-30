// Keeps the app's fixed safety wording in step with the backend and the
// crisis register, so a change on one side can't silently drift.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:your_counselor/core/content/safety_content.dart';

String _repoFile(String path) => File('../$path').readAsStringSync();

void main() {
  test('every crisis number shown in the app is in the crisis register', () {
    final register = _repoFile('skill/clinical-assist/references/crisis-resources.md');
    final current = register.split('## Current entries')[1].split('## Output rule')[0];
    final listed = RegExp(r'\*\*([\d-]+)\*\*').allMatches(current).map((m) => m.group(1)).toSet();

    for (final line in kCrisisLines) {
      expect(listed, contains(line.number), reason: '${line.service} ${line.number} is not in the register');
    }
    expect(kCrisisLines.map((l) => l.number).toSet(), equals(listed), reason: 'app should show every register number');
  });

  test('never shows the retired KIRAN or CHILDLINE numbers', () {
    for (final line in kCrisisLines) {
      expect(line.number, isNot('1800-599-0019'));
      expect(line.service.toUpperCase(), isNot(contains('CHILDLINE')));
    }
  });

  test('disclaimer matches the inspector verbatim', () {
    final source = _repoFile('app/inspector.py');
    final block = RegExp(r'DISCLAIMER = \(([\s\S]*?)\n\)').firstMatch(source)!.group(1)!;
    final python = RegExp(r'"([^"]*)"').allMatches(block).map((m) => m.group(1)).join();
    expect(kDisclaimer, python);
  });

  test('report categories match the incidents API', () {
    final source = _repoFile('app/main.py');
    final pattern = RegExp(r'category: str = Field\(pattern="\^\(([^)]*)\)\$"\)').firstMatch(source)!.group(1)!;
    expect(ReportCategory.values.map((c) => c.apiValue).toSet(), pattern.split('|').toSet());
  });

  test('consult modes match the consult API', () {
    final source = _repoFile('app/main.py');
    final pattern = RegExp(r'mode: str = Field\(default="auto", pattern="\^\(([^)]*)\)\$"\)')
        .firstMatch(source)!
        .group(1)!;
    expect(ConsultMode.values.map((m) => m.apiCode).toSet(), pattern.split('|').toSet());
  });
}
