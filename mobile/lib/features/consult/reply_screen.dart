import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/content/safety_content.dart';
import '../../core/demo/preview_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/safety_widgets.dart';
import '../../core/widgets/surfaces.dart';
import 'check_sheet.dart';
import 'report_sheet.dart';

/// A delivered, inspector-passed reply. In the design build the content is
/// the sample in `preview_data.dart`; the real reply arrives as markdown.
class ReplyScreen extends StatefulWidget {
  const ReplyScreen({super.key});

  @override
  State<ReplyScreen> createState() => _ReplyScreenState();
}

class _ReplyScreenState extends State<ReplyScreen> {
  final _keys = {
    for (final id in ['audit', 'safety', 'formulation', 'more']) id: GlobalKey(),
  };
  final _followUp = TextEditingController();
  int? _open = 13;

  @override
  void dispose() {
    _followUp.dispose();
    super.dispose();
  }

  void _jump(String id) {
    final ctx = _keys[id]!.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
  }

  void _copy() {
    Clipboard.setData(const ClipboardData(text: '[Full reply text]'));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reply copied')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New consult', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        titleSpacing: 0,
        actions: [
          IconButton(tooltip: 'Copy whole reply', onPressed: _copy, icon: const Icon(Icons.copy_rounded)),
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
                    const Text('FULL PLAN · 34F · PANIC', style: AppText.overline),
                    const SizedBox(height: 4),
                    Semantics(header: true, child: const Text('Clinical work-up', style: AppText.screenTitle)),
                    const SizedBox(height: 16),
                    const _SummaryCard(),
                    const SizedBox(height: 16),
                    _JumpBar(onJump: _jump),
                    const SizedBox(height: 16),
                    _AuditCard(key: _keys['audit']),
                    const SizedBox(height: 16),
                    _SectionCard(
                      key: _keys['safety'],
                      title: '2. Safety & risk screen',
                      body: '[Safety screen from the reply: current risk status and what to confirm next.]',
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      key: _keys['formulation'],
                      title: '3. Pattern analysis & formulation',
                      body: '[Formulation from the reply.]',
                      provisional: true,
                    ),
                    const SizedBox(height: 16),
                    _SectionList(
                      key: _keys['more'],
                      open: _open,
                      onToggle: (n) => setState(() => _open = _open == n ? null : n),
                    ),
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
            _FollowUpBar(
              controller: _followUp,
              onSend: () => showCheckSheet(context, text: _followUp.text, mode: ConsultMode.auto),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard();

  @override
  Widget build(BuildContext context) {
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
          const SizedBox(height: 10),
          Row(
            children: [
              fact('Confidence', 'Low', color: AppColors.checkInk),
              const SizedBox(width: 8),
              fact('Written for', 'L2 · Psychologist'),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'The case history has gaps, so sections 3 onward are provisional. Filling the gaps in section 1 raises confidence.',
            style: TextStyle(fontSize: 14, height: 1.45, color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _JumpBar extends StatelessWidget {
  const _JumpBar({required this.onJump});

  final ValueChanged<String> onJump;

  @override
  Widget build(BuildContext context) {
    const items = {'audit': 'Audit', 'safety': 'Safety', 'formulation': 'Formulation', 'more': 'Therapy & sessions'};
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        children: [
          for (final (i, e) in items.entries.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            ActionChip(
              label: Text(e.value),
              onPressed: () => onJump(e.key),
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

class _AuditCard extends StatelessWidget {
  const _AuditCard({super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('1. Case history & MSE audit', style: AppText.sectionTitle),
          const SizedBox(height: 12),
          const Text('PROCEDURAL AUDIT', style: AppText.overline),
          for (final (i, row) in kPreviewAudit.indexed) ...[
            if (i > 0) const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(row.item, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                      StatusPill(row.status, tone: row.tone),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(row.comment, style: AppText.smallMuted),
                ],
              ),
            ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () {}, child: const Text('Show history & MSE audit')),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({super.key, required this.title, required this.body, this.provisional = false});

  final String title;
  final String body;
  final bool provisional;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (provisional) ...[
            const StatusPill('Provisional · low confidence', tone: Tone.check, uppercase: true),
            const SizedBox(height: 10),
          ],
          Text(title, style: AppText.sectionTitle),
          const SizedBox(height: 10),
          Text(body, style: AppText.small),
        ],
      ),
    );
  }
}

class _SectionList extends StatelessWidget {
  const _SectionList({super.key, required this.open, required this.onToggle});

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
          for (final (i, title) in kReplySections.indexed) ...[
            if (i > 0) const Divider(),
            _SectionTile(number: i + 4, title: title, expanded: open == i + 4, onTap: () => onToggle(i + 4)),
          ],
        ],
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({required this.number, required this.title, required this.expanded, required this.onTap});

  final int number;
  final String title;
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('$number. $title', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
                const StatusPill('Provisional', tone: Tone.check, uppercase: true),
                const SizedBox(height: 10),
                const Text('[Section content from the reply. Wide tables scroll sideways.]', style: AppText.small),
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '$number. $title'));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Section copied')));
                  },
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
              decoration: const InputDecoration(
                hintText: 'Follow-up, e.g. shorten to 6 sessions',
                isDense: true,
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
