/// "Download PDF": turns a delivered reply into a PDF on the phone.
///
/// No AI and no server call: the reply's markdown (already passed by the server's
/// safety check) is laid out with the app's own fonts. The document opens with the
/// handling precautions and the crisis numbers, carries a confidentiality footer on
/// every page, and ends with the mandatory disclaimer. The app keeps no copy: the
/// bytes go straight to the system "Save as PDF / Print" screen.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/api/api_models.dart';
import '../../core/content/safety_content.dart';

// --- markdown → blocks ----------------------------------------------------------------

sealed class PdfBlock {
  const PdfBlock();
}

class PdfHeading extends PdfBlock {
  const PdfHeading(this.level, this.text);
  final int level;
  final String text;
  @override
  String toString() => text;
}

class PdfParagraph extends PdfBlock {
  const PdfParagraph(this.text);
  final String text;
  @override
  String toString() => text;
}

class PdfListItem extends PdfBlock {
  const PdfListItem(this.marker, this.text, this.indent);
  final String marker;
  final String text;
  final int indent;
  @override
  String toString() => '$marker $text';
}

class PdfTable extends PdfBlock {
  const PdfTable(this.rows);
  final List<List<String>> rows;
  @override
  String toString() => rows.map((r) => r.join(' | ')).join('\n');
}

class PdfQuote extends PdfBlock {
  const PdfQuote(this.text);
  final String text;
  @override
  String toString() => text;
}

class PdfRule extends PdfBlock {
  const PdfRule();
  @override
  String toString() => '---';
}

final _headingRe = RegExp(r'^(#{1,6})\s+(.*?)\s*#*\s*$');
final _ruleRe = RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$');
final _tableSepRe = RegExp(r'^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$');
final _listRe = RegExp(r'^(\s*)([-*+]|\d{1,3}[.)])\s+(.*)$');
final _quoteRe = RegExp(r'^\s*>\s?(.*)$');

/// The markdown subset the replies use: headings, paragraphs, lists, tables, quotes, rules.
List<PdfBlock> parseReportMarkdown(String markdown) {
  final blocks = <PdfBlock>[];
  final para = <String>[];
  final quote = <String>[];
  final table = <List<String>>[];

  void flush() {
    if (para.isNotEmpty) blocks.add(PdfParagraph(para.join(' ')));
    if (quote.isNotEmpty) blocks.add(PdfQuote(quote.join(' ')));
    if (table.isNotEmpty) blocks.add(PdfTable([for (final r in table) List.of(r)]));
    para.clear();
    quote.clear();
    table.clear();
  }

  final text = markdown.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  for (final raw in text.split('\n')) {
    final line = raw.trimRight();
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      flush();
      continue;
    }
    if (trimmed.startsWith('|')) {
      if (para.isNotEmpty || quote.isNotEmpty) {
        final keep = [...table];
        table.clear();
        flush();
        table.addAll(keep);
      }
      if (_tableSepRe.hasMatch(trimmed)) continue;
      var cells = trimmed.split('|').map((c) => c.trim()).toList();
      if (cells.isNotEmpty && cells.first.isEmpty) cells = cells.sublist(1);
      if (cells.isNotEmpty && cells.last.isEmpty) cells = cells.sublist(0, cells.length - 1);
      table.add(cells);
      continue;
    }
    if (table.isNotEmpty) flush();
    final h = _headingRe.firstMatch(trimmed);
    if (h != null) {
      flush();
      blocks.add(PdfHeading(h.group(1)!.length, h.group(2)!));
      continue;
    }
    if (_ruleRe.hasMatch(trimmed)) {
      flush();
      blocks.add(const PdfRule());
      continue;
    }
    final q = _quoteRe.firstMatch(line);
    if (q != null) {
      if (para.isNotEmpty) flush();
      if (q.group(1)!.trim().isNotEmpty) quote.add(q.group(1)!.trim());
      continue;
    }
    final l = _listRe.firstMatch(line);
    if (l != null) {
      flush();
      final indent = (l.group(1)!.replaceAll('\t', '    ').length ~/ 2).clamp(0, 3);
      final m = l.group(2)!;
      final marker = RegExp(r'^\d').hasMatch(m) ? '${m.substring(0, m.length - 1)}.' : '•';
      blocks.add(PdfListItem(marker, l.group(3)!.trim(), indent));
      continue;
    }
    if (quote.isNotEmpty) flush();
    // A wrapped line continues the previous list item.
    if (para.isEmpty && blocks.isNotEmpty && blocks.last is PdfListItem && raw.startsWith(' ')) {
      final last = blocks.removeLast() as PdfListItem;
      blocks.add(PdfListItem(last.marker, '${last.text} $trimmed', last.indent));
      continue;
    }
    para.add(trimmed);
  }
  flush();
  return blocks;
}

