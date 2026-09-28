import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/content/safety_content.dart';
import '../../core/demo/preview_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/surfaces.dart';

/// "Check before sending": shows what the cleaner removed, asks about
/// uncertain names, and keeps Send disabled until the clinician attests.
Future<void> showCheckSheet(BuildContext context, {required String text, required ConsultMode mode}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (_) => CheckSheet(text: text, mode: mode),
  );
}

enum _NameDecision { undecided, remove, keep }

class CheckSheet extends StatefulWidget {
  const CheckSheet({super.key, required this.text, required this.mode});

  final String text;
  final ConsultMode mode;

  @override
  State<CheckSheet> createState() => _CheckSheetState();
}

class _CheckSheetState extends State<CheckSheet> {
  var _decision = _NameDecision.undecided;
  var _attested = false;

  void _send() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push('/drafting');
  }

  @override
  Widget build(BuildContext context) {
    // Preview data until the Dart port of app/deid.py lands (plan Step 3).
    final preview = previewCleaner(removePossibleName: _decision == _NameDecision.remove);
    final name = previewCleaner(removePossibleName: false).possibleName;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
            child: Row(
              children: [
                const Expanded(child: Text('Check before sending', style: AppText.sheetTitle)),
                IconButton(
                  tooltip: 'Close and edit',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'We removed ${preview.removedTotal} items',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final e in preview.removed.entries) StatusPill('${e.value} ${e.key}', tone: Tone.check),
                    ],
                  ),
                  const SizedBox(height: 14),
                  AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Text.rich(
                      TextSpan(children: [for (final s in preview.segments) _segment(s)]),
                      style: const TextStyle(fontSize: 15, height: 1.7, color: AppColors.ink),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _NameQuestion(name: name, decision: _decision, onDecide: (d) => setState(() => _decision = d)),
                  const SizedBox(height: 14),
                  Material(
                    color: AppColors.lavender,
                    borderRadius: BorderRadius.circular(16),
                    child: CheckboxListTile(
                      value: _attested,
                      onChanged: (v) => setState(() => _attested = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: const Text(
                        'This contains no names or other identifiers of my client.',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
            child: FilledButton.icon(
              onPressed: _attested ? _send : null,
              icon: const Icon(Icons.lock_outline_rounded),
              label: Text(_attested ? 'Send securely' : 'Tick the box to send'),
            ),
          ),
        ],
      ),
    );
  }

  InlineSpan _segment(CleanSegment s) {
    if (s.isTag) {
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: AppColors.checkBg, borderRadius: BorderRadius.circular(6)),
          child: Text(
            s.text,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.checkInk,
              letterSpacing: 0.3,
            ),
          ),
        ),
      );
    }
    if (s.possibleName) {
      return TextSpan(
        text: s.text,
        style: const TextStyle(
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.dashed,
          decorationColor: AppColors.checkDot,
          decorationThickness: 2,
        ),
      );
    }
    return TextSpan(text: s.text);
  }
}

class _NameQuestion extends StatelessWidget {
  const _NameQuestion({required this.name, required this.decision, required this.onDecide});

  final String name;
  final _NameDecision decision;
  final ValueChanged<_NameDecision> onDecide;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderColor: AppColors.checkBorder,
      borderWidth: 1.5,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: decision == _NameDecision.undecided
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.help_outline_rounded, size: 19, color: AppColors.checkInk),
                    const SizedBox(width: 8),
                    Text(
                      'Is “$name” a name?',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.checkInk),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        onPressed: () => onDecide(_NameDecision.remove),
                        child: const Text('Yes, remove'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          foregroundColor: AppColors.ink,
                          side: const BorderSide(color: AppColors.inputBorder, width: 1.5),
                          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        onPressed: () => onDecide(_NameDecision.keep),
                        child: const Text('No, keep it'),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Text(
                    decision == _NameDecision.remove ? 'Removed “$name”' : 'Kept “$name” as written',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(onPressed: () => onDecide(_NameDecision.undecided), child: const Text('Undo')),
              ],
            ),
    );
  }
}
