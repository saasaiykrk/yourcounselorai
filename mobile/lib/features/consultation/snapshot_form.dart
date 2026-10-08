import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_models.dart';
import '../../core/deid/cleaner.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Saves the form. [done]: complete, move on; [skipRemaining]: empty fields become Skipped.
typedef SnapshotSave = Future<bool> Function(Map<String, SnapshotEntry> fields, {bool done, bool skipRemaining});

/// The Case Snapshot form (CR-001): every field on one scrollable screen, grouped. Fields taken
/// from the case text show a green ✓ and stay editable; every other field needs a value or a
/// status before "Continue". Typed text is checked by the on-phone cleaner as it is typed:
/// an identifier must be removed, a possible name or employer must be replaced (or, outside
/// Occupation, confirmed as not a name).
class SnapshotForm extends StatefulWidget {
  const SnapshotForm({
    super.key,
    required this.snapshot,
    required this.busy,
    required this.onSave,
    this.editing = false,
    this.onCancel,
  });

  final CaseSnapshot snapshot;
  final bool busy;
  final SnapshotSave onSave;

  /// Correcting a completed snapshot: one "Save changes" button, no skip.
  final bool editing;
  final VoidCallback? onCancel;

  @override
  State<SnapshotForm> createState() => _SnapshotFormState();
}

class _Draft {
  _Draft(SnapshotField f)
    : chips = [...f.selected],
      text = TextEditingController(text: f.value),
      status = f.status,
      prefilled = f.prefilled,
      original = (f.selected.join('|'), f.value, f.status);

  final List<String> chips;
  final TextEditingController text;
  SnapshotStatus? status;
  bool prefilled;
  bool keepPossibleName = false;
  final (String, String, SnapshotStatus?) original;

  bool get changed => (chips.join('|'), text.text.trim(), status) != original;
}

enum _Issue { identifier, possibleName, badNumber }

class _SnapshotFormState extends State<SnapshotForm> {
  late final Map<String, _Draft> _drafts = {for (final f in widget.snapshot.fields) f.key: _Draft(f)};

  CaseSnapshot get _s => widget.snapshot;

  @override
  void dispose() {
    for (final d in _drafts.values) {
      d.text.dispose();
    }
    super.dispose();
  }

  // --- rules -------------------------------------------------------------------------
  _Issue? _issue(SnapshotField f, _Draft d) {
    final t = d.text.text.trim();
    if (d.status != null || t.isEmpty) return null;
    if (f.text == 'number') {
      final n = int.tryParse(t);
      return n == null || n < 1 || n > 120 ? _Issue.badNumber : null;
    }
    final r = clean(t);
    if (!r.isClean) return _Issue.identifier;
    if (r.warnings.isNotEmpty && (f.key == 'occupation' || !d.keepPossibleName)) return _Issue.possibleName;
    return null;
  }

  bool _resolved(SnapshotField f, _Draft d) {
    if (d.status != null) return true;
    final t = d.text.text.trim();
    if (f.text == 'required' || f.text == 'number') return t.isNotEmpty;
    return d.chips.isNotEmpty || t.isNotEmpty;
  }

  bool _ok(SnapshotField f) => (_resolved(f, _drafts[f.key]!) || f.optional) && _issue(f, _drafts[f.key]!) == null;

  int get _remaining => widget.snapshot.fields.where((f) => !_ok(f)).length;

  /// Everything that can be sent: resolved and free of identifier problems.
  /// A field left "Skipped" stays skipped until the clinician fills it (it is never sent back).
  Map<String, SnapshotEntry> _entries({bool changedOnly = false}) => {
    for (final f in _s.fields)
      if (_ok(f) &&
          _resolved(f, _drafts[f.key]!) &&
          _drafts[f.key]!.status != SnapshotStatus.skipped &&
          (!changedOnly || _drafts[f.key]!.changed))
        f.key: _drafts[f.key]!.status != null
            ? SnapshotEntry(status: _drafts[f.key]!.status)
            : SnapshotEntry(chips: [..._drafts[f.key]!.chips], text: _drafts[f.key]!.text.text.trim()),
  };

  // --- actions -----------------------------------------------------------------------
  void _toggleChip(SnapshotField f, String chip) {
    final d = _drafts[f.key]!;
    final wasRisk = f.key == 'risk_screening' && d.chips.contains('Risk present');
    setState(() {
      d.status = null;
      d.prefilled = false;
      if (f.multi) {
        d.chips.contains(chip) ? d.chips.remove(chip) : d.chips.add(chip);
      } else {
        final on = d.chips.contains(chip);
        d.chips
          ..clear()
          ..addAll(on ? const [] : [chip]);
      }
    });
    // Gate 1 straight away: the emergency guidance comes before the rest of the form.
    if (f.key == 'risk_screening' && !wasRisk && d.chips.contains('Risk present')) {
      widget.onSave(_entries());
    }
  }

