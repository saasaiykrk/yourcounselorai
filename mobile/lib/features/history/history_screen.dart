import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/api/api_models.dart';
import '../../core/content/safety_content.dart';
import '../../core/providers.dart';
import '../../core/security/screen_protection.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../consult/reply_markdown.dart';

/// The clinician's past consults. Fetched from the server each time and kept
/// in memory only; nothing is written to the phone.
String historyModeLabel(String code) =>
    ConsultMode.values.where((m) => m.apiCode == code).map((m) => m.label).firstOrNull ?? code;

String historyWhen(DateTime? d) {
  if (d == null) return '';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final now = DateTime.now();
  final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (d.year == now.year && d.month == now.month && d.day == now.day) return 'Today, $hm';
  return '${d.day} ${months[d.month - 1]}${d.year == now.year ? '' : ' ${d.year}'}, $hm';
}

String _errorText(Object e) => switch (e) {
  NetworkProblem() => "Couldn't reach Your Counselor. Check your connection.",
  NotFound() => 'This consult is no longer in your history.',
  Unauthorized() => 'Please sign in again.',
  NotVerified() => 'History is available once your registration is verified.',
  _ => 'Something went wrong. Please try again.',
};

/// Bumped when the History tab is opened, so the list is re-read.
class HistoryRefresh extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final historyRefreshProvider = NotifierProvider<HistoryRefresh, int>(HistoryRefresh.new);

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => HistoryScreenState();
}

class HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String? _mode;
  late Future<List<ConsultSummary>> _future = _load();

  Future<List<ConsultSummary>> _load() => ref.read(historyRepositoryProvider).list(query: _search.text, mode: _mode);

  /// Re-reads the list (called when the tab is opened and after changes).
  void reload() {
    setState(() {
      _future = _load();
    });
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), reload);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(ConsultSummary c) async {
    final changed = await context.push<bool>('/history/consult', extra: c.id);
    if (changed == true && mounted) reload();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(historyRefreshProvider, (_, _) => reload());
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            reload();
            await _future.catchError((_) => <ConsultSummary>[]);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              const PageHeading('History', message: 'Your past consults. Only you can see them.'),
              const SizedBox(height: 16),
              TextField(
                controller: _search,
                onChanged: _onSearch,
                textInputAction: TextInputAction.search,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                decoration: InputDecoration(
                  hintText: 'Search your consults',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            reload();
                          },
                        ),
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (code, label) in [
                      (null, 'All'),
                      for (final m in ConsultMode.values.where((m) => m != ConsultMode.auto)) (m.apiCode, m.label),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: _mode == code,
                          onSelected: (_) {
                            _mode = code;
                            reload();
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<ConsultSummary>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snap.hasError) {
                    return _Message(_errorText(snap.error!), action: ('Try again', reload));
                  }
                  final list = snap.data!;
                  if (list.isEmpty) {
                    final filtered = _search.text.trim().isNotEmpty || _mode != null;
                    return _Message(filtered ? 'No consults match.' : 'Your consults will appear here.');
                  }
                  return Column(
                    children: [
                      for (final c in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: ConsultSummaryCard(consult: c, onTap: () => _open(c)),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ConsultSummaryCard extends StatelessWidget {
  const ConsultSummaryCard({super.key, required this.consult, required this.onTap});

  final ConsultSummary consult;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = consult;
    final modes = c.modes.map(historyModeLabel).join(', ');
    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.line),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      c.title ?? c.preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: c.title != null ? FontWeight.w800 : FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  if (c.hiddenAt != null) ...[
                    const SizedBox(width: 8),
                    const StatusPill('Deleted by clinician', tone: Tone.neutral),
                  ] else if (c.lastStatus == 'blocked') ...[
                    const SizedBox(width: 8),
                    const StatusPill('Held back', tone: Tone.check),
                  ],
                ],
              ),
              if (c.title != null) ...[
                const SizedBox(height: 2),
                Text(c.preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.smallMuted),
              ],
              const SizedBox(height: 6),
              Text(
                '${historyWhen(c.lastAt ?? c.createdAt)} · $modes'
                '${c.turns > 1 ? ' · ${c.turns} messages' : ''}',
                style: AppText.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One past consult, read-only. Screenshot-protected (it shows case text).
class HistoryConsultScreen extends ConsumerStatefulWidget {
  const HistoryConsultScreen({super.key, required this.consultId});

  final String consultId;

  @override
  ConsumerState<HistoryConsultScreen> createState() => _HistoryConsultScreenState();
}

class _HistoryConsultScreenState extends ConsumerState<HistoryConsultScreen> {
  late Future<ConsultDetail> _future = ref.read(historyRepositoryProvider).get(widget.consultId);
  bool _changed = false;

  void _reload() {
    setState(() {
      _future = ref.read(historyRepositoryProvider).get(widget.consultId);
    });
  }

  Future<void> _label(ConsultDetail d) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (_) => _LabelSheet(consultId: d.id, current: d.title),
    );
    if (saved == true) {
      _changed = true;
      _reload();
    }
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete from history?'),
        content: const Text(
          'It will disappear from your History. A de-identified copy is kept for safety review '
          'until the 12-month retention period ends.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.crisis),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await ref.read(historyRepositoryProvider).delete(widget.consultId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted from your history')));
        context.pop(true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_errorText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ProtectedScreen(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) context.pop(_changed);
        },
        child: FutureBuilder<ConsultDetail>(
          future: _future,
          builder: (context, snap) {
            final d = snap.data;
            return Scaffold(
              appBar: AppBar(
                title: Text(d?.title ?? 'Past consult', overflow: TextOverflow.ellipsis),
                actions: [
                  if (d != null)
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      onSelected: (v) => v == 'label' ? _label(d) : _delete(),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'label', child: Text('Add or change label')),
                        PopupMenuItem(value: 'delete', child: Text('Delete from history')),
                      ],
                    ),
                ],
              ),
              body: switch (snap) {
                AsyncSnapshot(connectionState: != ConnectionState.done) => const Center(
                  child: CircularProgressIndicator(),
                ),
                AsyncSnapshot(:final error?) => _Message(_errorText(error), action: ('Try again', _reload)),
                _ => ConsultTurnsView(detail: d!),
              },
            );
          },
        ),
      ),
    );
  }
}

