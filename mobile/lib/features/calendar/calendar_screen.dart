import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/api/calendar_models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import 'appointment_sheet.dart';

/// What to show for a failed calendar call. Server refusals carry their own plain message.
String calendarErrorText(Object e) => switch (e) {
  PlanRequired(:final message) => message,
  BillingRefused(:final message) => message,
  NetworkProblem() => "Couldn't reach Your Counselor. Check your connection.",
  NotFound() => 'This appointment no longer exists.',
  Unauthorized() => 'Please sign in again.',
  NotVerified() => 'The calendar is available once your registration is verified.',
  _ => 'Something went wrong. Please try again.',
};

Tone statusTone(AppointmentStatus s) => switch (s) {
  AppointmentStatus.pending => Tone.check,
  AppointmentStatus.confirmed => Tone.brand,
  AppointmentStatus.completed => Tone.neutral,
  _ => Tone.crisis,
};

enum CalendarView { day, week, month }

/// The consultant's calendar: booking link, counts, and appointments by day, week or month.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => CalendarScreenState();
}

class CalendarScreenState extends ConsumerState<CalendarScreen> {
  CalendarView _view = CalendarView.day;
  DateTime? _focus; // a day in the consultant's timezone
  Future<List<Appointment>>? _appts;
  Future<List<Appointment>>? _waiting;
  DateTime? _today;

  (DateTime, DateTime) _range(DateTime f) => switch (_view) {
    CalendarView.day => (f, f),
    CalendarView.week => (f.subtract(Duration(days: f.weekday - 1)), f.add(Duration(days: 7 - f.weekday))),
    CalendarView.month => (DateTime(f.year, f.month), DateTime(f.year, f.month + 1, 0)),
  };

  void _load() {
    final repo = ref.read(calendarRepositoryProvider);
    final (a, b) = _range(_focus!);
    setState(() {
      _appts = repo.appointments(a, b);
      _waiting = repo
          .appointments(_today!, _today!.add(const Duration(days: 60)))
          .then(
            (l) => [
              for (final x in l)
                if (x.status == AppointmentStatus.pending) x,
            ],
          );
    });
  }

  /// Re-reads everything (after any change).
  void refresh() {
    ref.invalidate(calendarHomeProvider);
    if (_focus != null) _load();
  }

  void _move(int step) {
    final f = _focus!;
    _focus = switch (_view) {
      CalendarView.day => f.add(Duration(days: step)),
      CalendarView.week => f.add(Duration(days: 7 * step)),
      CalendarView.month => DateTime(f.year, f.month + step),
    };
    _load();
  }

  Future<void> _open(Appointment a) async {
    final changed = await showAppointmentSheet(context, a);
    if (changed == true && mounted) refresh();
  }

