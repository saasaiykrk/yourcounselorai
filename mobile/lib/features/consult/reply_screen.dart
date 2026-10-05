import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_models.dart';
import '../../core/config.dart';
import '../../core/content/safety_content.dart';
import '../../core/demo/preview_data.dart';
import '../../core/security/screen_protection.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/safety_widgets.dart';
import '../../core/widgets/surfaces.dart';
import 'check_sheet.dart';
import 'consult_controller.dart';
import 'reply_markdown.dart';
import 'reply_sections.dart';
import 'report_sheet.dart';

/// Number of leading sections shown open as cards; the rest fold into a list.
const _openSections = 3;

/// A delivered, inspector-passed reply.
class ReplyScreen extends ConsumerStatefulWidget {
  const ReplyScreen({super.key});

  @override
  ConsumerState<ReplyScreen> createState() => _ReplyScreenState();
}

class _ReplyScreenState extends ConsumerState<ReplyScreen> {
  final _keys = <int, GlobalKey>{};
  final _followUp = TextEditingController();
  int? _open;

  @override
  void dispose() {
    _followUp.dispose();
    super.dispose();
  }

  GlobalKey _key(int i) => _keys.putIfAbsent(i, GlobalKey.new);

  void _jump(int i) {
    final ctx = _key(i).currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
  }

  void _newConsult() {
    ref.read(consultControllerProvider.notifier).clear();
    context.go('/consult');
  }

  Future<void> _sendFollowUp() async {
    if (_followUp.text.trim().length < AppConfig.minCaseLength) return;
    final sent = await showCheckSheet(context, text: _followUp.text, mode: ConsultMode.auto);
    if (sent && mounted) _followUp.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(consultControllerProvider);
    final reply = switch (state) {
      ConsultReplied(:final reply) => reply,
      _ => AppConfig.previewMode ? _previewReply : null,
    };
    if (reply == null) {
      return Scaffold(
        body: StatusPage(
          icon: Icons.chat_bubble_outline_rounded,
          tone: Tone.neutral,
          title: 'No reply to show',
          message: 'Replies are never stored on this phone. Start a new consult.',
          actions: [FilledButton(onPressed: _newConsult, child: const Text('New consult'))],
        ),
      );
    }

    final parsed = parseReply(reply.text);
    final sections = parsed.sections;
    final open = sections.take(_openSections).toList();
    final folded = sections.skip(_openSections).toList();
    final mode = ConsultMode.values.where((m) => m.apiCode == reply.meta.mode).firstOrNull;
    final isReport = reply.meta.mode == 'R'; // guided consultation: the fixed Consultation Report

    return ProtectedScreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'New consult',
            onPressed: _newConsult,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Text('New consult', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          titleSpacing: 0,
          actions: [
            IconButton(
              tooltip: 'Copy whole reply',
              onPressed: () => copyReplyText(context, reply.text, message: 'Reply copied'),
              icon: const Icon(Icons.copy_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${isReport ? 'Guided consultation' : (mode ?? ConsultMode.auto).label} · '
                                'knowledge base ${reply.skillVersion}'
                            .toUpperCase(),
                        style: AppText.overline,
                      ),
                      const SizedBox(height: 4),
                      Semantics(
                        header: true,
                        child: Text(isReport ? 'Consultation report' : 'Clinical work-up', style: AppText.screenTitle),
                      ),
                      const SizedBox(height: 16),
                      _SummaryCard(meta: reply.meta),
                      if (sections.length > 1) ...[
                        const SizedBox(height: 16),
                        _JumpBar(
                          labels: [for (final s in open) s.title, if (folded.isNotEmpty) 'All sections'],
                          onJump: _jump,
                        ),
                      ],
                      if (parsed.intro.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        AppCard(child: ReplyMarkdown(parsed.intro)),
                      ],
                      if (sections.isEmpty && parsed.intro.isEmpty) ...[
                        const SizedBox(height: 16),
                        AppCard(child: ReplyMarkdown(reply.text)),
                      ],
                      for (final (i, s) in open.indexed) ...[
                        const SizedBox(height: 16),
                        _SectionCard(key: _key(i), section: s),
                      ],
                      if (folded.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _SectionList(
                          key: _key(open.length),
                          sections: folded,
                          open: _open,
                          onToggle: (i) => setState(() => _open = _open == i ? null : i),
                        ),
                      ],
                      const SizedBox(height: 16),
                      const DisclaimerBlock(),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () => showReportSheet(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.crisis,
                          side: const BorderSide(color: AppColors.inputBorder, width: 1.5),
                          minimumSize: const Size.fromHeight(50),
                          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        icon: const Icon(Icons.flag_outlined),
                        label: const Text('Report a problem with this reply'),
                      ),
                    ],
                  ),
                ),
              ),
              _FollowUpBar(controller: _followUp, onSend: _sendFollowUp),
            ],
          ),
        ),
      ),
    );
  }
}

