/// The consultant's calendar and online booking, as the backend sends them.
///
/// Times: the server sends each instant in UTC (`starts_at`) and as the wall-clock time in the
/// consultant's own timezone (`local_start`). The app shows and groups by the local wall time, so it
/// needs no timezone database and is right even when the phone is set to another timezone.
library;

int _int(Object? v, [int fallback = 0]) => (v as num?)?.toInt() ?? fallback;

/// "2026-10-13T10:30" → a DateTime holding that wall time (never converted between zones).
DateTime wallTime(String v) => DateTime.parse(v.length > 16 ? v.substring(0, 16) : v);

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "10:30 AM"
String clock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// "Tue 13 Oct"
String shortDay(DateTime d) => '${weekdayNames[d.weekday - 1].substring(0, 3)} ${d.day} ${_months[d.month - 1]}';

/// "Tuesday 13 October 2026"
String longDay(DateTime d) => '${weekdayNames[d.weekday - 1]} ${d.day} ${monthNames[d.month - 1]} ${d.year}';

/// "09:00" ↔ minutes since midnight.
int hhmmToMinutes(String v) => int.parse(v.substring(0, 2)) * 60 + int.parse(v.substring(3, 5));

String minutesToHhmm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

/// "9:00 AM" from "09:00".
String hhmmLabel(String v) => clock(DateTime(2000, 1, 1, hhmmToMinutes(v) ~/ 60, hhmmToMinutes(v) % 60));

class BookingSettings {
  const BookingSettings({
    required this.slug,
    required this.displayName,
    this.bio = '',
    this.enabled = false,
    this.timezone = 'Asia/Kolkata',
    this.slotMinutes = 30,
    this.bufferMinutes = 0,
    this.minNoticeMinutes = 240,
    this.maxAdvanceDays = 30,
    this.approval = 'manual',
  });

  factory BookingSettings.fromJson(Map<String, dynamic> j) => BookingSettings(
    slug: j['slug'] as String? ?? '',
    displayName: j['display_name'] as String? ?? '',
    bio: j['bio'] as String? ?? '',
    enabled: j['enabled'] == true,
    timezone: j['timezone'] as String? ?? 'Asia/Kolkata',
    slotMinutes: _int(j['slot_minutes'], 30),
    bufferMinutes: _int(j['buffer_minutes']),
    minNoticeMinutes: _int(j['min_notice_minutes'], 240),
    maxAdvanceDays: _int(j['max_advance_days'], 30),
    approval: j['approval'] as String? ?? 'manual',
  );

  final String slug;
  final String displayName;
  final String bio;
  final bool enabled;
  final String timezone;
  final int slotMinutes;
  final int bufferMinutes;
  final int minNoticeMinutes;
  final int maxAdvanceDays;

  /// auto: requests are confirmed at once · manual: the consultant accepts or declines.
  final String approval;

  bool get autoApprove => approval == 'auto';

  Map<String, dynamic> toJson() => {
    'slug': slug,
    'display_name': displayName,
    'bio': bio,
    'enabled': enabled,
    'timezone': timezone,
    'slot_minutes': slotMinutes,
    'buffer_minutes': bufferMinutes,
    'min_notice_minutes': minNoticeMinutes,
    'max_advance_days': maxAdvanceDays,
    'approval': approval,
  };

  BookingSettings copyWith({
    String? slug,
    String? displayName,
    String? bio,
    bool? enabled,
    String? timezone,
    int? slotMinutes,
    int? bufferMinutes,
    int? minNoticeMinutes,
    int? maxAdvanceDays,
    String? approval,
  }) => BookingSettings(
    slug: slug ?? this.slug,
    displayName: displayName ?? this.displayName,
    bio: bio ?? this.bio,
    enabled: enabled ?? this.enabled,
    timezone: timezone ?? this.timezone,
    slotMinutes: slotMinutes ?? this.slotMinutes,
    bufferMinutes: bufferMinutes ?? this.bufferMinutes,
    minNoticeMinutes: minNoticeMinutes ?? this.minNoticeMinutes,
    maxAdvanceDays: maxAdvanceDays ?? this.maxAdvanceDays,
    approval: approval ?? this.approval,
  );
}