  Future<void> _add() async {
    final added = await showAddAppointmentSheet(context, _focus ?? _today!);
    if (added == true && mounted) refresh();
  }

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(calendarHomeProvider);
    final configured = home.value?.configured == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          if (configured) ...[
            IconButton(
              tooltip: 'Working hours',
              icon: const Icon(Icons.schedule_rounded),
              onPressed: () => context.push('/calendar/hours').then((_) => refresh()),
            ),
            IconButton(
              tooltip: 'Time off',
              icon: const Icon(Icons.event_busy_outlined),
              onPressed: () => context.push('/calendar/time-off').then((_) => refresh()),
            ),
          ],
          if (home.error is! PlanRequired)
            IconButton(
              tooltip: 'Booking settings',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => context.push('/calendar/settings').then((_) => refresh()),
            ),
        ],
      ),
      floatingActionButton: configured
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add'),
            )
          : null,
      body: home.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            e is PlanRequired ? _Locked(message: e.message) : _Problem(text: calendarErrorText(e), onRetry: refresh),
        data: (h) {
          if (!h.configured) return _SetUp(home: h);
          if (_today != h.today) {
            _today = h.today;
            _focus ??= h.today;
            WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _load() : null);
          }
          return RefreshIndicator(
            onRefresh: () async {
              refresh();
              await ref.read(calendarHomeProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              children: [
                _LinkCard(home: h),
                const SizedBox(height: 12),
                if (h.summary != null) _Stats(summary: h.summary!),
                if (_waiting != null) _Waiting(future: _waiting!, onOpen: _open),
                const SizedBox(height: 16),
                SegmentedButton<CalendarView>(
                  segments: const [
                    ButtonSegment(value: CalendarView.day, label: Text('Day')),
                    ButtonSegment(value: CalendarView.week, label: Text('Week')),
                    ButtonSegment(value: CalendarView.month, label: Text('Month')),
                  ],
                  selected: {_view},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) {
                    _view = v.first;
                    _load();
                  },
                ),
                const SizedBox(height: 8),
                if (_focus != null) _navigator(h),
                const SizedBox(height: 8),
                if (_appts != null)
                  FutureBuilder<List<Appointment>>(
                    future: _appts,
                    builder: (context, snap) {
                      if (snap.hasError) return _Problem(text: calendarErrorText(snap.error!), onRetry: _load);
                      if (!snap.hasData) {
                        return const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final list = snap.data!;
                      return switch (_view) {
                        CalendarView.day => _DayList(appointments: list, onOpen: _open),
                        CalendarView.week => _WeekList(
                          first: _range(_focus!).$1,
                          appointments: list,
                          today: h.today,
                          onOpen: _open,
                        ),
                        CalendarView.month => _MonthGrid(
                          month: _focus!,
                          appointments: list,
                          today: h.today,
                          onPick: (d) {
                            _focus = d;
                            _view = CalendarView.day;
                            _load();
                          },
                        ),
                      };
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _navigator(CalendarHome h) {
    final f = _focus!;
    final (a, b) = _range(f);
    final label = switch (_view) {
      CalendarView.day => f == h.today ? 'Today · ${shortDay(f)}' : longDay(f),
      CalendarView.week => '${shortDay(a)} – ${shortDay(b)}',
      CalendarView.month => '${monthNames[f.month - 1]} ${f.year}',
    };
    return Row(
      children: [
        IconButton(tooltip: 'Previous', onPressed: () => _move(-1), icon: const Icon(Icons.chevron_left_rounded)),
        Expanded(
          child: Text(label, textAlign: TextAlign.center, style: AppText.label.copyWith(fontSize: 16)),
        ),
        IconButton(tooltip: 'Next', onPressed: () => _move(1), icon: const Icon(Icons.chevron_right_rounded)),
        TextButton(
          onPressed: f == h.today
              ? null
              : () {
                  _focus = h.today;
                  _load();
                },
          child: const Text('Today'),
        ),
      ],
    );
  }
}

class _SetUp extends StatelessWidget {
  const _SetUp({required this.home});

  final CalendarHome home;

  @override
  Widget build(BuildContext context) {
    return PageBody(
      actions: [
        FilledButton.icon(
          onPressed: () => context.push('/calendar/settings'),
          icon: const Icon(Icons.event_available_rounded),
          label: const Text('Set up online booking'),
        ),
      ],
      children: const [
        Align(
          alignment: Alignment.centerLeft,
          child: IconTile(icon: Icons.calendar_month_rounded),
        ),
        PageHeading(
          'Your calendar',
          message:
              'Share a booking link so clients can choose a free time. You set your working hours, '
              'breaks, appointment length and days off, and decide whether requests need your approval.',
        ),
        NoticeBanner(
          icon: Icons.lock_outline_rounded,
          text:
              'Clients give only a first name and an email. They are stored encrypted and deleted 90 days '
              'after the appointment. No health details are asked for.',
        ),
      ],
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.home});

  final CalendarHome home;

  @override
  Widget build(BuildContext context) {
    final on = home.settings.enabled;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Your booking link', style: AppText.label)),
              StatusPill(
                on ? 'Taking bookings' : 'Off',
                tone: on ? Tone.brand : Tone.neutral,
                icon: on ? Icons.check_circle_rounded : Icons.pause_circle_outline_rounded,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            home.bookingUrl ?? '',
            style: const TextStyle(fontSize: 15, color: AppColors.royalPurple, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: home.bookingUrl == null
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: home.bookingUrl!));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('Booking link copied')));
                        }
                      },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy link'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${home.settings.slotMinutes} min · ${home.settings.autoApprove ? 'auto-confirm' : 'you approve'}',
                  style: AppText.caption,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          if (!on) ...[
            const SizedBox(height: 8),
            const Text('Clients can’t book until you switch booking on in settings.', style: AppText.caption),
          ],
          if (!home.bookingReady) ...[
            const SizedBox(height: 10),
            const NoticeBanner(
              icon: Icons.info_outline_rounded,
              tone: Tone.check,
              text: 'Online booking is not switched on for this server yet. You can still use your calendar.',
            ),
          ],
          if (home.windows.isEmpty) ...[
            const SizedBox(height: 10),
            NoticeBanner(
              icon: Icons.schedule_rounded,
              tone: Tone.check,
              text: 'Add your working hours so clients see free times.',
            ),
          ],
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.summary});

  final CalendarSummary summary;

  @override
  Widget build(BuildContext context) {
    Widget tile(String label, int n, {Tone tone = Tone.brand}) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(color: tone.background, borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            Text(
              '$n',
              style: TextStyle(fontFamily: 'Nunito', fontSize: 22, fontWeight: FontWeight.w800, color: tone.foreground),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: tone.foreground),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
    return Row(
      children: [
        tile('Today', summary.today),
        const SizedBox(width: 8),
        tile('Upcoming', summary.upcoming),
        const SizedBox(width: 8),
        tile('Waiting', summary.pending, tone: summary.pending > 0 ? Tone.check : Tone.neutral),
        const SizedBox(width: 8),
        tile('This month', summary.thisMonth, tone: Tone.neutral),
      ],
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.future, required this.onOpen});

  final Future<List<Appointment>> future;
  final void Function(Appointment) onOpen;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Appointment>>(
      future: future,
      builder: (context, snap) {
        final list = snap.data ?? const <Appointment>[];
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Requests waiting for you (${list.length})', style: AppText.sectionTitle.copyWith(fontSize: 17)),
              const SizedBox(height: 8),
              for (final a in list) AppointmentTile(appointment: a, onTap: () => onOpen(a), showDate: true),
            ],
          ),
        );
      },
    );
  }
}