  void _setStatus(SnapshotField f, SnapshotStatus s) {
    final d = _drafts[f.key]!;
    setState(() {
      d.prefilled = false;
      if (d.status == s) {
        d.status = null;
      } else {
        d.status = s;
        d.chips.clear();
        d.text.clear();
      }
    });
  }

  Future<void> _skipRemaining() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_s.text('skip_confirm_title')),
        content: Text(_s.text('skip_confirm_body')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(_s.text('skip_confirm_ok'))),
        ],
      ),
    );
    if (go == true && mounted) await widget.onSave(_entries(), skipRemaining: true);
  }

  // --- layout ------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    // Asked for this case, by group; the rest (not needed for this case) fold away at the end.
    final groups = <String, List<SnapshotField>>{};
    for (final f in _s.fields.where((f) => !f.optional)) {
      groups.putIfAbsent(f.group, () => []).add(f);
    }
    final optional = _s.fields.where((f) => f.optional).toList();
    final remaining = _remaining;
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('snapshot-form'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(_s.text('form_title'), style: AppText.sectionTitle),
              const SizedBox(height: 4),
              Text(_s.text('form_intro'), style: AppText.smallMuted),
              for (final g in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
                  child: Text(g.key.toUpperCase(), style: AppText.caption.copyWith(letterSpacing: 0.8)),
                ),
                for (final f in g.value) _fieldCard(f),
              ],
              if (optional.isNotEmpty) ...[
                const SizedBox(height: 14),
                Material(
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: AppColors.line),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    key: const ValueKey('snapshot-optional'),
                    title: Text(
                      '${_s.text('optional_title')} (${optional.length})',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(_s.text('optional_intro'), style: AppText.caption),
                    childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                    children: [for (final f in optional) _fieldCard(f)],
                  ),
                ),
              ],
            ],
          ),
        ),
        Material(
          color: AppColors.surface,
          elevation: 8,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (remaining > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        _s.text('remaining', {'n': '$remaining'}),
                        textAlign: TextAlign.center,
                        style: AppText.caption,
                      ),
                    ),
                  if (widget.editing)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: widget.busy ? null : widget.onCancel,
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: widget.busy || remaining > 0
                                ? null
                                : () => widget.onSave(_entries(changedOnly: true)),
                            child: const Text('Save changes'),
                          ),
                        ),
                      ],
                    )
                  else ...[
                    FilledButton(
                      key: const ValueKey('snapshot-continue'),
                      onPressed: widget.busy || remaining > 0 ? null : () => widget.onSave(_entries(), done: true),
                      child: Text(widget.busy ? 'Saving…' : _s.text('continue')),
                    ),
                    TextButton(
                      onPressed: widget.busy || remaining == 0 ? null : _skipRemaining,
                      child: Text(_s.text('skip_remaining')),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fieldCard(SnapshotField f) {
    final d = _drafts[f.key]!;
    final ok = _ok(f);
    final issue = _issue(f, d);
    final empty = !_resolved(f, d);
    final tick = d.prefilled && ok;
    final border = tick
        ? AppColors.doneBorder
        : ok
        ? AppColors.line
        : AppColors.checkBorder;
    // One semantics group per field, so a screen reader moves field by field.
    return Semantics(
      container: true,
      label: f.question,
      child: Container(
        key: ValueKey('snapshot-${f.key}'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: ok ? AppColors.surface : AppColors.checkBg.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: ok ? 1 : 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  // Read once, as the group's label.
                  child: ExcludeSemantics(
                    child: Text(
                      f.question,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.35),
                    ),
                  ),
                ),
                if (tick)
                  Semantics(
                    label: _s.text('prefilled_badge'),
                    child: Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.doneBg, borderRadius: BorderRadius.circular(999)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_rounded, size: 14, color: AppColors.doneInk),
                          const SizedBox(width: 3),
                          Text(
                            _s.text('prefilled_badge'),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.doneInk),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            if (d.status == SnapshotStatus.skipped)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(_s.statusLabel(SnapshotStatus.skipped), style: AppText.caption),
              ),
            if (!ok && issue == null && !(f.optional && empty))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  _s.text('needs_answer'),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.checkInk, fontWeight: FontWeight.w600),
                ),
              ),
            if (f.chips.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in f.chips)
                    f.multi
                        ? FilterChip(
                            label: Text(c),
                            selected: d.chips.contains(c),
                            onSelected: widget.busy ? null : (_) => _toggleChip(f, c),
                          )
                        : ChoiceChip(
                            label: Text(c),
                            selected: d.chips.contains(c),
                            onSelected: widget.busy ? null : (_) => _toggleChip(f, c),
                          ),
                ],
              ),
            ],
            if (f.text != 'none') ...[const SizedBox(height: 8), _textField(f, d, issue)],
            if (f.helper.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(f.helper, style: AppText.caption),
              ),
            if (f.statuses.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final s in f.statuses)
                    ChoiceChip(
                      key: ValueKey('status-${f.key}-${s.api}'),
                      label: Text(_s.statusLabel(s), style: const TextStyle(fontSize: 12.5)),
                      visualDensity: VisualDensity.compact,
                      selected: d.status == s,
                      onSelected: widget.busy ? null : (_) => _setStatus(f, s),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _textField(SnapshotField f, _Draft d, _Issue? issue) {
    final words = issue == _Issue.possibleName ? clean(d.text.text.trim()).warnings.join(', ') : '';
    final error = switch (issue) {
      _Issue.identifier => _s.text('identifier_block'),
      _Issue.possibleName => _s.text('possible_name', {'words': words}),
      _Issue.badNumber => '1 to 120',
      null => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: ValueKey('snapshot-text-${f.key}'),
          controller: d.text,
          enabled: !widget.busy,
          maxLength: f.text == 'number' ? 3 : 200,
          minLines: 1,
          maxLines: f.text == 'required' ? 3 : 2,
          keyboardType: f.text == 'number' ? TextInputType.number : TextInputType.text,
          inputFormatters: f.text == 'number' ? [FilteringTextInputFormatter.digitsOnly] : null,
          // No autocorrect learning or suggestions on clinical text.
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            hintText: switch (f.text) {
              'number' => _s.text('number_hint'),
              'required' => _s.text('required_hint'),
              _ => _s.text('details_hint'),
            },
            errorText: error,
            errorMaxLines: 3,
          ),
          onChanged: (_) => setState(() {
            d.status = null;
            d.prefilled = false;
            d.keepPossibleName = false;
          }),
        ),
        if (issue == _Issue.possibleName && f.key != 'occupation')
          TextButton(onPressed: () => setState(() => d.keepPossibleName = true), child: Text(_s.text('keep_anyway'))),
      ],
    );
  }
}

