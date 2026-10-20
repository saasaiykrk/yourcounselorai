import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/calendar_models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/surfaces.dart';
import 'calendar_screen.dart';

/// Details of one appointment and what can be done with it now. Returns true if it changed.
Future<bool?> showAppointmentSheet(BuildContext context, Appointment a) async {
  var tagged = false; // a changed tag also means the list should reload
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => AppointmentSheet(appointment: a, onTagged: () => tagged = true),
  );
  return r == true || tagged;
}

/// First Session · Follow-up · Online: one, or none (tap the chosen one again to clear it).
class TagChoice extends StatelessWidget {
  const TagChoice({super.key, required this.value, required this.onChanged, this.enabled = true});

  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final MapEntry(:key, value: label) in kAppointmentTags.entries)
        ChoiceChip(
          key: ValueKey('tag-$key'),
          label: Text(label),
          selected: value == key,
          onSelected: enabled ? (on) => onChanged(on ? key : null) : null,
        ),
    ],
  );
}

/// Add an appointment (a free time, or any time the consultant chooses). Returns true if added.
Future<bool?> showAddAppointmentSheet(BuildContext context, DateTime day) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => AddAppointmentSheet(day: day),
);

class AppointmentSheet extends ConsumerStatefulWidget {
  const AppointmentSheet({super.key, required this.appointment, this.onTagged});

  final Appointment appointment;

  /// Told when the consultant changes the tag (the sheet stays open).
  final VoidCallback? onTagged;

  @override
  ConsumerState<AppointmentSheet> createState() => _AppointmentSheetState();
}

class _AppointmentSheetState extends ConsumerState<AppointmentSheet> {
  String? _busy;
  String? _error;
  bool _moving = false;
  late String? _tag = widget.appointment.tag;

  Future<void> _setTag(String? tag) async {
    final before = _tag;
    setState(() {
      _tag = tag;
      _busy = 'tag';
      _error = null;
    });
    try {
      await ref.read(calendarRepositoryProvider).setTag(widget.appointment.id, tag);
      widget.onTagged?.call();
      if (mounted) setState(() => _busy = null);
    } catch (e) {
      if (mounted) {
        setState(() {
          _tag = before;
          _busy = null;
          _error = calendarErrorText(e);
        });
      }
    }
  }

  Future<void> _act(String action, {String? confirm}) async {
    if (confirm != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(confirm),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      _busy = action;
      _error = null;
    });
    try {
      await ref.read(calendarRepositoryProvider).act(widget.appointment.id, action);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = null;
          _error = calendarErrorText(e);
        });
      }
    }
  }

  Future<void> _reschedule(DateTime start, bool outsideHours) async {
    setState(() {
      _busy = 'reschedule';
      _error = null;
    });
    try {
      await ref
          .read(calendarRepositoryProvider)
          .reschedule(widget.appointment.id, start: start, outsideHours: outsideHours);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = null;
          _error = calendarErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    final started = !a.start.isAfter(DateTime.now());
    final busy = _busy != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(a.title, style: AppText.sheetTitle.copyWith(fontSize: 22))),
                StatusPill(a.status.label, tone: statusTone(a.status)),
              ],
            ),
            const SizedBox(height: 6),
            Text('${longDay(a.start)}\n${clock(a.start)} – ${clock(a.end)}', style: AppText.body),
            const SizedBox(height: 12),
            AppCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(Icons.person_outline_rounded, a.clientName ?? 'No name given'),
                  _row(Icons.mail_outline_rounded, a.clientEmail ?? 'No email given'),
                  _row(
                    a.source == 'public' ? Icons.link_rounded : Icons.edit_calendar_outlined,
                    a.source == 'public' ? 'Booked through your link' : 'Added by you',
                  ),
                  if (a.status == AppointmentStatus.pending && a.pendingUntil != null)
                    _row(
                      Icons.hourglass_bottom_rounded,
                      'Held until ${shortDay(a.pendingUntil!)} ${clock(a.pendingUntil!)}',
                    ),
                  if (a.cancelledBy != null) _row(Icons.info_outline_rounded, 'Cancelled by the ${a.cancelledBy}'),
                  if (a.rescheduledFrom != null) _row(Icons.update_rounded, 'Moved from an earlier time'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text('Type of session', style: AppText.label),
            const SizedBox(height: 8),
            TagChoice(value: _tag, enabled: !busy, onChanged: _setTag),
            if (_error != null) ...[
              const SizedBox(height: 12),
              NoticeBanner(icon: Icons.error_outline_rounded, tone: Tone.crisis, text: _error!),
            ],
            const SizedBox(height: 16),
            if (_moving) ...[
              const Text('Choose a new time', style: AppText.label),
              const SizedBox(height: 8),
              SlotPicker(
                from: dayOf(a.start).isBefore(dayOf(DateTime.now())) ? dayOf(DateTime.now()) : dayOf(a.start),
                ignore: a.id,
                busy: busy,
                actionLabel: 'Move here',
                onChosen: _reschedule,
              ),
              TextButton(onPressed: busy ? null : () => setState(() => _moving = false), child: const Text('Back')),
            ] else ...[
              if (a.status == AppointmentStatus.pending) ...[
                FilledButton.icon(
                  onPressed: busy ? null : () => _act('confirm'),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(_busy == 'confirm' ? 'Accepting…' : 'Accept'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _act('reject', confirm: 'Decline this request? The client is told.'),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Decline'),
                ),
                const SizedBox(height: 8),
              ],
              if (a.status.active) ...[
                OutlinedButton.icon(
                  onPressed: busy ? null : () => setState(() => _moving = true),
                  icon: const Icon(Icons.update_rounded),
                  label: const Text('Reschedule'),
                ),
                const SizedBox(height: 8),
              ],
              if (a.status == AppointmentStatus.confirmed && started) ...[
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _act('complete'),
                  icon: const Icon(Icons.task_alt_rounded),
                  label: const Text('Mark completed'),
                ),
                const SizedBox(height: 8),
              ],
              if (a.status.active)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: AppColors.crisis),
                  onPressed: busy
                      ? null
                      : () => _act(
                          'cancel',
                          confirm: a.clientEmail != null
                              ? 'Cancel this appointment? The client is told by email if email is set up.'
                              : 'Cancel this appointment?',
                        ),
                  icon: const Icon(Icons.event_busy_outlined),
                  label: const Text('Cancel appointment'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppColors.muted),
        const SizedBox(width: 10),
        Expanded(child: SelectableText(text, style: AppText.small)),
      ],
    ),
  );
}

