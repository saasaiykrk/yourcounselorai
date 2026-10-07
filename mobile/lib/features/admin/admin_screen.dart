import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/api/api_models.dart';
import '../../core/content/safety_content.dart';
import '../../core/providers.dart';
import '../../core/security/screen_protection.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/surfaces.dart';
import '../consult/report_pdf_action.dart';
import '../history/history_screen.dart';

/// Admin area: approve or reject registrations, and triage "Report a problem"
/// items and held-back replies. Reached from Account, shown only to admins;
/// the backend checks admin rights again on every request.
const adminRoles = {
  'counsellor_trainee': 'Counsellor / trainee',
  'psychologist': 'Psychologist',
  'psychiatrist': 'Psychiatrist',
};

const adminCategories = {
  'blocked': 'Held back by safety check',
  'unsafe': 'Unsafe',
  'wrong_clinical': 'Clinically wrong',
  'missing_safety': 'Missing safety content',
  'identifier_leak': 'Identifier leak',
  'crisis_number': 'Crisis number',
  'other': 'Other',
};

const adminIncidentStatuses = {'open': 'Open', 'triaged': 'Triaged', 'fixed': 'Fixed', 'wont_fix': "Won't fix"};

String _when(DateTime? d) {
  if (d == null) return '';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = d.hour.toString().padLeft(2, '0');
  final m = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${months[d.month - 1]}, $h:$m';
}

String _errorText(Object e) => switch (e) {
  NotVerified() || Unauthorized() => 'This account has no admin access.',
  NetworkProblem() => "Couldn't reach Your Counselor. Check your connection.",
  NotFound() => 'Not found. It may have been changed by another admin.',
  _ => 'Something went wrong. Please try again.',
};

/// How serious a report category is: decides the coloured edge on its card.
const _severity = {
  'unsafe': AppColors.crisis,
  'identifier_leak': AppColors.crisis,
  'crisis_number': AppColors.crisis,
  'missing_safety': AppColors.crisis,
  'blocked': AppColors.checkDot,
  'wrong_clinical': AppColors.checkDot,
};

String _registration(AdminClinician c) => c.registrationBody != null && c.registrationBody != 'none'
    ? '${c.registrationBody} ${c.registrationNumber ?? '(no number)'}'
    : 'No registration given';

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty && !RegExp(r'^(dr|mr|mrs|ms|prof)\.?$', caseSensitive: false).hasMatch(p))
      .toList();
  if (parts.isEmpty) return '?';
  return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
}

/// The admin area, laid out like the web admin panel: Overview, Registrations, Reports.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this);
  String _clinicianStatus = 'pending';
  String? _incidentStatus = 'open';
  int? _pending;
  int? _open;
  int _generation = 0; // bumps when something changed, so every tab reloads

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadCounts() async {
    final repo = ref.read(adminRepositoryProvider);
    try {
      final (p, o) = (await repo.clinicians('pending'), await repo.incidents('open'));
      if (!mounted) return;
      setState(() {
        _pending = p.length;
        _open = o.length;
      });
    } catch (_) {
      // Counts are optional.
    }
  }

  void _changed() {
    setState(() => _generation++);
    _loadCounts();
  }

  void _goRegistrations(String status) {
    setState(() => _clinicianStatus = status);
    _tabs.animateTo(1);
  }

  void _goReports(String? status) {
    setState(() => _incidentStatus = status);
    _tabs.animateTo(2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Row(
          children: [
            Text('Admin'),
            SizedBox(width: 8),
            StatusPill('Your Counselor', tone: Tone.brand),
          ],
        ),
        bottom: TabBar(
          controller: _tabs,
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          tabs: [
            const Tab(text: 'Overview'),
            Tab(child: _TabLabel('Registrations', _pending, AppColors.royalPurple)),
            Tab(child: _TabLabel('Reports', _open, AppColors.berry)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _OverviewTab(
            key: ValueKey('overview-$_generation'),
            onRegistrations: _goRegistrations,
            onReports: _goReports,
          ),
          _RegistrationsTab(
            key: ValueKey('reg-$_clinicianStatus-$_generation'),
            status: _clinicianStatus,
            onStatus: (s) => setState(() => _clinicianStatus = s),
            onChanged: _changed,
          ),
          _ReportsTab(
            key: ValueKey('rep-$_incidentStatus-$_generation'),
            status: _incidentStatus,
            onStatus: (s) => setState(() => _incidentStatus = s),
            onChanged: _changed,
          ),
        ],
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel(this.text, this.count, this.color);

  final String text;
  final int? count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
        if (count != null && count! > 0) ...[
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
            child: Text(
              '$count',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white),
            ),
          ),
        ],
      ],
    );
  }
}

