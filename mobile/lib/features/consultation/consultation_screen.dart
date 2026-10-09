import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/api/api_models.dart';
import '../../core/deid/cleaner.dart';
import '../../core/security/screen_protection.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/safety_widgets.dart';
import '../../core/widgets/surfaces.dart';
import '../consult/check_sheet.dart';
import '../consult/consult_controller.dart';
import 'consultation_controller.dart';
import 'snapshot_form.dart';

/// The guided consultation: one question at a time, then "Your consultation is
/// ready" and the report. Everything typed is cleaned on the phone before it is
/// sent; the server cleans it again and keeps the de-identified state.
class ConsultationScreen extends ConsumerStatefulWidget {
  const ConsultationScreen({super.key});

  @override
  ConsumerState<ConsultationScreen> createState() => _ConsultationScreenState();
}

class _ConsultationScreenState extends ConsumerState<ConsultationScreen> {
  // Answers live only in memory and are never written to disk.
  final _answer = TextEditingController();
  final _scroll = ScrollController();

  /// Correcting a completed Case Snapshot (before or after the report).
  bool _editingSnapshot = false;
  bool _readExtra = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_readExtra) {
      _readExtra = true;
      _editingSnapshot = GoRouterState.of(context).extra == kEditSnapshot;
    }
  }

  ConsultationController get _ctrl => ref.read(consultationControllerProvider.notifier);

  @override
  void dispose() {
    _answer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  });

  /// Cleans on the phone; sends straight away when nothing was found, otherwise
  /// shows the check panel first. Returns after the text was handed over.
  Future<void> _cleanThen(String raw, Future<bool> Function(String cleaned) send) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    final result = clean(text);
    if (result.isClean && result.warnings.isEmpty) {
      if (await send(result.text) && mounted) _answer.clear();
      return;
    }
    await showCheckSheet(
      context,
      text: text,
      onSend: (cleaned, _) async {
        if (await send(cleaned) && mounted) _answer.clear();
      },
    );
  }

  Future<void> _send([String? option]) => _cleanThen(option ?? _answer.text, _ctrl.answer);

  Future<void> _generate({required bool force}) async {
    final router = GoRouter.of(context);
    final reply = await _ctrl.generateReport(force: force);
    if (reply == null || !mounted) return;
    // Show it on the existing reply screen; follow-ups continue the same conversation.
    ref.read(consultControllerProvider.notifier).showReply(reply);
    final (route, extra) = routeForOutcome(ConsultReplied(reply));
    router.pushReplacement(route, extra: extra);
  }

  Future<bool> _saveSnapshot(Map<String, SnapshotEntry> fields, {bool done = false, bool skipRemaining = false}) async {
    final saved = await _ctrl.saveSnapshot(fields, done: done, skipRemaining: skipRemaining);
    if (saved && _editingSnapshot && mounted) setState(() => _editingSnapshot = false);
    return saved;
  }

  Future<void> _editFact(String field, String current) async {
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => _EditFactDialog(label: consultationFieldLabel(field), initial: current),
    );
    if (value == null || !mounted) return;
    if (value.trim().isEmpty) {
      await _ctrl.editFact(field, null);
    } else {
      await _cleanThen(value, (cleaned) => _ctrl.editFact(field, cleaned));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(consultationControllerProvider);
    ref.listen(consultationControllerProvider, (_, _) => _scrollToEnd());
    final c = s.consultation;

    return ProtectedScreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close (you can continue later)',
            onPressed: () => context.go('/consult'),
            icon: const Icon(Icons.close_rounded),
          ),
          titleSpacing: 0,
          title: const Text('Guided consultation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          actions: [
            if (c != null && c.stage == ConsultationStage.questioning)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(child: Text('${c.questionsAsked} of up to ${c.maxQuestions}', style: AppText.caption)),
              ),
          ],
        ),
        body: s.generating
            ? const _Generating()
            : c?.snapshot != null && (c!.stage == ConsultationStage.snapshot || _editingSnapshot)
            ? Column(
                children: [
                  if (s.error != null && !s.busy)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: _ErrorCard(error: s.error!, onRetry: null),
                    ),
                  Expanded(
                    child: SnapshotForm(
                      snapshot: c.snapshot!,
                      busy: s.busy,
                      editing: _editingSnapshot,
                      onCancel: () => setState(() => _editingSnapshot = false),
                      onSave: _saveSnapshot,
                    ),
                  ),
                ],
              )
            : SafeArea(
                top: false,
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        children: [
                          if (s.caseText != null)
                            _Bubble(mine: true, label: 'Your case', text: s.caseText!)
                          else if (c != null && c.caseSummary.isNotEmpty)
                            _Bubble(mine: false, label: 'Case so far', text: c.caseSummary),
                          if (c != null) ..._conversation(c),
                          if (s.busy) const _Thinking(),
                          if (s.error != null && !s.busy)
                            _ErrorCard(error: s.error!, onRetry: c == null ? null : _ctrl.retry),
                          if (c != null && !s.busy) ..._stageBody(c),
                        ],
                      ),
                    ),
                    if (c != null && c.stage == ConsultationStage.questioning)
                      _Composer(
                        controller: _answer,
                        enabled: !s.busy,
                        options: c.question?.options ?? const [],
                        onSend: _send,
                        onDontKnow: _ctrl.dontKnow,
                        onSkip: _ctrl.skip,
                        onGenerateNow: c.facts.isEmpty && c.snapshot == null ? null : () => _confirmGenerateNow(c),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  List<Widget> _conversation(Consultation c) => [
    for (final t in c.transcript) ...[
      if (t.question.isNotEmpty) _Bubble(mine: false, text: t.question),
      _Bubble(mine: true, text: t.answer, muted: t.answer.startsWith('(')),
    ],
    if (c.briefAnswer.isNotEmpty) _Bubble(mine: false, label: 'Answer', text: c.briefAnswer, info: true),
  ];

  List<Widget> _stageBody(Consultation c) => switch (c.stage) {
    ConsultationStage.questioning when c.question != null => [
      if (c.caseType.isNotEmpty) _CaseAssessment(caseType: c.caseType, needed: c.infoNeeded),
      _QuestionBubble(question: c.question!),
      if (c.facts.isNotEmpty) _KnownSoFar(facts: c.facts, unknown: c.unknown, onEdit: _editFact),
    ],
    ConsultationStage.ready => [
      _ReadyCard(
        consultation: c,
        onEdit: _editFact,
        onEditSnapshot: () => setState(() => _editingSnapshot = true),
        onGenerate: () => _generate(force: false),
      ),
    ],
    ConsultationStage.safetyStop => [
      _SafetyStop(
        onManaged: () => _ctrl.confirmSafety(managed: true),
        onAbsent: () => _ctrl.confirmSafety(managed: false),
      ),
    ],
    ConsultationStage.completed => [
      _DoneCard(
        onEditSnapshot: c.snapshot == null ? null : () => setState(() => _editingSnapshot = true),
        onOpen: c.reply == null
            ? null
            : () {
                ref.read(consultControllerProvider.notifier).showReply(c.reply!);
                context.pushReplacement('/reply');
              },
      ),
    ],
    _ => const [],
  };

  Future<void> _confirmGenerateNow(Consultation c) async {
    final missing = [
      if (c.snapshot == null) // the completed Case Snapshot already holds these
        for (final f in const ['presenting_concern', 'age_gender', 'risk_screening', 'duration_onset'])
          if (!c.facts.containsKey(f) && !c.unknown.contains(f)) consultationFieldLabel(f),
    ];
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generate the report now?'),
        content: Text(
          missing.isEmpty
              ? 'The report will use what you have told us so far.'
              : 'Not answered yet: ${missing.join(', ')}. The report will mark these as not provided.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep answering')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Generate now')),
        ],
      ),
    );
    if (go == true && mounted) await _generate(force: true);
  }
}