/// One working period on a weekday (0 = Monday). Several on one day leave breaks between them.
class WorkWindow {
  const WorkWindow({required this.weekday, required this.start, required this.end});

  factory WorkWindow.fromJson(Map<String, dynamic> j) =>
      WorkWindow(weekday: _int(j['weekday']), start: j['start'] as String, end: j['end'] as String);

  final int weekday;
  final String start; // "09:00"
  final String end;

  Map<String, dynamic> toJson() => {'weekday': weekday, 'start': start, 'end': end};
}

class TimeOff {
  const TimeOff({required this.id, required this.startsAt, required this.endsAt, this.label = ''});

  factory TimeOff.fromJson(Map<String, dynamic> j) => TimeOff(
    id: _int(j['id']),
    startsAt: wallTime(j['local_start'] as String),
    endsAt: wallTime(j['local_end'] as String),
    label: j['label'] as String? ?? '',
  );

  final int id;

  /// Wall-clock times in the consultant's timezone (the end is exclusive).
  final DateTime startsAt;
  final DateTime endsAt;
  final String label;
}

class CalendarSummary {
  const CalendarSummary({
    this.today = 0,
    this.upcoming = 0,
    this.pending = 0,
    this.thisMonth = 0,
    this.completed = 0,
    this.cancelled = 0,
    this.total = 0,
  });

  factory CalendarSummary.fromJson(Map<String, dynamic> j) => CalendarSummary(
    today: _int(j['today']),
    upcoming: _int(j['upcoming']),
    pending: _int(j['pending']),
    thisMonth: _int(j['this_month']),
    completed: _int(j['completed']),
    cancelled: _int(j['cancelled']),
    total: _int(j['total']),
  );

  final int today;
  final int upcoming;
  final int pending;
  final int thisMonth;
  final int completed;
  final int cancelled;
  final int total;
}

/// Everything the Calendar tab opens with.
class CalendarHome {
  const CalendarHome({
    required this.configured,
    required this.settings,
    this.bookingUrl,
    this.windows = const [],
    this.timeOff = const [],
    this.summary,
    required this.today,
    this.bookingReady = true,
    this.emailReady = false,
    this.timezones = const ['Asia/Kolkata'],
  });

  factory CalendarHome.fromJson(Map<String, dynamic> j) {
    final ready = j['ready'] as Map<String, dynamic>? ?? const {};
    return CalendarHome(
      configured: j['configured'] == true,
      settings: BookingSettings.fromJson(j['settings'] as Map<String, dynamic>? ?? const {}),
      bookingUrl: j['booking_url'] as String?,
      windows: [for (final w in (j['windows'] as List? ?? const [])) WorkWindow.fromJson(w as Map<String, dynamic>)],
      timeOff: [for (final t in (j['time_off'] as List? ?? const [])) TimeOff.fromJson(t as Map<String, dynamic>)],
      summary: j['summary'] is Map<String, dynamic>
          ? CalendarSummary.fromJson(j['summary'] as Map<String, dynamic>)
          : null,
      today: j['today'] is String ? DateTime.parse(j['today'] as String) : dayOf(DateTime.now()),
      bookingReady: ready['booking'] != false,
      emailReady: ready['email'] == true,
      timezones: [
        for (final t in (j['timezones'] as List? ?? const ['Asia/Kolkata'])) '$t',
      ],
    );
  }

  final bool configured;
  final BookingSettings settings;
  final String? bookingUrl;
  final List<WorkWindow> windows;
  final List<TimeOff> timeOff;
  final CalendarSummary? summary;

  /// Today in the consultant's timezone.
  final DateTime today;

  /// The server can store client details (its encryption key is set).
  final bool bookingReady;

