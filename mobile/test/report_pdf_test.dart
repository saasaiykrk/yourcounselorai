// "Download PDF": the report is turned into a PDF on the phone (no AI, no server call),
// with the safety notice first, the handling footer on every page and the disclaimer last.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:your_counselor/core/api/api_models.dart';
import 'package:your_counselor/core/content/safety_content.dart';
import 'package:your_counselor/features/consult/report_pdf.dart';
import 'package:your_counselor/main.dart';
import 'package:your_counselor/router.dart';

/// The gold-standard consultation report as the app receives it (contract line removed).
String _goldReport() {
  final raw = File('../fixtures/golden/consult_report_ocd.md').readAsStringSync();
  return raw.split('\n').where((l) => !l.startsWith('<!--yc')).join('\n').trim();
}

ConsultReply _reply(String text, {bool delivered = true, String mode = 'R', String level = 'L2'}) => ConsultReply(
  turnId: 't1',
  conversationId: 'c1',
  delivered: delivered,
  text: text,
  skillVersion: '2.3.0',
  meta: ReplyMeta(mode: mode, gate: 'none', ceiling: 'Moderate', level: level),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('markdown to blocks', () {
    test('headings, paragraphs, lists, tables, quotes and rules', () {
      final blocks = parseReportMarkdown('''
## Consultation Report — Sample

### 1. Pattern
Some **bold** text and *italic* text.

- first point
- second point
  - nested point
1. step one
2. step two

| Field | Details |
| --- | --- |
| Age / Gender | 9 years / Male |

> A quoted line

---
''');
      expect(blocks.whereType<PdfHeading>().map((h) => (h.level, h.text)), [
        (2, 'Consultation Report — Sample'),
        (3, '1. Pattern'),
      ]);
      expect(blocks.whereType<PdfParagraph>().first.text, 'Some **bold** text and *italic* text.');
      final items = blocks.whereType<PdfListItem>().toList();
      expect(items.map((i) => (i.marker, i.text, i.indent)), [
        ('•', 'first point', 0),
        ('•', 'second point', 0),
        ('•', 'nested point', 1),
        ('1.', 'step one', 0),
        ('2.', 'step two', 0),
      ]);
      final table = blocks.whereType<PdfTable>().single;
      expect(table.rows, [
        ['Field', 'Details'],
        ['Age / Gender', '9 years / Male'],
      ]);
      expect(blocks.whereType<PdfQuote>().single.text, 'A quoted line');
      expect(blocks.whereType<PdfRule>(), hasLength(1));
    });

    test('inline markup becomes styled runs; links keep their address', () {
      expect(inlineRuns('a **b** *c* `d` [site](https://who.int)').map((r) => (r.text, r.bold, r.italic)), [
        ('a ', false, false),
        ('b', true, false),
        (' ', false, false),
        ('c', false, true),
        (' d site (https://who.int)', false, false),
      ]);
    });
  });

  group('report document', () {
    test('safety notice first, disclaimer last, and the disclaimer is not repeated from the body', () {
      final doc = reportDocument(_reply(_goldReport()), generatedAt: DateTime(2026, 10, 7, 9, 30));
      expect(doc.title, 'Consultation report');
      expect(doc.precautions, kPdfPrecautions);
      expect(doc.precautions.join(' '), contains('de-identified'));
      expect(doc.crisisLine, contains('112'));
      expect(doc.crisisLine, contains('14416'));
      expect(doc.disclaimer, kDisclaimer);
      final bodyText = doc.blocks.map((b) => b.toString()).join('\n');
      expect(bodyText, isNot(contains(kDisclaimer)), reason: 'shown once, in its own box at the end');
      expect(doc.blocks.whereType<PdfHeading>().map((h) => h.text), contains('15. Disclaimer'));
      expect(doc.meta, contains('Passed the app\'s safety checks'));
      expect(doc.meta, contains('Written for L2'));
      expect(doc.meta, contains('Knowledge base 2.3.0'));
      expect(doc.footer, contains('De-identified'));
    });

    test('a direct consult is titled as a clinical work-up', () {
      expect(
        reportDocument(_reply('### 1. A\nText', mode: 'A'), generatedAt: DateTime(2026)).title,
        'Clinical work-up',
      );
    });

    test('a held-back reply cannot be exported', () {
      expect(
        () => reportDocument(_reply('held back', delivered: false), generatedAt: DateTime(2026)),
        throwsArgumentError,
      );
    });

    test('the file name carries no case details', () {
      expect(reportPdfFileName(DateTime(2026, 10, 7, 9, 30)), 'YourCounselor-report-2026-10-07-0930.pdf');
    });

    test('builds a real PDF from the gold report, with the bundled fonts', () async {
      final bytes = await buildReportPdf(_reply(_goldReport()), generatedAt: DateTime(2026, 10, 7));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(20000));
      expect(String.fromCharCodes(bytes.skip(bytes.length - 8)).trim(), endsWith('%%EOF'));
    });
  });

  group('reply screen', () {
    Future<List<(Uint8List, String)>> pumpReply(WidgetTester tester) async {
      final exported = <(Uint8List, String)>[];
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [reportPdfExporterProvider.overrideWithValue((bytes, name) async => exported.add((bytes, name)))],
          child: YourCounselorApp(router: buildRouter(initialLocation: '/reply')),
        ),
      );
      await tester.pumpAndSettle();
      return exported;
    }

    testWidgets('Download PDF asks first, lists the precautions, then exports', (tester) async {
      final exported = await pumpReply(tester);
      await tester.tap(find.byTooltip('Download PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Download this report as a PDF?'), findsOneWidget);
      expect(find.textContaining('leaves the app'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(exported, isEmpty);

      await tester.tap(find.byTooltip('Download PDF'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Download PDF'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
      await tester.pumpAndSettle();
      expect(exported, hasLength(1));
      expect(String.fromCharCodes(exported.single.$1.take(5)), '%PDF-');
      expect(exported.single.$2, startsWith('YourCounselor-report-'));
    });
  });
}
