// Calendar tab: booking link (copy), counts, requests waiting, accept, reschedule without
// duplicates, day/week/month views, settings, working hours, and the API request shapes.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:your_counselor/core/api/api_client.dart';
import 'package:your_counselor/core/api/api_exceptions.dart';
import 'package:your_counselor/core/api/calendar_models.dart';
import 'package:your_counselor/core/calendar/calendar_repository.dart';
import 'package:your_counselor/core/providers.dart';
import 'package:your_counselor/main.dart';
import 'package:your_counselor/router.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final ResponseBody Function(RequestOptions) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    requests.add(o);
    return respond(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

(ApiClient, _Adapter) _api(ResponseBody Function(RequestOptions) respond) {
  final adapter = _Adapter(respond);
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter;
  return (
    ApiClient(baseUrl: 'https://api.test', token: () async => 'tok', timeout: const Duration(seconds: 5), dio: dio),
    adapter,
  );
}

const _appt = {
  'id': 'a1',
  'starts_at': '2026-10-13T05:00:00Z',
  'ends_at': '2026-10-13T05:30:00Z',
  'local_start': '2026-10-13T10:30',
  'local_end': '2026-10-13T11:00',
  'status': 'pending',
  'source': 'public',
  'client': {'first_name': 'Meera', 'email': 'meera@example.com'},
  'pending_until': '2026-10-13T04:00:00Z',
  'cancelled_by': null,
  'rescheduled_from': null,
  'rescheduled_to': null,
  'created_at': '2026-10-12T04:00:00Z',
};

Future<PreviewCalendarRepository> _pump(
  WidgetTester tester, {
  PreviewCalendarRepository? repo,
  String location = '/calendar',
  Size size = const Size(390, 844),
}) async {
  final r = repo ?? PreviewCalendarRepository();
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [calendarRepositoryProvider.overrideWithValue(r)],
      child: YourCounselorApp(router: buildRouter(initialLocation: location)),
    ),
  );
  await tester.pumpAndSettle();
  return r;
}

/// A clinician on Learn (or with no plan): the server refuses the calendar.
class _NoAppointmentsPlan extends PreviewCalendarRepository {
  @override
  Future<CalendarHome> home() async =>
      throw const PlanRequired(feature: 'appointments', message: 'Appointments are in Practice, BYOK Scale and Scale.');
}

