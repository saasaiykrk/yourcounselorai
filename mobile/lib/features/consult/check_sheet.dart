import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/content/safety_content.dart';
import '../../core/deid/cleaner.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/surfaces.dart';
import 'consult_controller.dart';

/// "Check before sending": runs the cleaner on the phone, shows what was
/// removed, asks about possible names, and keeps Send disabled until the
/// clinician attests that no identifiers remain.
///
/// Returns true when the consult was sent (the caller then clears its draft).
///
/// With [onSend], the cleaned text and counts go to that callback instead of a
/// direct consult (the guided consultation uses this for the case and for any
/// answer in which the cleaner found something).
Future<bool> showCheckSheet(
  BuildContext context, {
  required String text,
  ConsultMode mode = ConsultMode.auto,
  void Function(String text, Map<String, int> redactionCounts)? onSend,
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (_) => CheckSheet(text: text, mode: mode, onSend: onSend),
  );
  return sent ?? false;
}

enum _NameDecision { undecided, remove, keep }

const _typeLabels = <String, (String, String)>{
  'PHONE': ('phone number', 'phone numbers'),
  'EMAIL': ('email address', 'email addresses'),
  'URL': ('web link', 'web links'),
  'HANDLE': ('social handle', 'social handles'),
  'ID': ('ID number', 'ID numbers'),
  'DOB': ('date of birth', 'dates of birth'),
  'ADDRESS': ('address', 'addresses'),
  'PINCODE': ('PIN code', 'PIN codes'),
  'NAME': ('name', 'names'),
  'ORG': ('workplace or school', 'workplaces or schools'),
};

final _tag = RegExp(r'\[(?:EMAIL|URL|HANDLE|ID|DOB|PHONE|ADDRESS|PINCODE|NAME|ORG)\]');

class CheckSheet extends ConsumerStatefulWidget {
  const CheckSheet({super.key, required this.text, required this.mode, this.onSend});

  final String text;
  final ConsultMode mode;
  final void Function(String text, Map<String, int> redactionCounts)? onSend;

  @override
  ConsumerState<CheckSheet> createState() => _CheckSheetState();
}

class _CheckSheetState extends ConsumerState<CheckSheet> {
  late final CleanResult _result = clean(widget.text);
  late final Map<String, _NameDecision> _names = {for (final n in _result.warnings) n: _NameDecision.undecided};
  var _attested = false;

  /// The text that will be sent: cleaned, plus any possible names the clinician removed.
  String get _outgoing {
    var text = _result.text;
    for (final e in _names.entries) {
      if (e.value == _NameDecision.remove) text = removeName(text, e.key);
    }
    return text;
  }

  /// Counts by type only, including names the clinician removed.
  Map<String, int> get _counts {
    final counts = Map<String, int>.from(_result.counts);
    final extraNames = '[NAME]'.allMatches(_outgoing).length - '[NAME]'.allMatches(_result.text).length;
    if (extraNames > 0) counts['NAME'] = (counts['NAME'] ?? 0) + extraNames;
    return counts;
  }

  void _send() {
    final onSend = widget.onSend;
    if (onSend != null) {
      final (text, counts) = (_outgoing, _counts);
      Navigator.of(context).pop(true);
      onSend(text, counts);
      return;
    }
    final router = GoRouter.of(context);
    ref.read(consultControllerProvider.notifier).send(text: _outgoing, mode: widget.mode, redactionCounts: _counts);
    Navigator.of(context).pop(true);
    router.push('/drafting');
  }

  @override
  Widget build(BuildContext context) {
    final counts = _counts;
    final total = counts.values.fold(0, (a, b) => a + b);

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
                  onPressed: () => Navigator.of(context).pop(false),
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
                    total == 0 ? 'We found nothing to remove' : 'We removed $total ${total == 1 ? 'item' : 'items'}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  if (counts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final e in counts.entries) StatusPill(_describe(e.key, e.value), tone: Tone.check),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Text.rich(
                      TextSpan(children: _spans(_outgoing)),
                      style: const TextStyle(fontSize: 15, height: 1.7, color: AppColors.ink),
                    ),
                  ),
                  for (final name in _names.keys) ...[
                    const SizedBox(height: 14),
                    _NameQuestion(
                      name: name,
                      decision: _names[name]!,
                      onDecide: (d) => setState(() => _names[name] = d),
                    ),
                  ],
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

  static String _describe(String type, int n) {
    final (one, many) = _typeLabels[type] ?? ('identifier', 'identifiers');
    return '$n ${n == 1 ? one : many}';
  }

  /// Tags get a tinted chip; undecided or kept possible names are underlined.
  List<InlineSpan> _spans(String text) {
    final flagged = [
      for (final e in _names.entries)
        if (e.value != _NameDecision.remove) e.key,
    ];
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _tag.allMatches(text)) {
      spans.addAll(_plain(text.substring(last, m.start), flagged));
      spans.add(_tagChip(m.group(0)!));
      last = m.end;
    }
    spans.addAll(_plain(text.substring(last), flagged));
    return spans;
  }

  static List<InlineSpan> _plain(String text, List<String> flagged) {
    if (flagged.isEmpty || text.isEmpty) return [TextSpan(text: text)];
    final pattern = RegExp('(?<![A-Za-z])(${flagged.map(RegExp.escape).join('|')})(?![A-Za-z])');
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in pattern.allMatches(text)) {
      spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(
        TextSpan(
          text: m.group(0),
          style: const TextStyle(
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.dashed,
            decorationColor: AppColors.checkDot,
            decorationThickness: 2,
          ),
        ),
      );
      last = m.end;
    }
    spans.add(TextSpan(text: text.substring(last)));
    return spans;
  }

  static InlineSpan _tagChip(String tag) => WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: AppColors.checkBg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        tag,
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
                    Expanded(
                      child: Text(
                        'Is “$name” a name?',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.checkInk),
                      ),
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
