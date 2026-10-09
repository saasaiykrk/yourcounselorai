import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Renders reply markdown in the app's style. Tables keep fixed-width
/// columns and scroll sideways instead of squashing text on a phone; the
/// scrollbar sits below the table, clear of the text.
/// Links are not followed: replies should never send clinicians off-app.
class ReplyMarkdown extends StatelessWidget {
  const ReplyMarkdown(this.data, {super.key});

  final String data;

  @override
  Widget build(BuildContext context) {
    final base = MarkdownStyleSheet.fromTheme(Theme.of(context));
    TextStyle f(TextStyle s) => s.copyWith(fontFamilyFallback: kSymbolFallbacks);
    return MarkdownBody(
      data: data,
      selectable: true,
      styleSheet: base.copyWith(
        p: f(AppText.small),
        pPadding: const EdgeInsets.only(bottom: 4),
        h1: f(AppText.sectionTitle),
        h2: f(AppText.sectionTitle),
        h3: f(AppText.sectionTitle),
        h4: f(const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.deepPurple)),
        strong: const TextStyle(fontWeight: FontWeight.w800),
        listBullet: f(AppText.small),
        blockSpacing: 10,
        tableHead: f(const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink)),
        tableBody: f(const TextStyle(fontSize: 13, height: 1.4, color: AppColors.ink)),
        tableBorder: TableBorder.all(color: AppColors.line),
        tableHeadAlign: TextAlign.left,
        tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        tableCellsDecoration: const BoxDecoration(color: AppColors.surface),
        // 140px columns: a two-column table (e.g. the Case Snapshot) fits a 360px phone without
        // scrolling; wider tables still scroll sideways.
        tableColumnWidth: const FixedColumnWidth(140),
        tableScrollbarThumbVisibility: true,
        // Room under the table for the sideways scrollbar, so it never covers the last row.
        tablePadding: const EdgeInsets.only(bottom: 16),
        blockquoteDecoration: BoxDecoration(color: AppColors.quiet, borderRadius: BorderRadius.circular(12)),
        blockquotePadding: const EdgeInsets.all(12),
        code: const TextStyle(fontSize: 13, backgroundColor: AppColors.quiet),
      ),
    );
  }
}

/// Copies reply text to the clipboard with a confirmation.
void copyReplyText(BuildContext context, String text, {String message = 'Copied'}) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