/// The completed snapshot, read-only, exactly as the report will show it (answered fields only, then
/// the "Ask in the next session" line), with an Edit link. Not known / N/A fields are named once,
/// muted, so the clinician sees what is left out.
class SnapshotSummary extends StatelessWidget {
  const SnapshotSummary({super.key, required this.snapshot, required this.onEdit});

  final CaseSnapshot snapshot;
  final VoidCallback? onEdit;

  String _shown(SnapshotField f) {
    final chips = f.selected.join(', ');
    final value = chips.isNotEmpty && f.value.isNotEmpty ? '$chips — ${f.value}' : chips + f.value;
    return f.text == 'number' ? '$value years' : value;
  }

  List<String> get _leftOut => [
    for (final f in snapshot.fields)
      if (f.status == SnapshotStatus.notKnown || f.status == SnapshotStatus.notApplicable) f.label,
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(snapshot.text('confirm_title'), style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                if (onEdit != null) TextButton(onPressed: onEdit, child: Text(snapshot.text('edit'))),
              ],
            ),
            Text(snapshot.text('confirm_intro'), style: AppText.caption),
            const SizedBox(height: 6),
            for (final f in snapshot.fields.where((f) => f.status == null && f.resolved))
              Padding(
                padding: const EdgeInsets.only(bottom: 6, right: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 120, child: Text(f.label, style: AppText.caption)),
                    Expanded(child: Text(_shown(f), style: const TextStyle(fontSize: 14, height: 1.35))),
                  ],
                ),
              ),
            if (snapshot.askNext.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: Text(
                  '${snapshot.text('ask_next_heading')}: ${snapshot.askNext.join(', ')}',
                  style: const TextStyle(fontSize: 13.5, color: AppColors.checkInk, fontWeight: FontWeight.w600),
                ),
              ),
            if (_leftOut.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: Text('${snapshot.text('left_out')}: ${_leftOut.join(', ')}', style: AppText.caption),
              ),
          ],
        ),
      ),
    );
  }
}