/// Pill-shaped filter like the web panel's (Waiting · Verified · Rejected).
class _Seg<T> extends StatelessWidget {
  const _Seg({required this.options, required this.value, required this.onPick});

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.lineSoft, borderRadius: BorderRadius.circular(14)),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final (v, label) in options)
            Semantics(
              button: true,
              selected: v == value,
              child: Material(
                color: v == value ? AppColors.surface : Colors.transparent,
                elevation: v == value ? 1 : 0,
                shadowColor: AppColors.ink.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onPick(v),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: v == value ? AppColors.royalPurple : AppColors.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// --- overview ------------------------------------------------------------------

class _OverviewTab extends ConsumerStatefulWidget {
  const _OverviewTab({super.key, required this.onRegistrations, required this.onReports});

  final ValueChanged<String> onRegistrations;
  final ValueChanged<String?> onReports;

  @override
  ConsumerState<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends ConsumerState<_OverviewTab> {
  late Future<(List<AdminClinician>, List<AdminClinician>, List<AdminIncident>)> _future = _load();

  Future<(List<AdminClinician>, List<AdminClinician>, List<AdminIncident>)> _load() async {
    final repo = ref.read(adminRepositoryProvider);
    return (await repo.clinicians('pending'), await repo.clinicians('verified'), await repo.incidents('open'));
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _future = _load());
        await _future.catchError((_) => (<AdminClinician>[], <AdminClinician>[], <AdminIncident>[]));
      },
      child: FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ListView(
              children: [_Problem(_errorText(snap.error!), onRetry: () => setState(() => _future = _load()))],
            );
          }
          final (pending, verified, open) = snap.data!;
          final held = open.where((i) => i.automatic).length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              const Text('What needs your attention today.', style: AppText.smallMuted),
              const SizedBox(height: 12),
              GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                // A fixed height (not an aspect ratio) so two-line labels fit on narrow phones.
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  mainAxisExtent: 118,
                ),
                children: [
                  _Stat(
                    '${pending.length}',
                    'Waiting for approval',
                    Icons.badge_outlined,
                    pending.isEmpty ? AppColors.deepPurple : AppColors.checkInk,
                    () => widget.onRegistrations('pending'),
                  ),
                  _Stat(
                    '${open.length}',
                    'Open reports',
                    Icons.flag_outlined,
                    open.isEmpty ? AppColors.deepPurple : AppColors.berry,
                    () => widget.onReports('open'),
                  ),
                  _Stat(
                    '$held',
                    'Held back by safety check',
                    Icons.warning_amber_rounded,
                    AppColors.deepPurple,
                    () => widget.onReports('open'),
                  ),
                  _Stat(
                    '${verified.length}',
                    'Verified clinicians',
                    Icons.groups_outlined,
                    AppColors.deepPurple,
                    () => widget.onRegistrations('verified'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _Section(
                title: 'Waiting for approval',
                onAll: () => widget.onRegistrations('pending'),
                children: pending.isEmpty
                    ? const [_Empty('Nobody is waiting for approval.', icon: Icons.check_circle_outline_rounded)]
                    : [
                        for (final c in pending.take(5))
                          _RowItem(
                            edge: AppColors.royalPurple,
                            title: c.fullName ?? c.email,
                            pill: const StatusPill('Waiting', tone: Tone.check),
                            meta: '${adminRoles[c.role] ?? c.role} · ${_registration(c)} · ${_when(c.createdAt)}',
                            onTap: () => widget.onRegistrations('pending'),
                          ),
                      ],
              ),
              const SizedBox(height: 14),
              _Section(
                title: 'Open reports',
                onAll: () => widget.onReports('open'),
                children: open.isEmpty
                    ? const [_Empty('No open reports.', icon: Icons.check_circle_outline_rounded)]
                    : [
                        for (final i in open.take(5))
                          _IncidentCard(
                            incident: i,
                            onTap: () => context.push('/admin/report', extra: i.id),
                          ),
                      ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.number, this.label, this.icon, this.color, this.onTap);

  final String number;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              FittedBox(
                child: Text(
                  number,
                  style: TextStyle(fontFamily: 'Nunito', fontSize: 30, fontWeight: FontWeight.w900, color: color),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 16, color: AppColors.muted),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.muted),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.onAll, required this.children});

  final String title;
  final VoidCallback onAll;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: AppText.sectionTitle)),
              TextButton(onPressed: onAll, child: const Text('See all ›')),
            ],
          ),
          for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(height: 8), c],
        ],
      ),
    );
  }
}

