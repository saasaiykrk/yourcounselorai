import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/calendar_models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/surfaces.dart';

/// Booking settings → Google Calendar & Meet. Connecting opens Google's consent page in the browser; when the
/// consultant comes back to the app the card reads the connection again. Hidden when the server has no
/// Google sign-in set up.
class GoogleCalendarCard extends ConsumerStatefulWidget {
  const GoogleCalendarCard({super.key});

  @override
  ConsumerState<GoogleCalendarCard> createState() => _GoogleCalendarCardState();
}

class _GoogleCalendarCardState extends ConsumerState<GoogleCalendarCard> with WidgetsBindingObserver {
  bool _busy = false;
  bool _sentToGoogle = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Google's consent page in the browser: read the connection again.
    if (state == AppLifecycleState.resumed && _sentToGoogle) ref.invalidate(googleConnectionProvider);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't reach YourCounselor. Check your connection and try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() => _run(() async {
    final url = await ref.read(calendarRepositoryProvider).googleConnectUrl();
    _sentToGoogle = true;
    await ref.read(openExternalProvider)(url);
    ref.invalidate(googleConnectionProvider);
  });

  Future<void> _meetFor(String v) => _run(() async {
    await ref.read(calendarRepositoryProvider).setGoogleMeetFor(v);
    ref.invalidate(googleConnectionProvider);
  });

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect Google Calendar?'),
        content: const Text(
          'New appointments will no longer be added to your Google Calendar or get a Meet link. '
          'Events already on your calendar stay.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep connected')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Disconnect')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await ref.read(calendarRepositoryProvider).disconnectGoogle();
      ref.invalidate(googleConnectionProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(googleConnectionProvider);
    final c = g.value;
    if (c == null || !c.available) return const SizedBox.shrink();
    return AppCard(
      key: const ValueKey('google-calendar'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.video_call_outlined, color: AppColors.royalPurple),
              SizedBox(width: 8),
              Expanded(child: Text('Google Calendar & Meet', style: AppText.label)),
            ],
          ),
          const SizedBox(height: 6),
          if (!c.connected) ...[
            const Text(
              'Every confirmed appointment goes on your Google Calendar with its own Google Meet link, and the '
              'client gets the invitation. Free with any Google account.',
              style: AppText.caption,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('google-connect'),
              onPressed: _busy ? null : _connect,
              icon: const Icon(Icons.link_rounded),
              label: const Text('Connect Google Calendar'),
            ),
          ] else ...[
            if (c.needsReconnect) ...[
              const NoticeBanner(
                icon: Icons.warning_amber_rounded,
                tone: Tone.check,
                text: 'Google permission was removed. Reconnect so new appointments get events and Meet links.',
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const ValueKey('google-reconnect'),
                onPressed: _busy ? null : _connect,
                child: const Text('Reconnect Google Calendar'),
              ),
            ] else
              Text('Connected as ${c.email}', style: AppText.caption),
            const SizedBox(height: 12),
            const Text('Add a Google Meet link to', style: AppText.label),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              key: const ValueKey('google-meet-for'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'online', label: Text('Online appointments')),
                ButtonSegment(value: 'all', label: Text('Every appointment')),
              ],
              selected: {c.meetFor},
              onSelectionChanged: _busy ? null : (v) => _meetFor(v.first),
            ),
            const SizedBox(height: 4),
            const Text('Appointments without Meet still go on your calendar.', style: AppText.caption),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: _busy ? null : _disconnect, child: const Text('Disconnect')),
            ),
          ],
          if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.crisis)),
        ],
      ),
    );
  }
}

/// The appointment's Meet link opened outside the app (the Meet app or the browser).
class JoinMeetButton extends ConsumerWidget {
  const JoinMeetButton({super.key, required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = appointment.meetUrl;
    if (url == null || !appointment.status.active || !url.startsWith('https://meet.google.com/')) {
      return const SizedBox.shrink();
    }
    return FilledButton.icon(
      key: const ValueKey('join-meet'),
      onPressed: () => ref.read(openExternalProvider)(Uri.parse(url)),
      icon: const Icon(Icons.videocam_outlined),
      label: const Text('Join Google Meet'),
    );
  }
}
