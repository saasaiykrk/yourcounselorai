// Report tables on a phone: the sideways scrollbar sits below the table (never over the last
// row), and a two-column table such as the Case Snapshot fits a 360px phone without scrolling.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:your_counselor/features/consult/reply_markdown.dart';

const _snapshot = '''
| Field | Details |
| --- | --- |
| Age | 34 years |
| Presenting concern | panic attacks with sweating and palpitations |
''';

const _wide = '''
| Week | Focus | Techniques | Client homework | Family task | Measure |
| --- | --- | --- | --- | --- | --- |
| 1 | Engagement | Psychoeducation | Panic diary | Read leaflet | PDSS |
''';

Future<void> _pump(WidgetTester tester, String md, double width) async {
  tester.view.physicalSize = Size(width, 800) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  // The report screen's padding: 20 each side, plus 16 inside the section card.
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: SingleChildScrollView(child: ReplyMarkdown(md)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ScrollPosition _tableScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byWidgetPredicate((w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

void main() {
  testWidgets('a two-column table fits a 360px phone: no sideways scrolling', (tester) async {
    await _pump(tester, _snapshot, 360);
    expect(_tableScroll(tester).maxScrollExtent, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide table scrolls, and its scrollbar has room below the last row', (tester) async {
    await _pump(tester, _wide, 390);
    expect(_tableScroll(tester).maxScrollExtent, greaterThan(0));
    final tableBottom = tester.getBottomLeft(find.byType(Table)).dy;
    final scrollBottom = tester
        .getBottomLeft(
          find.byWidgetPredicate((w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal),
        )
        .dy;
    expect(scrollBottom - tableBottom, greaterThanOrEqualTo(12), reason: 'the scrollbar thumb draws in this gap');
  });
}