/// Scrolls the page's list until [f] is built and on screen.
Future<void> _reach(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a plan without appointments shows which plans have them, and nothing to set up', (tester) async {
    await _pump(tester, repo: _NoAppointmentsPlan());
    expect(find.text('Appointments and your booking page'), findsOneWidget);
    expect(find.text('Appointments are in Practice, BYOK Scale and Scale.'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-see-plans')), findsOneWidget);
    expect(find.byTooltip('Booking settings'), findsNothing);
    expect(find.text('Add'), findsNothing);
  });

  group('models and API', () {
    test('times are the consultant’s wall-clock times, never shifted by the phone’s timezone', () {
      final a = Appointment.fromJson(_appt);
      expect(a.start, DateTime(2026, 10, 13, 10, 30));
      expect(clock(a.start), '10:30 AM');
      expect(a.status, AppointmentStatus.pending);
      expect(a.title, 'Meera');
      final slot = FreeSlot.fromJson({'starts_at': '2026-10-13T05:00:00Z', 'local': '2026-10-13T10:30'});
      expect(slot.local, DateTime(2026, 10, 13, 10, 30));
      expect(wallString(DateTime(2026, 3, 9, 7, 5)), '2026-03-09T07:05');
    });

    test('home parses settings, link, hours, time off and counts', () async {
      final (api, _) = _api(
        (_) => _json(200, {
          'configured': true,
          'settings': {'slug': 'asha-rao', 'display_name': 'Dr Asha Rao', 'enabled': true, 'approval': 'auto'},
          'booking_url': 'https://yc.test/book/asha-rao',
          'windows': [
            {'weekday': 0, 'start': '09:00', 'end': '13:00'},
          ],
          'time_off': [
            {'id': 3, 'local_start': '2026-11-01T00:00', 'local_end': '2026-11-03T00:00', 'label': 'Diwali'},
          ],
          'summary': {'today': 2, 'upcoming': 5, 'pending': 1, 'this_month': 9},
          'today': '2026-10-12',
          'ready': {'booking': true, 'email': false},
          'timezones': ['Asia/Kolkata', 'UTC'],
        }),
      );
      final h = await api.calendar();
      expect(h.settings.autoApprove, isTrue);
      expect(h.bookingUrl, 'https://yc.test/book/asha-rao');
      expect(h.windows.single.end, '13:00');
      expect(h.timeOff.single.label, 'Diwali');
      expect(h.summary!.pending, 1);
      expect(h.today, DateTime(2026, 10, 12));
      expect(h.emailReady, isFalse);
    });

    test('add, move and act send the right requests; times go as local wall times', () async {
      final (api, adapter) = _api((_) => _json(200, {'appointment': _appt}));
      final repo = ApiCalendarRepository(api);
      await repo.add(start: DateTime(2026, 10, 13, 18), firstName: 'Ravi');
      await repo.reschedule('a1', start: DateTime(2026, 10, 14, 9, 30), outsideHours: true);
      await repo.act('a1', 'confirm');
      final [add, move, act] = adapter.requests;
      expect((add.method, add.path), ('POST', '/v1/calendar/appointments'));
      expect(add.data, {'starts_local': '2026-10-13T18:00', 'first_name': 'Ravi'});
      expect(move.path, '/v1/calendar/appointments/a1/reschedule');
      expect(move.data, {'starts_local': '2026-10-14T09:30', 'outside_hours': true});
      expect((act.method, act.path), ('POST', '/v1/calendar/appointments/a1/confirm'));
    });

    test('a refused booking shows the server’s own message', () async {
      final (api, _) = _api(
        (_) => _json(409, {
          'detail': {'error': 'slot_taken', 'message': 'That time overlaps another appointment or time off.'},
        }),
      );
      expect(
        () => api.addAppointment(startsLocal: '2026-10-13T18:00'),
        throwsA(
          predicate(
            (e) => '$e'.isNotEmpty && (e as dynamic).message == 'That time overlaps another appointment or time off.',
          ),
        ),
      );
    });
  });

  group('Calendar tab', () {
    testWidgets('is in the bottom bar and shows the link, counts and waiting requests', (tester) async {
      await _pump(tester, location: '/consult');
      await tester.tap(find.text('Calendar').last);
      await tester.pumpAndSettle();
      expect(find.text('Your booking link'), findsOneWidget);
      expect(find.text('https://yourcounselor.app/book/asha-rao'), findsOneWidget);
      expect(find.text('Taking bookings'), findsOneWidget);
      expect(find.text('Waiting'), findsOneWidget);
      expect(find.textContaining('Requests waiting for you (2)'), findsOneWidget);
    });

    testWidgets('Copy link puts the booking link on the clipboard', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await _pump(tester);
      await tester.tap(find.text('Copy link'));
      await tester.pump();
      expect(copied, 'https://yourcounselor.app/book/asha-rao');
      expect(find.text('Booking link copied'), findsOneWidget);
    });

    testWidgets('accepting a request confirms it', (tester) async {
      final repo = await _pump(tester);
      await tester.tap(find.text('Rahul'));
      await tester.pumpAndSettle();
      expect(find.text('rahul@example.com'), findsOneWidget);
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      final all = await repo.appointments(DateTime(2000), DateTime(2100));
      expect(all.firstWhere((a) => a.clientName == 'Rahul').status, AppointmentStatus.confirmed);
      expect(find.textContaining('Requests waiting for you (1)'), findsOneWidget);
    });

    testWidgets('tags show on the list, and the consultant changes or clears one', (tester) async {
      final repo = await _pump(tester);
      expect(find.text('First Session · Booked by the client'), findsOneWidget);
      await tester.tap(find.text('Meera'));
      await tester.pumpAndSettle();
      expect(find.text('Type of session'), findsOneWidget);
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('tag-first_session'))).selected, isTrue);
      await tester.tap(find.byKey(const ValueKey('tag-follow_up')));
      await tester.pumpAndSettle();
      Future<String?> meera() async =>
          (await repo.appointments(DateTime(2000), DateTime(2100))).firstWhere((a) => a.clientName == 'Meera').tag;
      expect(await meera(), 'follow_up', reason: 'one tag: the new one replaces the old');
      await tester.tap(find.byKey(const ValueKey('tag-follow_up')));
      await tester.pumpAndSettle();
      expect(await meera(), isNull, reason: 'tapping the chosen tag again clears it');
      Navigator.of(tester.element(find.text('Type of session'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Booked by the client'), findsWidgets, reason: 'the list reloads after a tag change');
    });

    test('a tag moves with a reschedule and parses from the server', () async {
      final repo = PreviewCalendarRepository();
      final all = await repo.appointments(DateTime(2000), DateTime(2100));
      final kavya = all.firstWhere((a) => a.clientName == 'Kavya');
      final moved = await repo.reschedule(
        kavya.id,
        start: kavya.start.add(const Duration(hours: 3)),
        outsideHours: true,
      );
      expect(moved.tag, 'follow_up');
      final a = Appointment.fromJson({..._appt, 'tag': 'online'});
      expect((a.tag, a.tagLabel), ('online', 'Online'));
      expect(Appointment.fromJson(_appt).tagLabel, isNull);
    });

    testWidgets('rescheduling moves an appointment and leaves exactly one active', (tester) async {
      final repo = await _pump(tester);
      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      await _reach(tester, find.text('Kavya'));
      await tester.tap(find.text('Kavya'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reschedule'));
      await tester.pumpAndSettle();
      final chip = find.byType(ChoiceChip).at(find.byType(ChoiceChip).evaluate().length - 1);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pump();
      await tester.tap(find.text('Move here'));
      await tester.pumpAndSettle();
      final kavya = (await repo.appointments(DateTime(2000), DateTime(2100))).where((a) => a.clientName == 'Kavya');
      expect(kavya.where((a) => a.status.active).length, 1);
      expect(kavya.where((a) => a.status == AppointmentStatus.rescheduled).length, 1);
    });

    testWidgets('a day can be cancelled with a confirmation', (tester) async {
      final repo = await _pump(tester);
      await tester.tap(find.text('Meera'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cancel appointment'));
      await tester.tap(find.text('Cancel appointment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      final all = await repo.appointments(DateTime(2000), DateTime(2100));
      expect(all.firstWhere((a) => a.clientName == 'Meera').status, AppointmentStatus.cancelled);
    });

    testWidgets('month view: tapping a day opens that day', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();
      final now = DateTime.now();
      expect(find.text('${monthNames[now.month - 1]} ${now.year}'), findsOneWidget);
      final today = find.bySemanticsLabel(RegExp('^${longDay(dayOf(now))}'));
      await _reach(tester, today);
      await tester.tap(today);
      await tester.pumpAndSettle();
      expect(find.textContaining('Today ·'), findsOneWidget);
      expect(find.text('Meera'), findsOneWidget);
    });

    testWidgets('not set up yet: set-up screen, then settings turn it on', (tester) async {
      final repo = PreviewCalendarRepository()..unconfigure();
      await _pump(tester, repo: repo);
      expect(find.text('Set up online booking'), findsOneWidget);
      await tester.tap(find.text('Set up online booking'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Link name'), 'taken');
      await _reach(tester, find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('That link name is taken.'), findsOneWidget);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Link name'), 'dr-asha');
      await tester.tap(find.text('45 min'));
      await _reach(tester, find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final h = await repo.home();
      expect((h.configured, h.settings.slug, h.settings.slotMinutes), (true, 'dr-asha', 45));
      expect(find.text('Your booking link'), findsOneWidget);
    });

    testWidgets('working hours: add Sunday hours and save', (tester) async {
      final repo = await _pump(tester);
      await tester.tap(find.byTooltip('Working hours'));
      await tester.pumpAndSettle();
      await _reach(tester, find.byTooltip('Add hours on Sunday'));
      await tester.tap(find.byTooltip('Add hours on Sunday'));
      await tester.pumpAndSettle();
      await _reach(tester, find.text('Save hours'));
      await tester.tap(find.text('Save hours'));
      await tester.pumpAndSettle();
      final h = await repo.home();
      expect(h.windows.where((w) => w.weekday == 6).single.start, '10:00');
    });

    for (final width in [320.0, 360.0]) {
      testWidgets('fits on a ${width.toInt()}px phone in every view', (tester) async {
        await _pump(tester, size: Size(width, 700));
        for (final v in ['Week', 'Month', 'Day']) {
          await _reach(tester, find.text(v));
          await tester.tap(find.text(v));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  });
}
