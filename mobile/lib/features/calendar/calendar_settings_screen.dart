import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/calendar_models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/surfaces.dart';
import 'calendar_screen.dart';

String _minutesLabel(int m) => m == 0
    ? 'None'
    : m < 60
    ? '$m min'
    : m % 1440 == 0
    ? '${m ~/ 1440} day${m == 1440 ? '' : 's'}'
    : '${m ~/ 60} hour${m == 60 ? '' : 's'}';

/// Booking link name, on/off, appointment length, buffer, notice, how far ahead, timezone, approval.
class CalendarSettingsScreen extends ConsumerStatefulWidget {
  const CalendarSettingsScreen({super.key});

  @override
  ConsumerState<CalendarSettingsScreen> createState() => _CalendarSettingsScreenState();
}

class _CalendarSettingsScreenState extends ConsumerState<CalendarSettingsScreen> {
  BookingSettings? _s;
  final _slug = TextEditingController();
  final _name = TextEditingController();
  final _bio = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _slug.dispose();
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _init(BookingSettings s) {
    if (_s != null) return;
    _s = s;
    _slug.text = s.slug;
    _name.text = s.displayName;
    _bio.text = s.bio;
  }

  Future<void> _save() async {
    final s = _s!.copyWith(
      slug: _slug.text.trim().toLowerCase(),
      displayName: _name.text.trim(),
      bio: _bio.text.trim(),
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(calendarRepositoryProvider).saveSettings(s);
      ref.invalidate(calendarHomeProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking settings saved')));
        Navigator.pop(context);
      }
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
    final home = ref.watch(calendarHomeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Booking settings')),
      body: home.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(calendarErrorText(e), style: AppText.bodyMuted)),
        data: (h) {
          _init(h.settings);
          final s = _s!;
          void set(BookingSettings v) => setState(() => _s = v);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Take bookings online', style: AppText.label),
                  subtitle: const Text('Clients can book free times through your link', style: AppText.caption),
                  value: s.enabled,
                  onChanged: (v) => set(s.copyWith(enabled: v)),
                ),
              ),
              if (!h.bookingReady && s.enabled)
                const NoticeBanner(
                  icon: Icons.info_outline_rounded,
                  tone: Tone.check,
                  text: 'Online booking is not switched on for this server yet, so this can’t be turned on.',
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Name clients see', counterText: ''),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _slug,
                maxLength: 40,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Link name',
                  helperText: 'Lowercase letters, numbers and hyphens, e.g. asha-rao',
                  prefixText: '/book/',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bio,
                maxLength: 500,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Short introduction (optional)',
                  helperText: 'Shown on your booking page. No contact numbers or client details.',
                ),
              ),
              const SizedBox(height: 18),
              const Text('Appointment length', style: AppText.label),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in const [15, 30, 45, 60])
                    ChoiceChip(
                      label: Text('$m min'),
                      selected: s.slotMinutes == m,
                      onSelected: (_) => set(s.copyWith(slotMinutes: m)),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              _drop<int>(
                'Break after each appointment',
                s.bufferMinutes,
                const [0, 5, 10, 15, 30, 45, 60],
                _minutesLabel,
                (v) => set(s.copyWith(bufferMinutes: v)),
              ),
              _drop<int>(
                'Minimum notice before an appointment',
                s.minNoticeMinutes,
                const [0, 60, 120, 240, 720, 1440, 2880],
                _minutesLabel,
                (v) => set(s.copyWith(minNoticeMinutes: v)),
              ),
              _drop<int>(
                'How far ahead clients can book',
                s.maxAdvanceDays,
                const [7, 14, 30, 60, 90],
                (d) => '$d days',
                (v) => set(s.copyWith(maxAdvanceDays: v)),
              ),
              _drop<String>(
                'Timezone',
                s.timezone,
                {...h.timezones, s.timezone}.toList(),
                (t) => t.replaceAll('_', ' '),
                (v) => set(s.copyWith(timezone: v)),
              ),
              const SizedBox(height: 6),
              const Text('New requests', style: AppText.label),
              const SizedBox(height: 4),
              RadioGroup<String>(
                groupValue: s.approval,
                onChanged: (v) => set(s.copyWith(approval: v)),
                child: const Column(
                  children: [
                    RadioListTile(
                      contentPadding: EdgeInsets.zero,
                      value: 'manual',
                      title: Text('I accept or decline each request'),
                      subtitle: Text('The time is held for 24 hours while you decide', style: AppText.caption),
                    ),
                    RadioListTile(
                      contentPadding: EdgeInsets.zero,
                      value: 'auto',
                      title: Text('Confirm automatically'),
                      subtitle: Text('Free times are confirmed as soon as they are booked', style: AppText.caption),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                NoticeBanner(icon: Icons.error_outline_rounded, tone: Tone.crisis, text: _error!),
              ],
              const SizedBox(height: 16),
              FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save')),
            ],
          );
        },
      ),
    );
  }

  Widget _drop<T>(String label, T value, List<T> options, String Function(T) show, void Function(T) onChanged) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: DropdownButtonFormField<T>(
          initialValue: options.contains(value) ? value : options.first,
          decoration: InputDecoration(labelText: label),
          items: [for (final o in options) DropdownMenuItem(value: o, child: Text(show(o)))],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      );
}

/// Weekly working hours. Several periods on one day leave breaks between them.
class WorkingHoursScreen extends ConsumerStatefulWidget {
  const WorkingHoursScreen({super.key});

  @override
  ConsumerState<WorkingHoursScreen> createState() => _WorkingHoursScreenState();
}

