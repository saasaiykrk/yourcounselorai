import 'dart:convert';

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
import '../../core/widgets/surfaces.dart';
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

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Registrations'),
              Tab(text: 'Reports'),
            ],
          ),
        ),
        body: const TabBarView(children: [_RegistrationsTab(), _ReportsTab()]),
      ),
    );
  }
}

// --- registrations -------------------------------------------------------------

class _RegistrationsTab extends ConsumerStatefulWidget {
  const _RegistrationsTab();

  @override
  ConsumerState<_RegistrationsTab> createState() => _RegistrationsTabState();
}

class _RegistrationsTabState extends ConsumerState<_RegistrationsTab> {
  String _status = 'pending';
  late Future<List<AdminClinician>> _future = _load();

  Future<List<AdminClinician>> _load() => ref.read(adminRepositoryProvider).clinicians(_status);

  void _reload() {
    setState(() {
      _future = _load();
    });
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(approve ? 'Approved ${c.email}' : 'Rejected ${c.email}')));
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        await _future.catchError((_) => <AdminClinician>[]);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'pending', label: Text('Waiting')),
              ButtonSegment(value: 'verified', label: Text('Verified')),
              ButtonSegment(value: 'rejected', label: Text('Rejected')),
            ],
            selected: {_status},
            showSelectedIcon: false,
            onSelectionChanged: (s) {
              _status = s.first;
              _reload();
            },
          ),
          const SizedBox(height: 12),
          if (_status == 'pending')
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Check each registration number on the official register (RCI / NMC / State Medical Council) before approving.',
                style: AppText.caption,
              ),
            ),
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
              final list = snap.data!;
              if (list.isEmpty) {
                return _Empty(_status == 'pending' ? 'Nobody is waiting for approval.' : 'None yet.');
              }
              return Column(
                children: [
                  for (final c in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ClinicianCard(
                        clinician: c,
                        onApprove: c.verificationStatus == 'pending' ? () => _decide(c, approve: true) : null,
                        onReject: c.verificationStatus == 'pending' ? () => _decide(c, approve: false) : null,
                        onConsults: c.verificationStatus == 'verified'
                            ? () => context.push('/admin/consults', extra: (c.id, c.email))
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

class _ClinicianCard extends StatelessWidget {
  const _ClinicianCard({required this.clinician, this.onApprove, this.onReject, this.onConsults});

  final AdminClinician clinician;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onConsults;

  @override
  Widget build(BuildContext context) {
    final c = clinician;
    final reg = c.registrationBody != null && c.registrationBody != 'none'
        ? '${c.registrationBody} ${c.registrationNumber ?? '(no number)'}'
        : 'No registration given';
    final (pill, tone) = switch (c.verificationStatus) {
      'verified' => ('Verified · ${c.level}', Tone.brand),
      'rejected' => ('Rejected', Tone.crisis),
      _ => ('Waiting', Tone.check),
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(c.fullName ?? c.email, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              StatusPill(pill, tone: tone),
            ],
          ),
          const SizedBox(height: 4),
          if (c.fullName != null || c.gender != null || c.age != null)
            Text(
              [
                if (c.fullName != null) c.email,
                if (c.gender != null) kGenders[c.gender] ?? c.gender!,
                if (c.age != null) 'age ${c.age}',
              ].join(' · '),
              style: AppText.smallMuted,
            ),
          Text('${adminRoles[c.role] ?? c.role} · $reg', style: AppText.smallMuted),
          Text(
            'Registered ${_when(c.createdAt)}${c.verificationNote != null ? ' · ${c.verificationNote}' : ''}',
            style: AppText.caption,
          ),
          if (onConsults != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onConsults,
              icon: const Icon(Icons.history_rounded, size: 18),
              label: const Text('Consults'),
            ),
          ],
          if (onApprove != null || onReject != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(onPressed: onApprove, child: const Text('Approve')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.crisis),
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
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.approve ? 'Approve registration' : 'Reject registration', style: AppText.sheetTitle),
          const SizedBox(height: 4),
          Text('${c.email} · ${adminRoles[c.role] ?? c.role}', style: AppText.smallMuted),
          if (widget.approve) ...[
            const SizedBox(height: 16),
            const Text('Level', style: AppText.label),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'L1', label: Text('L1')),
                ButtonSegment(value: 'L2', label: Text('L2')),
                ButtonSegment(value: 'L3', label: Text('L3')),
              ],
              selected: {_level},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _level = s.first),
            ),
          ],
          const SizedBox(height: 16),
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
  const _ReportsTab();

  @override
  ConsumerState<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<_ReportsTab> {
  String? _status = 'open';
  late Future<List<AdminIncident>> _future = _load();

  Future<List<AdminIncident>> _load() => ref.read(adminRepositoryProvider).incidents(_status);

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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, label) in [
                ('open', 'Open'),
                ('triaged', 'Triaged'),
                ('fixed', 'Fixed'),
                ('wont_fix', "Won't fix"),
                (null, 'All'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _status == value,
                  onSelected: (_) {
                    _status = value;
                    _reload();
                  },
                ),
            ],
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
              if (list.isEmpty) return const _Empty('No reports here.');
              return Column(
                children: [
                  for (final i in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _IncidentCard(
                        incident: i,
                        onTap: () async {
                          await context.push('/admin/report', extra: i.id);
                          if (mounted) _reload();
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

class _IncidentCard extends StatelessWidget {
  const _IncidentCard({required this.incident, required this.onTap});

  final AdminIncident incident;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final i = incident;
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
                      adminCategories[i.category] ?? i.category,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(
                    adminIncidentStatuses[i.status] ?? i.status,
                    tone: i.status == 'open' ? Tone.check : Tone.brand,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${i.automatic ? 'Automatic' : 'Reported by clinician'} · ${_when(i.createdAt)} · ${i.level ?? ''}',
                style: AppText.caption,
              ),
            ],
          ),
        ),
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
      if (mounted) setState(() => _message = 'Saved.');
    } catch (e) {
      if (mounted) setState(() => _message = _errorText(e));
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
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Text(adminCategories[i.category] ?? i.category, style: AppText.screenTitle),
                const SizedBox(height: 4),
                Text(
                  '${i.automatic ? 'Automatic' : 'Reported by clinician'} · ${_when(i.createdAt)} · '
                  'mode ${i.requestedMode ?? '?'} · ${i.level ?? ''} · reply ${i.turnStatus ?? ''}',
                  style: AppText.caption,
                ),
                if (i.note != null && i.note!.isNotEmpty) _Block('Report note', i.note!),
                _Block('Case as sent (de-identified)', i.inputDeid ?? ''),
                _Block('Reply as shown to the clinician', i.outputShown ?? ''),
                _Block('Safety-check reports', const JsonEncoder.withIndent('  ').convert(i.inspectorReports)),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    for (final e in adminIncidentStatuses.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _status = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  maxLength: 2000,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(labelText: 'Reviewer note', counterText: ''),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save')),
                if (_message != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _message!,
                    style: TextStyle(color: _message == 'Saved.' ? AppColors.royalPurple : AppColors.crisis),
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
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Text(text, textAlign: TextAlign.center, style: AppText.bodyMuted),
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