/// A list row with a coloured left edge, a title, a status pill and one meta line.
class _RowItem extends StatelessWidget {
  const _RowItem({required this.edge, required this.title, required this.pill, required this.meta, this.onTap});

  final Color edge;
  final String title;
  final Widget pill;
  final String meta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.line),
      ),
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: edge),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 8),
                          pill,
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(meta, style: AppText.caption),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- registrations -------------------------------------------------------------

class _RegistrationsTab extends ConsumerStatefulWidget {
  const _RegistrationsTab({super.key, required this.status, required this.onStatus, required this.onChanged});

  final String status;
  final ValueChanged<String> onStatus;
  final VoidCallback onChanged;

  @override
  ConsumerState<_RegistrationsTab> createState() => _RegistrationsTabState();
}

class _RegistrationsTabState extends ConsumerState<_RegistrationsTab> {
  late Future<List<AdminClinician>> _future = _load();
  final _search = TextEditingController();

  Future<List<AdminClinician>> _load() => ref.read(adminRepositoryProvider).clinicians(widget.status);

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _decide(AdminClinician c, {required bool approve}) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (_) => _DecisionSheet(clinician: c, approve: approve),
    );
    if (done == true && mounted) {
      final who = c.fullName ?? c.email;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(approve ? 'Approved $who' : 'Rejected $who')));
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        await _future.catchError((_) => <AdminClinician>[]);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _Seg<String>(
            options: const [('pending', 'Waiting'), ('verified', 'Verified'), ('rejected', 'Rejected')],
            value: widget.status,
            onPick: widget.onStatus,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: 'Search name, email or registration no.',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (widget.status == 'pending')
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Check each registration number on the official register (RCI / NMC / State Medical Council) before approving.',
                style: AppText.caption,
              ),
            ),
          const SizedBox(height: 12),
          FutureBuilder<List<AdminClinician>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) return _Problem(_errorText(snap.error!), onRetry: _reload);
              final list = [
                for (final c in snap.data!)
                  if (q.isEmpty ||
                      [c.fullName, c.email, c.registrationNumber].any((v) => (v ?? '').toLowerCase().contains(q)))
                    c,
              ];
              if (list.isEmpty) {
                return _Empty(
                  q.isNotEmpty
                      ? 'No registrations match "$q".'
                      : widget.status == 'pending'
                      ? 'Nobody is waiting for approval.'
                      : 'None yet.',
                  icon: q.isNotEmpty ? Icons.search_off_rounded : Icons.inbox_outlined,
                );
              }
              return Column(
                children: [
                  for (final c in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ClinicianCard(
                        clinician: c,
                        onApprove: c.verificationStatus == 'pending' ? () => _decide(c, approve: true) : null,
                        onReject: c.verificationStatus == 'pending' ? () => _decide(c, approve: false) : null,
                        onConsults: c.verificationStatus == 'verified'
                            ? () => context.push('/admin/consults', extra: (c.id, c.fullName ?? c.email))
                            : null,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [AppColors.royalPurple, AppColors.brandPink]),
      ),
      child: Text(
        _initials(name),
        style: const TextStyle(fontFamily: 'Nunito', fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white),
      ),
    );
  }
}