/// A piece of text with one style.
class InlineRun {
  const InlineRun(this.text, {this.bold = false, this.italic = false});
  final String text;
  final bool bold;
  final bool italic;
}

final _inlineRe = RegExp(r'\*\*(.+?)\*\*|__(.+?)__|\*([^*\s][^*]*?)\*|`([^`]+)`|\[([^\]]+)\]\(([^)\s]+)\)');

/// **bold**, *italic*, `code` (plain) and [links](url) → styled runs. Adjacent runs
/// of the same style are merged.
List<InlineRun> inlineRuns(String text) {
  final runs = <InlineRun>[];
  void add(String t, {bool bold = false, bool italic = false}) {
    if (t.isEmpty) return;
    if (runs.isNotEmpty && runs.last.bold == bold && runs.last.italic == italic) {
      runs[runs.length - 1] = InlineRun(runs.last.text + t, bold: bold, italic: italic);
    } else {
      runs.add(InlineRun(t, bold: bold, italic: italic));
    }
  }

  var at = 0;
  for (final m in _inlineRe.allMatches(text)) {
    add(text.substring(at, m.start));
    if (m.group(1) != null || m.group(2) != null) {
      add(m.group(1) ?? m.group(2)!, bold: true);
    } else if (m.group(3) != null) {
      add(m.group(3)!, italic: true);
    } else if (m.group(4) != null) {
      add(m.group(4)!);
    } else {
      add('${m.group(5)} (${m.group(6)})');
    }
    at = m.end;
  }
  add(text.substring(at));
  return runs;
}

// --- the document -------------------------------------------------------------------

/// Everything printed, in order; built without fonts so it can be tested directly.
class ReportDocument {
  const ReportDocument({
    required this.title,
    required this.meta,
    required this.precautions,
    required this.crisisLine,
    required this.blocks,
    required this.disclaimer,
    required this.footer,
  });

  final String title;
  final String meta;
  final List<String> precautions;
  final String crisisLine;
  final List<PdfBlock> blocks;
  final String disclaimer;
  final String footer;
}

String _two(int n) => n.toString().padLeft(2, '0');