class _WorkingHoursScreenState extends ConsumerState<WorkingHoursScreen> {
  List<WorkWindow>? _w;
  bool _busy = false;
  String? _error;

  Future<String?> _pick(String initial) async {
    final m = hhmmToMinutes(initial);
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
    );
    return t == null ? null : minutesToHhmm(t.hour * 60 + t.minute);
  }

  Future<void> _editTime(int i, {required bool start}) async {
    final w = _w![i];
    final v = await _pick(start ? w.start : w.end);
    if (v == null) return;
    setState(() {
      _w![i] = WorkWindow(weekday: w.weekday, start: start ? v : w.start, end: start ? w.end : v);
    });
  }

  void _add(int weekday) {
    final day = _w!.where((w) => w.weekday == weekday).toList();
    final from = day.isEmpty ? 10 * 60 : (hhmmToMinutes(day.last.end) + 60).clamp(0, 22 * 60);
    setState(() {
      _w!.add(
        WorkWindow(weekday: weekday, start: minutesToHhmm(from), end: minutesToHhmm((from + 180).clamp(0, 1439))),
      );
      _w!.sort((a, b) => a.weekday != b.weekday ? a.weekday - b.weekday : a.start.compareTo(b.start));
    });
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(calendarRepositoryProvider).saveAvailability(_w!);
      ref.invalidate(calendarHomeProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Working hours saved')));
        Navigator.pop(context);
      }
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
    final home = ref.watch(calendarHomeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Working hours')),
      body: home.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(calendarErrorText(e), style: AppText.bodyMuted)),
        data: (h) {
          _w ??= List.of(h.windows);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                'Times are in ${h.settings.timezone.replaceAll('_', ' ')}. Add a second period on a day to leave a break.',
                style: AppText.smallMuted,
              ),
              const SizedBox(height: 12),
              for (var d = 0; d < 7; d++) ...[
                AppCard(
                  padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(weekdayNames[d], style: AppText.label)),
                          if (_w!.where((w) => w.weekday == d).isEmpty)
                            const Text('Not working', style: AppText.caption),
                          IconButton(
                            tooltip: 'Add hours on ${weekdayNames[d]}',
                            icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.royalPurple),
                            onPressed: _w!.where((w) => w.weekday == d).length >= 4 ? null : () => _add(d),
                          ),
                        ],
                      ),
                      for (final (i, w) in _w!.indexed)
                        if (w.weekday == d)
                          Row(
                            children: [
                              TextButton(onPressed: () => _editTime(i, start: true), child: Text(hhmmLabel(w.start))),
                              const Text('to'),
                              TextButton(onPressed: () => _editTime(i, start: false), child: Text(hhmmLabel(w.end))),
                              const Spacer(),
                              IconButton(
                                tooltip: 'Remove',
                                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.muted),
                                onPressed: () => setState(() => _w!.removeAt(i)),
                              ),
                            ],
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_error != null) ...[
                NoticeBanner(icon: Icons.error_outline_rounded, tone: Tone.crisis, text: _error!),
                const SizedBox(height: 8),
              ],
              FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save hours')),
            ],
          );
        },
      ),
    );
  }
}

/// Holidays and other days off. Existing appointments in them are kept and pointed out.
class TimeOffScreen extends ConsumerStatefulWidget {
  const TimeOffScreen({super.key});

  @override
  ConsumerState<TimeOffScreen> createState() => _TimeOffScreenState();
}

class _TimeOffScreenState extends ConsumerState<TimeOffScreen> {
  bool _busy = false;

  Future<void> _add(CalendarHome h) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: h.today,
      lastDate: h.today.add(const Duration(days: 365)),
      helpText: 'Days off',
    );
    if (range == null || !mounted) return;
    final label = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Days off'),
        content: TextField(
          controller: label,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Label (optional)', hintText: 'e.g. Diwali'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final clashes = await ref
          .read(calendarRepositoryProvider)
          .addTimeOff(from: range.start, to: range.end, label: label.text.trim());
      ref.invalidate(calendarHomeProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              clashes == 0
                  ? 'Days off added'
                  : 'Days off added. $clashes appointment${clashes == 1 ? ' is' : 's are'} already booked then: '
                        'open the calendar to move or cancel ${clashes == 1 ? 'it' : 'them'}.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(calendarErrorText(e))));
    } finally {
      label.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(TimeOff t) async {
    try {
      await ref.read(calendarRepositoryProvider).deleteTimeOff(t.id);
      ref.invalidate(calendarHomeProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(calendarErrorText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(calendarHomeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Time off')),
      floatingActionButton: home.hasValue
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : () => _add(home.value!),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add days off'),
            )
          : null,
      body: home.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(calendarErrorText(e), style: AppText.bodyMuted)),
        data: (h) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            const Text(
              'No free times are offered on days off. Appointments already booked then are kept: you decide '
              'whether to move or cancel them.',
              style: AppText.smallMuted,
            ),
            const SizedBox(height: 12),
            if (h.timeOff.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No days off planned.', style: AppText.bodyMuted, textAlign: TextAlign.center),
              ),
            for (final t in h.timeOff)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                  child: Row(
                    children: [
                      const Icon(Icons.beach_access_outlined, color: AppColors.royalPurple),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.label.isEmpty ? 'Time off' : t.label, style: AppText.label),
                            Text(_span(t), style: AppText.caption),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.muted),
                        onPressed: () => _delete(t),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _span(TimeOff t) {
    final a = t.startsAt, b = t.endsAt.subtract(const Duration(minutes: 1));
    return dayOf(a) == dayOf(b) ? shortDay(a) : '${shortDay(a)} – ${shortDay(b)}';
  }
}
