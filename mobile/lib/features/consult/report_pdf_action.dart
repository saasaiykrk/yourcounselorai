import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import 'report_pdf.dart';

/// "Download PDF" for one delivered reply, shared by the clinician's reply screen
/// and the admin consult view: confirm the precautions, then (for admins) record
/// the download in the audit log, then build the PDF on the phone and hand it to
/// the system "Save as PDF / Print" screen. Nothing is exported if [record] fails.
/// [onBusy] is told when work starts (after the confirmation) and ends.
/// A clinician's own download needs a plan with PDF downloads (Practice, BYOK Scale, Scale).
Future<void> downloadReportPdf(
  BuildContext context,
  WidgetRef ref,
  ConsultReply reply, {
  Future<void> Function()? record,
  void Function(bool busy)? onBusy,
}) async {
  Me? me;
  if (record == null) {
    try {
      me = await ref.read(meProvider.future);
    } catch (_) {
      me = null; // offline: the PDF is built on the phone; nothing to check against
    }
    if (!context.mounted) return;
  }
  if (me?.has('pdf') == false) {
    final see = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PDF downloads'),
        content: const Text(
          'Downloading reports as PDF with your name is part of Practice, BYOK Scale and Scale.',
          style: AppText.smallMuted,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('See plans')),
        ],
      ),
    );
    if (see == true && context.mounted) context.push('/pricing');
    return;
  }
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Download this report as a PDF?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The file leaves the app\'s protection once you save or share it. It contains '
              'de-identified information only.${record != null ? ' The download is recorded in the audit log.' : ''}',
              style: AppText.smallMuted,
            ),
            const SizedBox(height: 10),
            for (final p in const [
              'Save it only to a protected device or folder.',
              'Do not add client names or contact details to it.',
              'Do not send it by ordinary email or messaging apps.',
              'Delete it when you no longer need it.',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2, right: 8),
                      child: Icon(Icons.shield_outlined, size: 16, color: AppColors.royalPurple),
                    ),
                    Expanded(child: Text(p, style: const TextStyle(fontSize: 14.5, height: 1.4))),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            const Text(
              'The PDF starts with these precautions and the crisis numbers, and ends with the disclaimer.',
              style: AppText.caption,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Download PDF')),
      ],
    ),
  );
  if (go != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final export = ref.read(reportPdfExporterProvider);
  onBusy?.call(true);
  try {
    await _record(messenger, record) && await _export(messenger, export, reply);
  } finally {
    onBusy?.call(false);
  }
}

Future<bool> _record(ScaffoldMessengerState messenger, Future<void> Function()? record) async {
  if (record != null) {
    try {
      await record();
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't record the download, so nothing was saved.")));
      return false;
    }
  }
  return true;
}

Future<bool> _export(ScaffoldMessengerState messenger, ReportPdfExporter export, ConsultReply reply) async {
  try {
    final now = DateTime.now();
    final bytes = await buildReportPdf(reply, generatedAt: now);
    await export(bytes, reportPdfFileName(now));
    return true;
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text("Couldn't create the PDF. Please try again.")));
    return false;
  }
}

/// A delivered reply from the consult history, in the shape the PDF builder takes.
ConsultReply replyFromTurn(ConsultTurn t, String consultId) => ConsultReply(
  turnId: t.id,
  conversationId: consultId,
  delivered: t.delivered,
  text: t.reply,
  skillVersion: t.skillVersion,
  meta: ReplyMeta(mode: t.mode, level: t.level),
);
