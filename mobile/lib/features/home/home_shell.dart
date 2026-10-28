import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../history/history_screen.dart';

/// Bottom navigation between Consult, History, Calendar, Education and Account.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const historyBranch = 1;
  static const calendarBranch = 2;
  static const educationBranch = 3;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    // Load the calendar in the background as soon as the home screen opens (after the plan check), so
    // the Calendar tab is ready when tapped. Listening keeps it loaded; errors show on the tab itself.
    ref.listenManual(calendarHomeProvider, (_, _) {});
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) {
          // History is re-read every time it is opened (a consult may have just finished).
          if (i == HomeShell.historyBranch) ref.read(historyRefreshProvider.notifier).bump();
          // The calendar too: bookings arrive from clients at any time.
          if (i == HomeShell.calendarBranch) ref.invalidate(calendarHomeProvider);
          // Education links are signed for a few hours: fetch fresh ones each time.
          if (i == HomeShell.educationBranch) ref.invalidate(educationPagesProvider);
          shell.goBranch(i, initialLocation: i == shell.currentIndex);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Consult',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded),
            selectedIcon: Icon(Icons.history_toggle_off_rounded),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school_rounded),
            label: 'Knowledge',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}