// --- pieces ---------------------------------------------------------------------------

class _Bubble extends StatelessWidget {
  const _Bubble({required this.mine, required this.text, this.label, this.muted = false, this.info = false});

  final bool mine;
  final String text;
  final String? label;
  final bool muted;
  final bool info;

  @override
  Widget build(BuildContext context) {
    final bg = mine ? AppColors.royalPurple : (info ? AppColors.lavender : AppColors.surface);
    final fg = mine ? Colors.white : AppColors.ink;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
            border: mine ? null : Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label != null)
                Text(
                  label!.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: mine ? Colors.white70 : AppColors.muted,
                  ),
                ),
              Text(
                text,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: muted ? fg.withValues(alpha: 0.75) : fg,
                  fontStyle: muted ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestionBubble extends StatelessWidget {
  const _QuestionBubble({required this.question});

  final ConsultationQuestion question;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: AppColors.royalPurple, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (question.clarify) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.checkBg, borderRadius: BorderRadius.circular(999)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.rule_rounded, size: 14, color: AppColors.checkInk),
                    SizedBox(width: 4),
                    Text(
                      'Checking your last answer',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.checkInk),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            Semantics(
              header: true,
              child: Text(
                question.question,
                style: const TextStyle(fontSize: 16, height: 1.45, fontWeight: FontWeight.w700),
              ),
            ),
            if (question.why.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, size: 15, color: AppColors.muted),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Why we ask: ${question.why}', style: AppText.smallMuted)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What the AI understood the case to be, and what the report still needs — so the clinician
/// sees a structured assessment, not open-ended chat.
class _CaseAssessment extends StatelessWidget {
  const _CaseAssessment({required this.caseType, required this.needed});

  final String caseType;
  final List<String> needed;

  static const _shown = 5;

  @override
  Widget build(BuildContext context) {
    final more = needed.length - _shown;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.lavender,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Case identified', style: AppText.caption),
          const SizedBox(height: 2),
          Text(caseType, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.35)),
          const SizedBox(height: 2),
          const Text('A working label for planning the questions, not a diagnosis.', style: AppText.caption),
          if (needed.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Still needed for the report (${needed.length})', style: AppText.caption),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final f in needed.take(_shown))
                  Chip(
                    label: Text(consultationFieldLabel(f)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.line),
                    labelStyle: const TextStyle(fontSize: 12.5, color: AppColors.ink),
                  ),
                if (more > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('+$more more', style: AppText.caption),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Working out the next question…', style: AppText.smallMuted),
          ],
        ),
      ),
    );
  }
}