  /// Booking emails are switched on for this server.
  final bool emailReady;
  final List<String> timezones;
}

enum AppointmentStatus {
  pending('Waiting for you'),
  confirmed('Confirmed'),
  completed('Completed'),
  cancelled('Cancelled'),
  rejected('Declined'),
  expired('Expired'),
  rescheduled('Moved');

  const AppointmentStatus(this.label);

  final String label;

  static AppointmentStatus parse(String? v) =>
      AppointmentStatus.values.firstWhere((s) => s.name == v, orElse: () => AppointmentStatus.cancelled);

  bool get active => this == pending || this == confirmed;
}

/// What kind of session an appointment is: one tag, or none (the server's booking.TAGS).
const kAppointmentTags = {'first_session': 'First Session', 'follow_up': 'Follow-up', 'online': 'Online'};

class Appointment {
  const Appointment({
    required this.id,
    required this.start,
    required this.end,
    required this.status,
    this.source = 'public',
    this.clientName,
    this.clientEmail,
    this.pendingUntil,
    this.cancelledBy,
    this.rescheduledFrom,
    this.rescheduledTo,
    this.tag,
  });

  factory Appointment.fromJson(Map<String, dynamic> j) {
    final client = j['client'] as Map<String, dynamic>?;
    return Appointment(
      id: j['id'] as String,
      start: wallTime(j['local_start'] as String),
      end: wallTime(j['local_end'] as String),
      status: AppointmentStatus.parse(j['status'] as String?),
      source: j['source'] as String? ?? 'public',
      clientName: client?['first_name'] as String?,
      clientEmail: client?['email'] as String?,
      pendingUntil: j['pending_until'] is String ? DateTime.parse(j['pending_until'] as String).toLocal() : null,
      cancelledBy: j['cancelled_by'] as String?,
      rescheduledFrom: j['rescheduled_from'] as String?,
      rescheduledTo: j['rescheduled_to'] as String?,
      tag: j['tag'] as String?,
    );
  }

  final String id;

  /// Wall-clock times in the consultant's timezone.
  final DateTime start;
  final DateTime end;
  final AppointmentStatus status;

  /// public: booked through the link · consultant: added in the app.
  final String source;
  final String? clientName;
  final String? clientEmail;
  final DateTime? pendingUntil;
  final String? cancelledBy;
  final String? rescheduledFrom;
  final String? rescheduledTo;

  /// first_session · follow_up · online, or null.
  final String? tag;

  String? get tagLabel => kAppointmentTags[tag];

  String get title => clientName ?? (source == 'consultant' ? 'Appointment' : 'Client');

  Appointment copyWith({AppointmentStatus? status, String? cancelledBy, Object? tag = _keep}) => Appointment(
    id: id,
    start: start,
    end: end,
    status: status ?? this.status,
    source: source,
    clientName: clientName,
    clientEmail: clientEmail,
    cancelledBy: cancelledBy ?? this.cancelledBy,
    rescheduledFrom: rescheduledFrom,
    rescheduledTo: rescheduledTo,
    tag: identical(tag, _keep) ? this.tag : tag as String?,
  );
}

const _keep = Object();

/// A free time: the instant to send back (UTC) and its wall time to show.
class FreeSlot {
  const FreeSlot({required this.startsAt, required this.local});

  factory FreeSlot.fromJson(Map<String, dynamic> j) =>
      FreeSlot(startsAt: j['starts_at'] as String, local: wallTime(j['local'] as String));

  final String startsAt;
  final DateTime local;
}

class FreeDay {
  const FreeDay({required this.date, required this.slots});

  factory FreeDay.fromJson(Map<String, dynamic> j) => FreeDay(
    date: DateTime.parse(j['date'] as String),
    slots: [for (final s in (j['slots'] as List? ?? const [])) FreeSlot.fromJson(s as Map<String, dynamic>)],
  );

  final DateTime date;
  final List<FreeSlot> slots;
}
