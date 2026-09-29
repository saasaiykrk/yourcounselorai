import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/content/safety_content.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/layout.dart';
import 'consult_controller.dart';

/// "Report a problem" on any reply. Categories match the backend's
/// `/v1/incidents` values.
Future<void> showReportSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (_) => const ReportSheet(),
  );
}

class ReportSheet extends ConsumerStatefulWidget {
  const ReportSheet({super.key});

  @override
  ConsumerState<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<ReportSheet> {
  ReportCategory? _category;
  bool _busy = false;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(consultControllerProvider.notifier).report(category: _category!, note: _note.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Thank you. Our clinical safety team will review this reply.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't send the report. Check your connection and try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
            child: Row(
              children: [
                const Expanded(child: Text('Report a problem', style: AppText.sheetTitle)),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Our clinical safety team reviews every report.', style: AppText.smallMuted),
                  const SizedBox(height: 16),
                  const Text('What went wrong?', style: AppText.label),
                  const SizedBox(height: 8),
                  for (final c in ReportCategory.values) ...[
                    ChoiceCard(title: c.label, selected: _category == c, onTap: () => setState(() => _category = c)),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 8),
                  const Text('Note (optional)', style: AppText.label),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _note,
                    minLines: 3,
                    maxLines: 5,
                    maxLength: 2000,
                    autocorrect: false,
                    enableIMEPersonalizedLearning: false,
                    decoration: const InputDecoration(hintText: 'What should it have said?', counterText: ''),
                  ),
                  const SizedBox(height: 6),
                  const Text("Please don't include client names or contact details.", style: AppText.caption),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
            child: FilledButton(onPressed: _category == null || _busy ? null : _send, child: const Text('Send report')),
          ),
        ],
      ),
    );
  }
}