class _KnownSoFar extends StatelessWidget {
  const _KnownSoFar({required this.facts, required this.unknown, required this.onEdit});

  final Map<String, String> facts;
  final List<String> unknown;
  final void Function(String field, String current) onEdit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(
          'What we know so far (${facts.length})',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        subtitle: const Text('Tap a line to correct it', style: AppText.caption),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        children: [_FactList(facts: facts, unknown: unknown, onEdit: onEdit)],
      ),
    );
  }
}

class _FactList extends StatelessWidget {
  const _FactList({required this.facts, required this.unknown, required this.onEdit});

  final Map<String, String> facts;
  final List<String> unknown;
  final void Function(String field, String current) onEdit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in facts.entries)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            title: Text(consultationFieldLabel(e.key), style: AppText.caption),
            subtitle: Text(e.value, style: const TextStyle(fontSize: 14.5, color: AppColors.ink, height: 1.4)),
            trailing: const Icon(Icons.edit_outlined, size: 18, color: AppColors.muted),
            onTap: () => onEdit(e.key, e.value),
          ),
        if (unknown.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text('Not known: ${unknown.map(consultationFieldLabel).join(', ')}', style: AppText.smallMuted),
          ),
      ],
    );
  }
}

class _ReadyCard extends StatelessWidget {
  const _ReadyCard({
    required this.consultation,
    required this.onEdit,
    required this.onEditSnapshot,
    required this.onGenerate,
  });