/// One appointment in a list.
class AppointmentTile extends StatelessWidget {
  const AppointmentTile({super.key, required this.appointment, required this.onTap, this.showDate = false});

  final Appointment appointment;
  final VoidCallback onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final faded = !a.status.active && a.status != AppointmentStatus.completed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 40,
                  decoration: BoxDecoration(
                    color: statusTone(a.status).foreground,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 78,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(clock(a.start), style: AppText.label),
                      Text(showDate ? shortDay(a.start) : clock(a.end), style: AppText.caption),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.title,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.label.copyWith(
                          decoration: faded ? TextDecoration.lineThrough : null,
                          color: faded ? AppColors.muted : AppColors.ink,
                        ),
                      ),
                      Text(
                        [?a.tagLabel, a.source == 'public' ? 'Booked by the client' : 'Added by you'].join(' · '),
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
                StatusPill(a.status.label, tone: statusTone(a.status)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DayList extends StatelessWidget {
  const _DayList({required this.appointments, required this.onOpen});

  final List<Appointment> appointments;
  final void Function(Appointment) onOpen;

  @override
  Widget build(BuildContext context) {
    final shown = appointments.where((a) => a.status != AppointmentStatus.rescheduled).toList();
    if (shown.isEmpty) return const _Empty('No appointments on this day.');
    return Column(
      children: [for (final a in shown) AppointmentTile(appointment: a, onTap: () => onOpen(a))],
    );
  }
}

class _WeekList extends StatelessWidget {
  const _WeekList({required this.first, required this.appointments, required this.today, required this.onOpen});

  final DateTime first;
  final List<Appointment> appointments;
  final DateTime today;
  final void Function(Appointment) onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < 7; i++)
          Builder(
            builder: (context) {
              final d = first.add(Duration(days: i));
              final day = [
                for (final a in appointments)
                  if (dayOf(a.start) == d && a.status != AppointmentStatus.rescheduled) a,
              ];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        d == today ? 'Today · ${shortDay(d)}' : shortDay(d),
                        style: AppText.label.copyWith(color: d == today ? AppColors.royalPurple : AppColors.muted),
                      ),
                    ),
                    if (day.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(left: 4, bottom: 4),
                        child: Text('No appointments', style: AppText.caption),
                      ),
                    for (final a in day) AppointmentTile(appointment: a, onTap: () => onOpen(a)),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.appointments, required this.today, required this.onPick});