/// Free times for the next two weeks, plus "Another time…" for any time (outside working hours too).
class SlotPicker extends ConsumerStatefulWidget {
  const SlotPicker({
    super.key,
    required this.from,
    required this.onChosen,
    this.ignore,
    this.busy = false,
    this.actionLabel = 'Choose',
  });

  final DateTime from;
  final String? ignore;
  final bool busy;
  final String actionLabel;

  /// (start as a wall time in the consultant's timezone, outside the free times?)
  final void Function(DateTime start, bool outsideHours) onChosen;

  @override
  ConsumerState<SlotPicker> createState() => _SlotPickerState();
}

class _SlotPickerState extends ConsumerState<SlotPicker> {
  late Future<List<FreeDay>> _days;
  DateTime? _day;
  DateTime? _slot;

  @override
  void initState() {
    super.initState();
    _days = ref.read(calendarRepositoryProvider).freeSlots(widget.from, days: 14, ignore: widget.ignore);
  }

  Future<void> _other() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _day ?? widget.from,
      firstDate: dayOf(now),
      lastDate: dayOf(now).add(const Duration(days: 365)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 10, minute: 0));
    if (t == null) return;
    widget.onChosen(DateTime(d.year, d.month, d.day, t.hour, t.minute), true);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FreeDay>>(
      future: _days,
      builder: (context, snap) {
        if (snap.hasError) {
          return Text(calendarErrorText(snap.error!), style: AppText.smallMuted);
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final days = snap.data!;
        final day = days.where((d) => d.date == _day).firstOrNull ?? days.firstOrNull;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (days.isEmpty)
              const Text('No free times in the next two weeks.', style: AppText.smallMuted)
            else ...[
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final d in days)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(shortDay(d.date)),
                          selected: d.date == day?.date,
                          onSelected: (_) => setState(() {
                            _day = d.date;
                            _slot = null;
                          }),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in day!.slots)
                    ChoiceChip(
                      label: Text(clock(s.local)),
                      selected: s.local == _slot,
                      onSelected: (_) => setState(() {
                        _day = day.date;
                        _slot = s.local;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _slot == null || widget.busy ? null : () => widget.onChosen(_slot!, false),
                child: Text(widget.busy ? 'Saving…' : widget.actionLabel),
              ),
            ],
            TextButton.icon(
              onPressed: widget.busy ? null : _other,
              icon: const Icon(Icons.more_time_rounded),
              label: const Text('Another time (outside your hours)…'),
            ),
          ],
        );
      },
    );
  }
}

class AddAppointmentSheet extends ConsumerStatefulWidget {
  const AddAppointmentSheet({super.key, required this.day});

  final DateTime day;

  @override
  ConsumerState<AddAppointmentSheet> createState() => _AddAppointmentSheetState();
}

class _AddAppointmentSheetState extends ConsumerState<AddAppointmentSheet> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _tag;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save(DateTime start, bool _) async {
    final name = _name.text.trim(), email = _email.text.trim();
    if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$').hasMatch(email)) {
      setState(() => _error = 'Please enter a valid email, or leave it empty.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(calendarRepositoryProvider)
          .add(start: start, firstName: name.isEmpty ? null : name, email: email.isEmpty ? null : email, tag: _tag);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = calendarErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = dayOf(DateTime.now());
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add an appointment', style: AppText.sheetTitle.copyWith(fontSize: 22)),
            const SizedBox(height: 4),
            const Text(
              'Client details are optional. With an email, the client gets the confirmation and a cancel link.',
              style: AppText.smallMuted,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'First name (optional)', counterText: ''),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _email,
              maxLength: 254,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email (optional)', counterText: ''),
            ),
            const SizedBox(height: 14),
            const Text('Type of session (optional)', style: AppText.label),
            const SizedBox(height: 8),
            TagChoice(value: _tag, enabled: !_busy, onChanged: (t) => setState(() => _tag = t)),
            if (_error != null) ...[
              const SizedBox(height: 12),
              NoticeBanner(icon: Icons.error_outline_rounded, tone: Tone.crisis, text: _error!),
            ],
            const SizedBox(height: 16),
            const Text('Time', style: AppText.label),
            const SizedBox(height: 8),
            SlotPicker(
              from: widget.day.isBefore(today) ? today : widget.day,
              busy: _busy,
              actionLabel: 'Add appointment',
              onChosen: _save,
            ),
          ],
        ),
      ),
    );
  }
}