class _ClinicianCard extends StatelessWidget {
  const _ClinicianCard({required this.clinician, this.onApprove, this.onReject, this.onConsults});

  final AdminClinician clinician;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onConsults;

  @override
  Widget build(BuildContext context) {
    final c = clinician;
    final (pill, tone) = switch (c.verificationStatus) {
      'verified' => ('Verified · ${c.level}', Tone.brand),
      'rejected' => ('Rejected', Tone.crisis),
      _ => ('Waiting', Tone.check),
    };
    final hasNumber = c.registrationBody != null && c.registrationBody != 'none' && c.registrationNumber != null;
    final personal = [
      if (c.gender != null) kGenders[c.gender] ?? c.gender!,
      if (c.age != null) '${c.age} yrs',
    ].join(' · ');

    Widget fact(String label, Widget value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 2),
        value,
      ],
    );
    const factStyle = TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.ink);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(c.fullName ?? c.email),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.fullName ?? c.email,
                      style: const TextStyle(fontFamily: 'Nunito', fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    if (c.fullName != null)
                      Text(c.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(pill, tone: tone),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: fact('Role', Text(adminRoles[c.role] ?? c.role, style: factStyle))),
              const SizedBox(width: 12),
              Expanded(
                child: fact(
                  'Registration',
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _registration(c),
                          style: hasNumber ? factStyle.copyWith(fontFamily: 'monospace') : factStyle,
                        ),
                      ),
                      if (hasNumber)
                        IconButton(
                          tooltip: 'Copy registration number',
                          visualDensity: VisualDensity.compact,
                          iconSize: 17,
                          color: AppColors.royalPurple,
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: c.registrationNumber!));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(const SnackBar(content: Text('Registration number copied')));
                            }
                          },
                          icon: const Icon(Icons.copy_rounded),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: fact('Gender · age', Text(personal.isEmpty ? 'Not given' : personal, style: factStyle))),
              const SizedBox(width: 12),
              Expanded(
                child: fact(
                  c.verificationStatus == 'pending' ? 'Registered' : 'Decided',
                  Text(_when(c.createdAt), style: factStyle),
                ),
              ),
            ],
          ),
          if (c.verificationNote != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
              child: Text('How it was checked: ${c.verificationNote}', style: AppText.caption),
            ),
          ],
          if (onConsults != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onConsults,
                icon: const Icon(Icons.history_rounded, size: 18),
                label: const Text('Consults'),
              ),
            ),
          ],
          if (onApprove != null || onReject != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton(onPressed: onApprove, child: const Text('Approve')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.crisis,
                      backgroundColor: AppColors.crisisBg,
                      side: BorderSide.none,
                    ),
                    child: const Text('Reject'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DecisionSheet extends ConsumerStatefulWidget {
  const _DecisionSheet({required this.clinician, required this.approve});

  final AdminClinician clinician;
  final bool approve;

  @override
  ConsumerState<_DecisionSheet> createState() => _DecisionSheetState();
}

class _DecisionSheetState extends ConsumerState<_DecisionSheet> {
  late String _level = switch (widget.clinician.role) {
    'counsellor_trainee' => 'L1',
    'psychiatrist' => 'L3',
    _ => 'L2',
  };
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final note = _note.text.trim();
    if (note.length < 3) {
      setState(() => _error = 'Say how you checked the registration.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(adminRepositoryProvider)
          .decide(widget.clinician.id, approve: widget.approve, level: widget.approve ? _level : null, note: note);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.clinician;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.approve ? 'Approve registration' : 'Reject registration', style: AppText.sheetTitle),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.fullName ?? c.email, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                Text(
                  [if (c.fullName != null) c.email, adminRoles[c.role] ?? c.role, _registration(c)].join(' · '),
                  style: AppText.caption,
                ),
              ],
            ),
          ),
          if (widget.approve) ...[
            const SizedBox(height: 16),
            const Text('Level', style: AppText.label),
            const SizedBox(height: 6),
            for (final (code, label) in const [
              ('L1', 'Counsellor / trainee'),
              ('L2', 'Psychologist'),
              ('L3', 'Senior / psychiatrist'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: _level == code ? AppColors.lavender : AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: _level == code ? AppColors.royalPurple : AppColors.line, width: 1.5),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _level = code),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            _level == code ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                            size: 20,
                            color: AppColors.royalPurple,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            code,
                            style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.royalPurple),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(label)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'How you checked (required)',
              hintText: 'e.g. RCI register, 3 Oct 2026',
              counterText: '',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppColors.crisis)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _confirm,
            style: widget.approve ? null : FilledButton.styleFrom(backgroundColor: AppColors.crisis),
            child: Text(_busy ? 'Saving…' : (widget.approve ? 'Approve as $_level' : 'Reject')),
          ),
        ],
      ),
    );
  }
}