String _date(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// The download's file name: date and time only, never anything from the case.
String reportPdfFileName(DateTime at) => 'YourCounselor-report-${_date(at)}-${_two(at.hour)}${_two(at.minute)}.pdf';

/// Lays out a delivered reply. A held-back reply cannot be exported.
ReportDocument reportDocument(ConsultReply reply, {required DateTime generatedAt}) {
  if (!reply.delivered) throw ArgumentError('only a delivered reply can be downloaded');
  final body = reply.text
      .split('\n')
      .where((l) => !l.contains(kDisclaimer)) // printed once, in its own box at the end
      .join('\n');
  final isReport = reply.meta.mode == 'R';
  return ReportDocument(
    title: isReport ? 'Consultation report' : 'Clinical work-up',
    meta: [
      isReport ? 'Guided consultation' : 'Direct consult',
      'Generated ${_date(generatedAt)} ${_two(generatedAt.hour)}:${_two(generatedAt.minute)}',
      if (reply.meta.level case final level?) 'Written for $level',
      if (reply.meta.ceiling case final ceiling? when ceiling.isNotEmpty && ceiling != 'NA')
        'Confidence ceiling $ceiling',
      'Knowledge base ${reply.skillVersion}',
      'Passed the app\'s safety checks',
    ].join(' · '),
    precautions: kPdfPrecautions,
    crisisLine:
        'In an emergency (India): ${kCrisisLines.map((c) => '${c.service} ${c.number}').join(' · ')}. '
        '$kCrisisVerifiedNote',
    blocks: parseReportMarkdown(body),
    disclaimer: kDisclaimer,
    footer: 'YourCounselor · Confidential · De-identified · For professional use only',
  );
}

// --- rendering ----------------------------------------------------------------------

const _deep = PdfColor.fromInt(0xFF3F0079);
const _royal = PdfColor.fromInt(0xFF6A11BA);
const _ink = PdfColor.fromInt(0xFF1E1030);
const _muted = PdfColor.fromInt(0xFF5A5068);
const _line = PdfColor.fromInt(0xFFE6DDF0);
const _lavender = PdfColor.fromInt(0xFFF1E7FB);
const _checkInk = PdfColor.fromInt(0xFF7F440A);
const _checkBg = PdfColor.fromInt(0xFFFAEBD8);
const _crisisInk = PdfColor.fromInt(0xFF8E2A2A);
const _crisisBg = PdfColor.fromInt(0xFFF7E2DF);

/// Columns share the width by how much text they hold, so a short column such as
/// "Week" is not squeezed until its heading breaks mid-word.
Map<int, pw.TableColumnWidth> _columnWidths(List<List<String>> rows) {
  final widths = <int, pw.TableColumnWidth>{};
  for (var c = 0; c < rows.first.length; c++) {
    var weight = rows.first[c].length + 2;
    for (final row in rows.skip(1)) {
      if (c < row.length && row[c].length > weight) weight = row[c].length;
    }
    widths[c] = pw.FlexColumnWidth(weight.clamp(9, 28).toDouble());
  }
  return widths;
}

Future<pw.Font> _font(String asset) async => pw.Font.ttf(await rootBundle.load(asset));

/// Builds the PDF bytes for a delivered reply.
Future<Uint8List> buildReportPdf(ConsultReply reply, {required DateTime generatedAt}) async {
  final doc = reportDocument(reply, generatedAt: generatedAt);
  final regular = await _font('assets/fonts/NunitoSans-Regular.ttf');
  final bold = await _font('assets/fonts/NunitoSans-Bold.ttf');
  final heading = await _font('assets/fonts/Nunito-ExtraBold.ttf');
  final fallback = [
    await _font('assets/fonts/NotoSymbols-Subset.ttf'),
    await _font('assets/fonts/NotoMath-Subset.ttf'),
    await _font('assets/fonts/NotoGreek-Subset.ttf'),
  ];
  final logo = pw.MemoryImage((await rootBundle.load('assets/brand/logo_full.png')).buffer.asUint8List());

  final theme =
      pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        italic: regular,
        boldItalic: bold,
        fontFallback: fallback,
      ).copyWith(
        defaultTextStyle: pw.TextStyle(font: regular, fontSize: 10, lineSpacing: 2.5, color: _ink),
      );

  pw.TextSpan spans(String text, {pw.TextStyle? style}) => pw.TextSpan(
    style: style,
    children: [
      for (final r in inlineRuns(text))
        pw.TextSpan(
          text: r.text,
          style: pw.TextStyle(
            fontWeight: r.bold ? pw.FontWeight.bold : null,
            fontStyle: r.italic ? pw.FontStyle.italic : null,
            color: r.italic ? _muted : null,
          ),
        ),
    ],
  );

  pw.Widget rich(String text, {pw.TextStyle? style}) => pw.RichText(text: spans(text, style: style));

  pw.Widget block(PdfBlock b) => switch (b) {
    PdfHeading(:final level, :final text) => pw.Padding(
      padding: pw.EdgeInsets.only(top: level <= 3 ? 14 : 9, bottom: 5),
      child: pw.Text(
        text.replaceAll('**', ''),
        style: pw.TextStyle(
          font: heading,
          fontSize: switch (level) {
            1 || 2 => 16,
            3 => 13,
            _ => 11,
          },
          color: level <= 3 ? _deep : _royal,
        ),
      ),
    ),
    PdfParagraph(:final text) => pw.Padding(padding: const pw.EdgeInsets.only(bottom: 6), child: rich(text)),
    PdfListItem(:final marker, :final text, :final indent) => pw.Padding(
      padding: pw.EdgeInsets.only(left: 4.0 + indent * 14, bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 16,
            child: pw.Text(marker, style: const pw.TextStyle(color: _royal)),
          ),
          pw.Expanded(child: rich(text)),
        ],
      ),
    ),
    PdfTable(:final rows) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 2, bottom: 8),
      child: pw.Table(
        border: pw.TableBorder.all(color: _line, width: 0.6),
        columnWidths: _columnWidths(rows),
        children: [
          for (final (i, row) in rows.indexed)
            pw.TableRow(
              decoration: i == 0 ? const pw.BoxDecoration(color: _lavender) : null,
              repeat: i == 0,
              children: [
                for (var c = 0; c < rows.first.length; c++)
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                    child: rich(
                      c < row.length ? row[c] : '',
                      style: pw.TextStyle(fontSize: 8.5, fontWeight: i == 0 ? pw.FontWeight.bold : null),
                    ),
                  ),
              ],
            ),
        ],
      ),
    ),
    PdfQuote(:final text) => pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.fromLTRB(10, 6, 8, 6),
      decoration: const pw.BoxDecoration(
        color: _lavender,
        border: pw.Border(left: pw.BorderSide(color: _royal, width: 2.5)),
      ),
      child: rich(text),
    ),
    PdfRule() => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      child: pw.Divider(color: _line, thickness: 0.8),
    ),
  };

  final pdf = pw.Document(title: doc.title, author: 'YourCounselor', creator: 'YourCounselor app', theme: theme);
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 40),
      header: (ctx) => ctx.pageNumber == 1
          ? pw.SizedBox()
          : pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(doc.title, style: const pw.TextStyle(fontSize: 8, color: _muted)),
            ),
      footer: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _line, width: 0.6)),
        ),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(doc.footer, style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
            ),
            pw.Text(
              'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 7.5, color: _muted),
            ),
          ],
        ),
      ),
      build: (ctx) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Image(logo, height: 34),
            pw.Spacer(),
            pw.Text(
              'CONFIDENTIAL',
              style: pw.TextStyle(font: heading, fontSize: 9, color: _crisisInk, letterSpacing: 1),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          doc.title,
          style: pw.TextStyle(font: heading, fontSize: 22, color: _deep),
        ),
        pw.SizedBox(height: 3),
        pw.Text(doc.meta, style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
        pw.SizedBox(height: 12),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: _checkBg,
            borderRadius: pw.BorderRadius.circular(6),
            border: pw.Border.all(color: const PdfColor.fromInt(0xFFC98A48), width: 0.6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Safety precautions: read before use',
                style: pw.TextStyle(font: heading, fontSize: 10.5, color: _checkInk),
              ),
              pw.SizedBox(height: 5),
              for (final p in doc.precautions)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 3),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.SizedBox(
                        width: 10,
                        child: pw.Text('•', style: const pw.TextStyle(color: _checkInk)),
                      ),
                      pw.Expanded(
                        child: pw.Text(p, style: const pw.TextStyle(fontSize: 8.5, color: _checkInk)),
                      ),
                    ],
                  ),
                ),
              pw.SizedBox(height: 4),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                decoration: pw.BoxDecoration(color: _crisisBg, borderRadius: pw.BorderRadius.circular(4)),
                child: pw.Text(
                  doc.crisisLine,
                  style: pw.TextStyle(fontSize: 8.5, color: _crisisInk, fontWeight: pw.FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 6),
        ...doc.blocks.map(block),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(color: _lavender, borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Text(
            doc.disclaimer,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _deep),
          ),
        ),
      ],
    ),
  );
  return pdf.save();
}

// --- export -------------------------------------------------------------------------

/// Hands the finished PDF to the phone. Replaced in tests.
typedef ReportPdfExporter = Future<void> Function(Uint8List bytes, String fileName);

/// Opens the system "Save as PDF / Print" screen: the clinician chooses where the
/// file goes, and the app itself keeps no copy.
final reportPdfExporterProvider = Provider<ReportPdfExporter>(
  (ref) =>
      (bytes, fileName) => Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName),
);
