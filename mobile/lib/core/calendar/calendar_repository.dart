import '../api/api_client.dart';
import '../api/api_exceptions.dart';
import '../api/calendar_models.dart';

/// The consultant's calendar, working hours, time off and appointments.
abstract interface class CalendarRepository {
  Future<CalendarHome> home();

  Future<void> saveSettings(BookingSettings settings);

  Future<void> saveAvailability(List<WorkWindow> windows);

  /// Returns how many existing appointments fall in the new time off.
  Future<int> addTimeOff({required DateTime from, required DateTime to, String label});

  Future<void> deleteTimeOff(int id);

  Future<List<Appointment>> appointments(DateTime start, DateTime end);

  Future<List<FreeDay>> freeSlots(DateTime start, {int days, String? ignore});

  Future<Appointment> add({required DateTime start, String? firstName, String? email});

  Future<Appointment> reschedule(String id, {required DateTime start, bool outsideHours});

  /// [action]: confirm · reject · cancel · complete.
  Future<Appointment> act(String id, String action);
}

/// "2026-10-13T18:00": a wall time in the consultant's timezone.
String wallString(DateTime t) => '${isoDate(t)}T${minutesToHhmm(t.hour * 60 + t.minute)}';

class ApiCalendarRepository implements CalendarRepository {
  ApiCalendarRepository(this._api);

  final ApiClient _api;

  @override
  Future<CalendarHome> home() => _api.calendar();

  @override
  Future<void> saveSettings(BookingSettings settings) => _api.saveCalendarSettings(settings);

  @override
  Future<void> saveAvailability(List<WorkWindow> windows) => _api.saveAvailability(windows);

  @override
  Future<int> addTimeOff({required DateTime from, required DateTime to, String label = ''}) =>
      _api.addTimeOff(from: from, to: to, label: label);

  @override
  Future<void> deleteTimeOff(int id) => _api.deleteTimeOff(id);

  @override
  Future<List<Appointment>> appointments(DateTime start, DateTime end) => _api.appointments(start, end);

  @override
  Future<List<FreeDay>> freeSlots(DateTime start, {int days = 7, String? ignore}) =>
      _api.freeSlots(start, days: days, ignore: ignore);

  @override
  Future<Appointment> add({required DateTime start, String? firstName, String? email}) =>
      _api.addAppointment(startsLocal: wallString(start), firstName: firstName, email: email);

  @override
  Future<Appointment> reschedule(String id, {required DateTime start, bool outsideHours = false}) =>
      _api.rescheduleAppointment(id, startsLocal: wallString(start), outsideHours: outsideHours);

  @override
  Future<Appointment> act(String id, String action) => _api.appointmentAction(id, action);
}

/// Offline preview: a sample calendar kept in memory. Same rules as the server for overlaps,
/// working hours and the allowed status changes, so the screens behave the same way.
class PreviewCalendarRepository implements CalendarRepository {
  PreviewCalendarRepository({DateTime? now}) : _now = now ?? DateTime.now() {
    final t = dayOf(_now);
    DateTime at(int days, int h, [int m = 0]) => t.add(Duration(days: days, hours: h, minutes: m));
    var n = 0;
    Appointment a(DateTime s, AppointmentStatus st, {String? name, String? email, String source = 'public'}) =>
        Appointment(
          id: 'preview-${n++}',
          start: s,
          end: s.add(Duration(minutes: _settings.slotMinutes)),
          status: st,
          source: source,
          clientName: name,
          clientEmail: email,
        );
    _appts.addAll([
      a(at(0, 10), AppointmentStatus.confirmed, name: 'Meera', email: 'meera@example.com'),
      a(at(0, 15, 30), AppointmentStatus.pending, name: 'Arjun', email: 'arjun@example.com'),
      a(at(1, 11), AppointmentStatus.confirmed, name: 'Kavya', email: 'kavya@example.com'),
      a(at(2, 16), AppointmentStatus.pending, name: 'Rahul', email: 'rahul@example.com'),
      a(at(3, 12), AppointmentStatus.confirmed, source: 'consultant'),
      a(at(-1, 10), AppointmentStatus.completed, name: 'Sana', email: 'sana@example.com'),
      a(at(-2, 14), AppointmentStatus.cancelled, name: 'Dev', email: 'dev@example.com'),
    ]);
  }

  final DateTime _now;
  final _appts = <Appointment>[];
  final _off = <TimeOff>[];
  var _configured = true;
  var _settings = const BookingSettings(
    slug: 'asha-rao',
    displayName: 'Dr Asha Rao',
    bio: 'Clinical psychologist. Anxiety, mood and stress.',
    enabled: true,
  );
  var _windows = [
    for (var d = 0; d < 5; d++) ...[
      WorkWindow(weekday: d, start: '10:00', end: '13:00'),
      WorkWindow(weekday: d, start: '14:00', end: '18:00'),
    ],
    const WorkWindow(weekday: 5, start: '10:00', end: '13:00'),
  ];

  /// Starts the preview with booking not yet set up.
  void unconfigure() => _configured = false;

  CalendarSummary _summary() {
    final today = dayOf(_now);
    bool on(Appointment a, DateTime d) => dayOf(a.start) == d;
    return CalendarSummary(
      today: _appts.where((a) => on(a, today) && a.status != AppointmentStatus.cancelled).length,
      upcoming: _appts.where((a) => a.status.active && a.start.isAfter(_now)).length,
      pending: _appts.where((a) => a.status == AppointmentStatus.pending).length,
      thisMonth: _appts.where((a) => a.start.month == _now.month && a.start.year == _now.year).length,
      completed: _appts.where((a) => a.status == AppointmentStatus.completed).length,
      cancelled: _appts.where((a) => a.status == AppointmentStatus.cancelled).length,
      total: _appts.length,
    );
  }

