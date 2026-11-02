// Booking settings → Google Calendar & Meet: connect through Google's consent page (in the browser), choose
// which appointments get a Meet link, reconnect after a removed permission, disconnect. And the Join Google
// Meet button on an appointment.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:your_counselor/core/api/calendar_models.dart';
import 'package:your_counselor/core/calendar/calendar_repository.dart';
import 'package:your_counselor/core/providers.dart';
import 'package:your_counselor/features/calendar/google_calendar_card.dart';
import 'package:your_counselor/main.dart';
import 'package:your_counselor/router.dart';

Future<(PreviewCalendarRepository, List<Uri>)> _pump(WidgetTester tester, {GoogleConnection? state}) async {
  final repo = PreviewCalendarRepository();
  if (state != null) repo.googleState = state;
  final opened = <Uri>[];
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        calendarRepositoryProvider.overrideWithValue(repo),
        openExternalProvider.overrideWithValue((u) async {
          opened.add(u);
          return true;
        }),
      ],
      child: YourCounselorApp(router: buildRouter(initialLocation: '/calendar/settings')),
    ),
  );
  await tester.pumpAndSettle();
  return (repo, opened);
}

void main() {
  test('the server describes the connection and the appointment its Meet link', () {
    final g = GoogleConnection.fromJson({
      'available': true,
      'connected': true,
      'status': 'revoked',
      'email': 'a@gmail.com',
      'meet_for': 'all',
    });
    expect((g.connected, g.needsReconnect, g.email, g.meetFor), (true, true, 'a@gmail.com', 'all'));
    expect(GoogleConnection.fromJson({}).meetFor, 'online');
    final a = Appointment.fromJson({
      'id': 'a1',
      'local_start': '2026-11-10T10:00',
      'local_end': '2026-11-10T10:30',
      'status': 'confirmed',
      'meet_url': 'https://meet.google.com/abc-defg-hij',
    });
    expect(a.meetUrl, 'https://meet.google.com/abc-defg-hij');
  });

  testWidgets('connect opens Google, then the choice of Meet links and disconnect', (tester) async {
    final (repo, opened) = await _pump(tester);
    final connect = find.byKey(const ValueKey('google-connect'));
    await tester.ensureVisible(connect);
    expect(find.text('Google Calendar & Meet'), findsOneWidget);
    await tester.tap(connect);
    await tester.pumpAndSettle();
    expect(opened.single.host, 'accounts.google.com', reason: "Google's consent page, in the browser");
    expect(find.text('Connected as you@gmail.com'), findsOneWidget);

    await tester.ensureVisible(find.text('Every appointment'));
    await tester.tap(find.text('Every appointment'));
    await tester.pumpAndSettle();
    expect(repo.googleState.meetFor, 'all');

    await tester.ensureVisible(find.text('Disconnect'));
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Disconnect'));
    await tester.pumpAndSettle();
    expect(repo.googleState.connected, isFalse);
    expect(find.byKey(const ValueKey('google-connect'), skipOffstage: false), findsOneWidget);
  });

  testWidgets('a removed permission asks to reconnect', (tester) async {
    await _pump(
      tester,
      state: const GoogleConnection(available: true, connected: true, status: 'revoked', email: 'a@gmail.com'),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('google-reconnect')));
    expect(find.textContaining('Google permission was removed'), findsOneWidget);
  });

  testWidgets('hidden when the server has no Google sign-in', (tester) async {
    await _pump(tester, state: const GoogleConnection());
    expect(find.text('Google Calendar & Meet'), findsNothing);
  });

  testWidgets('an appointment with a Meet link has Join Google Meet; others do not', (tester) async {
    final opened = <Uri>[];
    Widget button(Appointment a) => ProviderScope(
      overrides: [
        openExternalProvider.overrideWithValue((u) async {
          opened.add(u);
          return true;
        }),
      ],
      child: MaterialApp(
        home: Scaffold(body: JoinMeetButton(appointment: a)),
      ),
    );
    final start = DateTime(2026, 11, 10, 10), end = DateTime(2026, 11, 10, 10, 30);
    await tester.pumpWidget(
      button(
        Appointment(
          id: 'a',
          start: start,
          end: end,
          status: AppointmentStatus.confirmed,
          meetUrl: 'https://meet.google.com/abc-defg-hij',
        ),
      ),
    );
    await tester.tap(find.text('Join Google Meet'));
    expect(opened.single.toString(), 'https://meet.google.com/abc-defg-hij');
    await tester.pumpWidget(
      button(
        Appointment(
          id: 'b',
          start: start,
          end: end,
          status: AppointmentStatus.cancelled,
          meetUrl: 'https://meet.google.com/abc-defg-hij',
        ),
      ),
    );
    expect(find.text('Join Google Meet'), findsNothing, reason: 'a cancelled appointment');
    await tester.pumpWidget(
      button(
        Appointment(
          id: 'c',
          start: start,
          end: end,
          status: AppointmentStatus.confirmed,
          meetUrl: 'https://evil.example',
        ),
      ),
    );
    expect(find.text('Join Google Meet'), findsNothing, reason: 'only Google Meet links');
  });
}