final _previewReply = ConsultReply(
  turnId: 'preview-turn',
  conversationId: 'preview-conversation',
  delivered: true,
  text: kPreviewReplyMarkdown,
  skillVersion: '2.1.1',
  meta: const ReplyMeta(mode: 'A', gate: 'none', ceiling: 'Low', level: 'L2'),
);

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.meta});

  final ReplyMeta meta;

  @override
  Widget build(BuildContext context) {
    final ceiling = meta.ceiling;
    final low = ceiling?.toLowerCase() == 'low';

    Widget fact(String label, String value, {Color color = AppColors.ink}) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppText.caption),
            Text(
              value,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color),
            ),
          ],
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.lavender, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_user_outlined, size: 19, color: AppColors.royalPurple),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Passed safety checks',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.royalPurple),
                ),
              ),
            ],
          ),
          if (ceiling != null && ceiling != 'NA' || meta.level != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (ceiling != null && ceiling != 'NA')
                  fact('Confidence', ceiling, color: low ? AppColors.checkInk : AppColors.ink),
                if (ceiling != null && ceiling != 'NA' && meta.level != null) const SizedBox(width: 8),
                if (meta.level != null) fact('Written for', meta.level!),
              ],
            ),
          ],
          if (low) ...[
            const SizedBox(height: 10),
            const Text(
              'The case history has gaps, so later sections are provisional. Filling the gaps in section 1 raises confidence.',
              style: TextStyle(fontSize: 14, height: 1.45, color: AppColors.inkSoft),
            ),
          ],
        ],
      ),
    );
  }
}

class _JumpBar extends StatelessWidget {
  const _JumpBar({required this.labels, required this.onJump});

  final List<String> labels;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        children: [
          for (final (i, label) in labels.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            ActionChip(
              label: Text(label.length > 26 ? '${label.substring(0, 24)}…' : label),
              onPressed: () => onJump(i),
              labelStyle: TextStyle(fontWeight: FontWeight.w700, color: i == 0 ? Colors.white : AppColors.ink),
              backgroundColor: i == 0 ? AppColors.ink : AppColors.surface,
              side: BorderSide(color: i == 0 ? AppColors.ink : AppColors.line),
              shape: const StadiumBorder(),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({super.key, required this.section});

  final ReplySection section;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section.provisional) ...[
            const StatusPill('Provisional · low confidence', tone: Tone.check, uppercase: true),
            const SizedBox(height: 10),
          ],
          Semantics(header: true, child: Text(section.heading, style: AppText.sectionTitle)),
          const SizedBox(height: 10),
          ReplyMarkdown(section.body),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () =>
                  copyReplyText(context, '${section.heading}\n\n${section.body}', message: 'Section copied'),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: const Text('Copy this section'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionList extends StatelessWidget {
  const _SectionList({super.key, required this.sections, required this.open, required this.onToggle});

  final List<ReplySection> sections;
  final int? open;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.line),
      ),
      child: Column(
        children: [
          for (final (i, s) in sections.indexed) ...[
            if (i > 0) const Divider(),
            _SectionTile(section: s, expanded: open == i, onTap: () => onToggle(i)),
          ],
        ],
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({required this.section, required this.expanded, required this.onTap});

  final ReplySection section;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: expanded,
          button: true,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(section.heading, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                    Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.muted),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (section.provisional) ...[
                  const StatusPill('Provisional', tone: Tone.check, uppercase: true),
                  const SizedBox(height: 10),
                ],
                ReplyMarkdown(section.body),
                TextButton(
                  onPressed: () =>
                      copyReplyText(context, '${section.heading}\n\n${section.body}', message: 'Section copied'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  child: const Text('Copy this section'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FollowUpBar extends StatelessWidget {
  const _FollowUpBar({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              maxLength: AppConfig.maxCaseLength,
              decoration: const InputDecoration(
                hintText: 'Follow-up, e.g. shorten to 6 sessions',
                isDense: true,
                counterText: '',
                fillColor: AppColors.background,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Check and send follow-up',
            onPressed: onSend,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.royalPurple,
              minimumSize: const Size(50, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