// --- reports -----------------------------------------------------------------

class _ReportsTab extends ConsumerStatefulWidget {
  const _ReportsTab({super.key, required this.status, required this.onStatus, required this.onChanged});

  final String? status;
  final ValueChanged<String?> onStatus;
  final VoidCallback onChanged;

  @override
  ConsumerState<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<_ReportsTab> {
  late Future<List<AdminIncident>> _future = _load();

  Future<List<AdminIncident>> _load() => ref.read(adminRepositoryProvider).incidents(widget.status);

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        await _future.catchError((_) => <AdminIncident>[]);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _Seg<String?>(
            options: const [
              ('open', 'Open'),
              ('triaged', 'Triaged'),
              ('fixed', 'Fixed'),
              ('wont_fix', "Won't fix"),
              (null, 'All'),
            ],
            value: widget.status,
            onPick: widget.onStatus,
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<AdminIncident>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) return _Problem(_errorText(snap.error!), onRetry: _reload);
              final list = snap.data!;
              if (list.isEmpty) return const _Empty('No reports here.', icon: Icons.check_circle_outline_rounded);
              return Column(
                children: [
                  for (final i in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _IncidentCard(
                        incident: i,
                        onTap: () async {
                          await context.push('/admin/report', extra: i.id);
                          if (mounted) widget.onChanged();
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

StatusPill _statusPill(String status) => StatusPill(
  adminIncidentStatuses[status] ?? status,
  tone: status == 'open' ? Tone.check : (status == 'fixed' ? Tone.brand : Tone.neutral),
);

class _IncidentCard extends StatelessWidget {
  const _IncidentCard({required this.incident, required this.onTap});

  final AdminIncident incident;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final i = incident;
    return _RowItem(
      edge: _severity[i.category] ?? AppColors.royalPurple,
      title: adminCategories[i.category] ?? i.category,
      pill: _statusPill(i.status),
      meta: [
        i.automatic ? 'Automatic' : 'Reported by clinician',
        _when(i.createdAt),
        i.level ?? '',
        historyModeLabel(i.requestedMode ?? ''),
      ].where((s) => s.isNotEmpty).join(' · '),
      onTap: onTap,
    );
  }
}

/// The safety-check results, readable: each blocked check with its reason; the raw report on request.
class _Checks extends StatelessWidget {
  const _Checks(this.reports);

  final Object? reports;

  @override
  Widget build(BuildContext context) {
    final attempts = reports is List ? reports! as List : const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (n, r) in attempts.indexed) ...[
          Builder(
            builder: (context) {
              final map = r is Map ? r : const {};
              final blocks = [
                for (final b in (map['blocks'] as List? ?? const []))
                  b is Map ? ('${b['code']}', '${b['message'] ?? ''}') : ('$b', ''),
              ];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 4),
                    child: Text(
                      'Attempt ${n + 1} · ${map['passed'] == true ? 'passed' : '${blocks.length} problem(s)'}',
                      style: AppText.caption,
                    ),
                  ),
                  if (blocks.isEmpty)
                    _CheckLine(ok: true, code: 'All checks passed', message: '')
                  else
                    for (final (code, message) in blocks)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _CheckLine(ok: false, code: code, message: message),
                      ),
                ],
              );
            },
          ),
        ],
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'Show raw report',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.royalPurple),
            ),
            children: [
              AppCard(
                color: AppColors.background,
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  const JsonEncoder.withIndent('  ').convert(reports),
                  style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace', height: 1.45),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CheckLine extends StatelessWidget {
  const _CheckLine({required this.ok, required this.code, required this.message});

  final bool ok;
  final String code;
  final String message;

  @override
  Widget build(BuildContext context) {
    final fg = ok ? AppColors.royalPurple : AppColors.crisis;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: ok ? AppColors.lavender : AppColors.crisisBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            code,
            style: TextStyle(fontFamily: ok ? null : 'monospace', fontWeight: FontWeight.w800, color: fg),
          ),
          if (message.isNotEmpty) Text(message, style: TextStyle(fontSize: 13.5, height: 1.4, color: fg)),
        ],
      ),
    );
  }
}