/// The turns of a consult: each case as sent, then the reply as shown.
class ConsultTurnsView extends StatelessWidget {
  const ConsultTurnsView({super.key, required this.detail, this.header});

  final ConsultDetail detail;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        ?header,
        for (final (i, t) in detail.turns.indexed) ...[
          if (i > 0) const Divider(height: 40),
          Text(
            '${i == 0 ? 'Case' : 'Follow-up'} · ${historyModeLabel(t.mode)} · ${historyWhen(t.createdAt)}',
            style: AppText.overline,
          ),
          const SizedBox(height: 6),
          AppCard(
            color: AppColors.background,
            padding: const EdgeInsets.all(12),
            child: SelectableText(t.input, style: AppText.small),
          ),
          const SizedBox(height: 12),
          if (t.delivered)
            ReplyMarkdown(t.reply)
          else
            const NoticeBanner(
              icon: Icons.shield_outlined,
              text: 'This reply was held back by the safety check, so there is nothing to show.',
              tone: Tone.check,
            ),
        ],
        const SizedBox(height: 16),
        const Text(
          'This tool is for professional use only. It does not diagnose or replace clinical judgement.',
          style: AppText.caption,
        ),
      ],
    );
  }
}

class _LabelSheet extends ConsumerStatefulWidget {
  const _LabelSheet({required this.consultId, this.current});

  final String consultId;
  final String? current;

  @override
  ConsumerState<_LabelSheet> createState() => _LabelSheetState();
}

class _LabelSheetState extends ConsumerState<_LabelSheet> {
  late final _text = TextEditingController(text: widget.current ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save({bool clear = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(historyRepositoryProvider).label(widget.consultId, clear ? null : _text.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } on IdentifiersDetected catch (e) {
      final what = e.types.map((t) => describeIdentifierType(t).toLowerCase()).join(', ');
      if (mounted) {
        setState(() => _error = 'This looks like it contains $what. Use a description such as "exam panic review".');
      }
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Label this consult', style: AppText.sheetTitle),
          const SizedBox(height: 8),
          const NoticeBanner(
            icon: Icons.privacy_tip_outlined,
            text: "Don't use client names, initials, phone numbers or IDs. Describe the case instead.",
            tone: Tone.check,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            maxLength: 60,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            decoration: const InputDecoration(labelText: 'Label', hintText: 'e.g. exam panic review'),
          ),
          if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.crisis)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save label')),
          if (widget.current != null)
            TextButton(onPressed: _busy ? null : () => _save(clear: true), child: const Text('Remove label')),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.action});

  final String text;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 8),
      child: Column(
        children: [
          Text(text, textAlign: TextAlign.center, style: AppText.bodyMuted),
          if (action != null) TextButton(onPressed: action!.$2, child: Text(action!.$1)),
        ],
      ),
    );
  }
}