  @override
  Future<CalendarHome> home() async => CalendarHome(
    configured: _configured,
    settings: _settings,
    bookingUrl: _configured ? 'https://yourcounselor.app/book/${_settings.slug}' : null,
    windows: List.of(_windows),
    timeOff: List.of(_off),
    summary: _configured ? _summary() : null,
    today: dayOf(_now),
    timezones: const ['Asia/Kolkata', 'Asia/Dubai', 'Europe/London', 'America/New_York', 'UTC'],
  );

  @override
  Future<void> saveSettings(BookingSettings settings) async {
    if (settings.slug == 'taken') throw const BillingRefused(code: 'slug_taken', message: 'That link name is taken.');
    _settings = settings;
    _configured = true;
  }

  @override
  Future<void> saveAvailability(List<WorkWindow> windows) async => _windows = List.of(windows);

  @override
  Future<int> addTimeOff({required DateTime from, required DateTime to, String label = ''}) async {
    final end = dayOf(to).add(const Duration(days: 1));
    _off.add(TimeOff(id: _off.length + 1, startsAt: dayOf(from), endsAt: end, label: label));
    return _appts.where((a) => a.status.active && !a.start.isBefore(dayOf(from)) && a.start.isBefore(end)).length;
  }

  @override
  Future<void> deleteTimeOff(int id) async => _off.removeWhere((t) => t.id == id);

  @override
  Future<List<Appointment>> appointments(DateTime start, DateTime end) async {
    final hi = dayOf(end).add(const Duration(days: 1));
    return [
      for (final a in _appts)
        if (!a.start.isBefore(dayOf(start)) && a.start.isBefore(hi)) a,
    ]..sort((a, b) => a.start.compareTo(b.start));
  }

  bool _clash(DateTime s, {String? ignore}) {
    final e = s.add(Duration(minutes: _settings.slotMinutes + _settings.bufferMinutes));
    final blocked = _appts.any(
      (a) =>
          a.id != ignore &&
          a.status.active &&
          s.isBefore(a.end.add(Duration(minutes: _settings.bufferMinutes))) &&
          a.start.isBefore(e),
    );
    final off = _off.any((t) => s.isBefore(t.endsAt) && t.startsAt.isBefore(e));
    return blocked || off;
  }

  @override
  Future<List<FreeDay>> freeSlots(DateTime start, {int days = 7, String? ignore}) async {
    final out = <FreeDay>[];
    for (var i = 0; i < days; i++) {
      final d = dayOf(start).add(Duration(days: i));
      final slots = <FreeSlot>[];
      for (final w in _windows.where((w) => w.weekday == d.weekday - 1)) {
        for (
          var m = hhmmToMinutes(w.start);
          m + _settings.slotMinutes <= hhmmToMinutes(w.end);
          m += _settings.slotMinutes
        ) {
          final s = d.add(Duration(minutes: m));
          if (s.isAfter(_now) && !_clash(s, ignore: ignore)) {
            slots.add(FreeSlot(startsAt: s.toUtc().toIso8601String(), local: s));
          }
        }
      }
      if (slots.isNotEmpty) out.add(FreeDay(date: d, slots: slots));
    }
    return out;
  }

  Never _taken() => throw const BillingRefused(code: 'slot_taken', message: 'That time is not free.', status: 409);

  @override
  Future<Appointment> add({required DateTime start, String? firstName, String? email}) async {
    if (start.isBefore(_now) || _clash(start)) _taken();
    final a = Appointment(
      id: 'preview-${_appts.length + 100}',
      start: start,
      end: start.add(Duration(minutes: _settings.slotMinutes)),
      status: AppointmentStatus.confirmed,
      source: 'consultant',
      clientName: firstName,
      clientEmail: email,
    );
    _appts.add(a);
    return a;
  }

  @override
  Future<Appointment> reschedule(String id, {required DateTime start, bool outsideHours = false}) async {
    final i = _appts.indexWhere((a) => a.id == id);
    if (i < 0) throw const NotFound();
    final old = _appts[i];
    if (!old.status.active) {
      throw const BillingRefused(code: 'not_allowed', message: 'This one can no longer be moved.');
    }
    if (start.isBefore(_now) || _clash(start, ignore: id)) _taken();
    final moved = Appointment(
      id: 'preview-${_appts.length + 100}',
      start: start,
      end: start.add(Duration(minutes: _settings.slotMinutes)),
      status: AppointmentStatus.confirmed,
      source: old.source,
      clientName: old.clientName,
      clientEmail: old.clientEmail,
      rescheduledFrom: id,
    );
    _appts[i] = old.copyWith(status: AppointmentStatus.rescheduled);
    _appts.add(moved);
    return moved;
  }

  static const _moves = {
    'confirm': ({AppointmentStatus.pending}, AppointmentStatus.confirmed),
    'reject': ({AppointmentStatus.pending}, AppointmentStatus.rejected),
    'cancel': ({AppointmentStatus.pending, AppointmentStatus.confirmed}, AppointmentStatus.cancelled),
    'complete': ({AppointmentStatus.confirmed}, AppointmentStatus.completed),
  };

  @override
  Future<Appointment> act(String id, String action) async {
    final i = _appts.indexWhere((a) => a.id == id);
    if (i < 0) throw const NotFound();
    final (from, to) = _moves[action]!;
    final a = _appts[i];
    if (!from.contains(a.status) || (action == 'complete' && a.start.isAfter(_now))) {
      throw const BillingRefused(code: 'not_allowed', message: "This appointment can't be changed that way now.");
    }
    return _appts[i] = a.copyWith(status: to, cancelledBy: to == AppointmentStatus.cancelled ? 'consultant' : null);
  }
}