/// One report with its de-identified case and reply. Screenshot-protected.
class AdminReportScreen extends ConsumerStatefulWidget {
  const AdminReportScreen({super.key, required this.incidentId});

  final String incidentId;

  @override
  ConsumerState<AdminReportScreen> createState() => _AdminReportScreenState();
}

class _AdminReportScreenState extends ConsumerState<AdminReportScreen> {
  late Future<AdminIncident> _future = ref.read(adminRepositoryProvider).incident(widget.incidentId);
  final _note = TextEditingController();
  String? _status;
  bool _busy = false;
  String? _message;
  bool _saved = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref
          .read(adminRepositoryProvider)
          .updateIncident(widget.incidentId, status: _status!, reviewerNote: _note.text.trim());
      if (mounted) {
        setState(() {
          _saved = true;
          _message = 'Saved as ${adminIncidentStatuses[_status] ?? _status}.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saved = false;
          _message = _errorText(e);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ProtectedScreen(
      child: Scaffold(
        appBar: AppBar(title: const Text('Report')),
        body: FutureBuilder<AdminIncident>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _Problem(
                _errorText(snap.error!),
                onRetry: () => setState(() {
                  _future = ref.read(adminRepositoryProvider).incident(widget.incidentId);
                }),
              );
            }
            final i = snap.data!;
            if (_status == null) {
              _status = i.status;
              _note.text = i.reviewerNote ?? '';
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(adminCategories[i.category] ?? i.category, style: AppText.screenTitle),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _statusPill(i.status),
                    StatusPill(i.automatic ? 'Automatic' : 'Reported by clinician', tone: Tone.neutral),
                    StatusPill(_when(i.createdAt), tone: Tone.neutral),
                    StatusPill(
                      [historyModeLabel(i.requestedMode ?? '?'), i.level ?? ''].where((s) => s.isNotEmpty).join(' · '),
                      tone: Tone.neutral,
                    ),
                    if (i.turnStatus != null) StatusPill('Reply ${i.turnStatus}', tone: Tone.neutral),
                  ],
                ),
                if (i.note != null && i.note!.isNotEmpty && !i.automatic) _Block("Clinician's note", i.note!),
                const SizedBox(height: 16),
                const Text('Safety checks', style: AppText.sectionTitle),
                _Checks(i.inspectorReports),
                _Block('Case as sent (de-identified)', i.inputDeid ?? ''),
                _Block('Reply as shown to the clinician', i.outputShown ?? ''),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),
                const Text('Your review', style: AppText.sectionTitle),
                const SizedBox(height: 8),
                _Seg<String>(
                  options: [for (final e in adminIncidentStatuses.entries) (e.key, e.value)],
                  value: _status!,
                  onPick: (v) => setState(() => _status = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  maxLength: 2000,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Reviewer note',
                    hintText: 'What you found and did',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save review')),
                if (_message != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _message!,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _saved ? AppColors.royalPurple : AppColors.crisis,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block(this.title, this.text);

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppText.sectionTitle),
          const SizedBox(height: 6),
          AppCard(
            color: AppColors.background,
            padding: const EdgeInsets.all(12),
            child: SelectableText(text, style: const TextStyle(fontSize: 14, height: 1.45)),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text, {this.icon = Icons.inbox_outlined});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Column(
        children: [
          Icon(icon, size: 30, color: AppColors.pendingRing),
          const SizedBox(height: 6),
          Text(text, textAlign: TextAlign.center, style: AppText.bodyMuted),
        ],
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem(this.text, {required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.crisis),
          ),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

// --- a clinician's consults (admin; every view is recorded in admin_audit) ------

const _auditNotice = NoticeBanner(
  icon: Icons.visibility_outlined,
  text: 'Admin view: opening consults is recorded in the audit log. Use it for safety review only.',
  tone: Tone.check,
);

class AdminConsultsScreen extends ConsumerStatefulWidget {
  const AdminConsultsScreen({super.key, required this.clinicianId, required this.email});

  final String clinicianId;
  final String email;

  @override
  ConsumerState<AdminConsultsScreen> createState() => _AdminConsultsScreenState();
}

class _AdminConsultsScreenState extends ConsumerState<AdminConsultsScreen> {
  late Future<List<ConsultSummary>> _future = _load();

  Future<List<ConsultSummary>> _load() => ref.read(adminRepositoryProvider).clinicianConsults(widget.clinicianId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.email, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _auditNotice,
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
                return _Problem(
                  _errorText(snap.error!),
                  onRetry: () {
                    setState(() {
                      _future = _load();
                    });
                  },
                );
              }
              final list = snap.data!;
              if (list.isEmpty) return const _Empty('No consults yet.');
              return Column(
                children: [
                  for (final c in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ConsultSummaryCard(
                        consult: c,
                        onTap: () => context.push('/admin/consult', extra: c.id),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// One consult as an admin sees it. Screenshot-protected; the backend records the view.
class AdminConsultScreen extends ConsumerStatefulWidget {
  const AdminConsultScreen({super.key, required this.consultId});

  final String consultId;

  @override
  ConsumerState<AdminConsultScreen> createState() => _AdminConsultScreenState();
}

class _AdminConsultScreenState extends ConsumerState<AdminConsultScreen> {
  late final Future<ConsultDetail> _future = ref.read(adminRepositoryProvider).consult(widget.consultId);

  @override
  Widget build(BuildContext context) {
    return ProtectedScreen(
      child: Scaffold(
        appBar: AppBar(title: const Text('Consult')),
        body: FutureBuilder<ConsultDetail>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) return _Problem(_errorText(snap.error!), onRetry: () => context.pop());
            final d = snap.data!;
            return ConsultTurnsView(
              detail: d,
              onDownload: (t) => downloadReportPdf(
                context,
                ref,
                replyFromTurn(t, d.id),
                record: () => ref.read(adminRepositoryProvider).recordPdfDownload(d.id, t.id),
              ),
              header: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _auditNotice,
                    if (d.title != null) ...[const SizedBox(height: 12), Text(d.title!, style: AppText.sectionTitle)],
                    if (d.hiddenAt != null) ...[
                      const SizedBox(height: 8),
                      Text('Deleted from the clinician\'s history ${historyWhen(d.hiddenAt)}', style: AppText.caption),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