  final Consultation consultation;
  final void Function(String field, String current) onEdit;
  final VoidCallback onEditSnapshot;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final c = consultation;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.lavender, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.task_alt_rounded, color: AppColors.royalPurple),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your consultation is ready',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.royalPurple),
                ),
              ),
            ],
          ),
          if (c.caseType.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Case identified: ${c.caseType}', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          ],
          if (c.caseSummary.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(c.caseSummary, style: const TextStyle(fontSize: 14.5, height: 1.45)),
          ],
          if (c.infoNeeded.isNotEmpty && c.snapshot == null) ...[
            const SizedBox(height: 8),
            Text(
              'Not available (the report will say so): ${c.infoNeeded.map(consultationFieldLabel).join(', ')}',
              style: AppText.smallMuted,
            ),
          ],
          if (c.snapshot != null) ...[
            const SizedBox(height: 10),
            SnapshotSummary(snapshot: c.snapshot!, onEdit: onEditSnapshot),
          ],
          if (c.snapshot == null || c.facts.isNotEmpty) ...[
            const SizedBox(height: 10),
            Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              child: _FactList(facts: c.facts, unknown: c.unknown, onEdit: onEdit),
            ),
          ],
          if (c.hasReport && c.snapshot != null) ...[
            const SizedBox(height: 10),
            Text(c.snapshot!.text('updated_note'), style: AppText.smallMuted, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onGenerate,
            icon: const Icon(Icons.description_outlined),
            label: Text(
              c.snapshot == null ? 'Generate report' : c.snapshot!.text(c.hasReport ? 'update_report' : 'generate'),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            c.snapshot == null
                ? 'Takes 1–3 minutes. The report always has the same sections; anything not provided is marked.'
                : 'Takes 1–3 minutes. The report always has the same sections.',
            textAlign: TextAlign.center,
            style: AppText.caption,
          ),
        ],
      ),
    );
  }
}

class _SafetyStop extends StatelessWidget {
  const _SafetyStop({required this.onManaged, required this.onAbsent});

  final VoidCallback onManaged;
  final VoidCallback onAbsent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: StatusPill('Safety first', tone: Tone.crisis, icon: Icons.warning_amber_rounded, uppercase: true),
        ),
        const SizedBox(height: 10),
        const Text(
          'Your answer suggests possible risk. Questions are paused until you confirm your client is safe right now.',
          style: TextStyle(fontSize: 15.5, height: 1.45, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        const CrisisNumbersCard(),
        const SizedBox(height: 14),
        FilledButton(onPressed: onManaged, child: const Text('Immediate safety is being managed — continue')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: onAbsent, child: const Text('Risk was screened and is absent — continue')),
      ],
    );
  }
}

class _DoneCard extends StatelessWidget {
  const _DoneCard({required this.onOpen, this.onEditSnapshot});

  final VoidCallback? onOpen;

  /// Correct the Case Snapshot, then update the report.
  final VoidCallback? onEditSnapshot;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('The report has been written.', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('It is also in History.', style: AppText.smallMuted),
          if (onOpen != null) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: onOpen, child: const Text('Open the report')),
          ],
          if (onEditSnapshot != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onEditSnapshot, child: const Text('Edit the Case Snapshot')),
          ],
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.onRetry});

  final ApiException error;
  final Future<bool> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final (text, canRetry) = switch (error) {
      IdentifiersDetected(:final types) => (
        'The server found something that looks like ${types.map(describeIdentifierType).join(', ').toLowerCase()}. '
            'Nothing was sent on. Please rewrite it without the identifier.',
        false,
      ),
      Conflict() => ('Still working on your last step. Try again in a moment.', true),
      DailyLimitReached() => ("You've reached today's consult limit. You can continue tomorrow.", false),
      NetworkProblem(timedOut: true) => ('This is taking too long. Try again.', true),
      NetworkProblem() => ("Couldn't reach Your Counselor. Check your connection and try again.", true),
      Unauthorized() => ('Please sign in again.', false),
      NotVerified() => ('Your registration is not verified yet.', false),
      NotFound() => ('This consultation is no longer available.', false),
      ServerProblem() => ('Something went wrong on our side. Try again.', true),
      PaymentRequired(:final message) => ('$message Your answers are saved.', false),
      OwnKeyFailed(:final message, :final retry) => (message, retry),
      BillingRefused(:final message) => (message, false),
    };
    final (fixLabel, fixRoute) = switch (error) {
      PaymentRequired() => ('See plans', '/pricing'),
      OwnKeyFailed() => ('Manage key', '/pricing/own-key'),
      _ => (null, null),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.checkBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.checkBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.checkInk),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14.5, height: 1.4, color: AppColors.checkInk)),
          ),
          if (canRetry && onRetry != null) TextButton(onPressed: onRetry, child: const Text('Try again')),
          if (fixRoute != null) TextButton(onPressed: () => context.push(fixRoute), child: Text(fixLabel!)),
        ],
      ),
    );
  }
}