  final DateTime month;
  final List<Appointment> appointments;
  final DateTime today;
  final void Function(DateTime) onPick;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday - 1;
    final counts = <int, (int, int)>{}; // day → (active, waiting)
    for (final a in appointments) {
      if (a.start.month != month.month || !(a.status.active || a.status == AppointmentStatus.completed)) continue;
      final (n, w) = counts[a.start.day] ?? (0, 0);
      counts[a.start.day] = (n + 1, w + (a.status == AppointmentStatus.pending ? 1 : 0));
    }
    return Column(
      children: [
        Row(
          children: [
            for (final w in weekdayNames)
              Expanded(
                child: Center(child: Text(w.substring(0, 1), style: AppText.caption)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 0.8,
          children: [
            for (var i = 0; i < lead; i++) const SizedBox.shrink(),
            for (var d = 1; d <= days; d++)
              Builder(
                builder: (context) {
                  final date = DateTime(month.year, month.month, d);
                  final (n, w) = counts[d] ?? (0, 0);
                  final isToday = date == today;
                  return Semantics(
                    button: true,
                    label: '${longDay(date)}, $n appointments',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => onPick(date),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isToday ? AppColors.lavender : AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isToday ? AppColors.royalPurple : AppColors.line),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$d',
                              style: TextStyle(
                                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                                color: isToday ? AppColors.royalPurple : AppColors.ink,
                              ),
                            ),
                            if (n > 0)
                              Container(
                                margin: const EdgeInsets.only(top: 2),
                                padding: const EdgeInsets.symmetric(horizontal: 5),
                                decoration: BoxDecoration(
                                  color: w > 0 ? AppColors.checkBg : AppColors.lavender,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$n',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: w > 0 ? AppColors.checkInk : AppColors.royalPurple,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Tap a day to see its appointments. Amber: a request is waiting for you.', style: AppText.caption),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Column(
      children: [
        const Icon(Icons.event_available_outlined, color: AppColors.muted, size: 32),
        const SizedBox(height: 8),
        Text(text, style: AppText.bodyMuted, textAlign: TextAlign.center),
      ],
    ),
  );
}

/// The plan doesn't include appointments (Learn, or no plan): say which plans do.
class _Locked extends StatelessWidget {
  const _Locked({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const SizedBox(height: 24),
      const Center(child: IconTile(icon: Icons.lock_outline_rounded, size: 56)),
      const SizedBox(height: 16),
      const Text('Appointments and your booking page', style: AppText.sectionTitle, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text(message, style: AppText.bodyMuted, textAlign: TextAlign.center),
      const SizedBox(height: 18),
      FilledButton(
        key: const ValueKey('calendar-see-plans'),
        onPressed: () => context.push('/pricing'),
        child: const Text('See plans'),
      ),
    ],
  );
}

class _Problem extends StatelessWidget {
  const _Problem({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: AppText.bodyMuted, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}