/// Small text buttons so "Don't know", "Skip" and "Report now" usually fit one row on a phone.
final _compact = TextButton.styleFrom(
  padding: const EdgeInsets.symmetric(horizontal: 10),
  visualDensity: VisualDensity.compact,
  textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
);

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.options,
    required this.onSend,
    required this.onDontKnow,
    required this.onSkip,
    required this.onGenerateNow,
  });

  final TextEditingController controller;
  final bool enabled;
  final List<String> options;
  final Future<void> Function([String? option]) onSend;
  final Future<bool> Function() onDontKnow;
  final Future<bool> Function() onSkip;
  final VoidCallback? onGenerateNow;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (options.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final o in options) ActionChip(label: Text(o), onPressed: enabled ? () => onSend(o) : null),
                ],
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: enabled,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 4000,
                    // No autocorrect learning or suggestions on clinical text.
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(hintText: 'Your answer', counterText: '', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Send answer',
                  onPressed: enabled ? () => onSend() : null,
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
            // Wraps onto a second line instead of overflowing with very large text.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Wrap(
                  children: [
                    TextButton(
                      style: _compact,
                      onPressed: enabled ? onDontKnow : null,
                      child: const Text("Don't know"),
                    ),
                    TextButton(style: _compact, onPressed: enabled ? onSkip : null, child: const Text('Skip')),
                  ],
                ),
                TextButton.icon(
                  style: _compact,
                  onPressed: enabled ? onGenerateNow : null,
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('Report now'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditFactDialog extends StatefulWidget {
  const _EditFactDialog({required this.label, required this.initial});

  final String label;
  final String initial;

  @override
  State<_EditFactDialog> createState() => _EditFactDialogState();
}

class _EditFactDialogState extends State<_EditFactDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.label),
      content: TextField(
        controller: _text,
        autofocus: true,
        minLines: 1,
        maxLines: 4,
        maxLength: 300,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        decoration: const InputDecoration(helperText: 'Leave empty to remove it.'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_text.text), child: const Text('Save')),
      ],
    );
  }
}

class _Generating extends StatefulWidget {
  const _Generating();

  @override
  State<_Generating> createState() => _GeneratingState();
}

class _GeneratingState extends State<_Generating> {
  Timer? _ticker;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _elapsed++));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clock = '${_elapsed ~/ 60}:${(_elapsed % 60).toString().padLeft(2, '0')}';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 44, height: 44, child: CircularProgressIndicator(strokeWidth: 3.5)),
            const SizedBox(height: 20),
            const Text('Writing your consultation report', textAlign: TextAlign.center, style: AppText.sheetTitle),
            const SizedBox(height: 8),
            const Text(
              'Case summary sent securely · drafting with the clinical knowledge base · safety checks on the report',
              textAlign: TextAlign.center,
              style: AppText.smallMuted,
            ),
            const SizedBox(height: 12),
            Text(clock, style: AppText.caption),
            const SizedBox(height: 6),
            const Text('Usually 1–3 minutes. Keep the app open.', style: AppText.caption),
          ],
        ),
      ),
    );
  }
}
