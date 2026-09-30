import 'package:go_router/go_router.dart';

import 'features/account/account_screen.dart';
import 'features/consult/consult_screen.dart';
import 'features/consult/drafting_screen.dart';
import 'features/consult/reply_screen.dart';
import 'features/gallery/gallery_screen.dart';
import 'features/home/home_shell.dart';
import 'features/onboarding/onboarding_screens.dart';
import 'features/states/state_screens.dart';

GoRouter buildRouter({String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),
      GoRoute(
        path: '/code',
        builder: (_, state) => CodeScreen(email: state.extra as String?),
      ),
      GoRoute(path: '/details', builder: (_, _) => const DetailsScreen()),
      GoRoute(path: '/pending', builder: (_, _) => const PendingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/consult', builder: (_, _) => const ConsultScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/account', builder: (_, _) => const AccountScreen())],
          ),
        ],
      ),
      GoRoute(path: '/drafting', builder: (_, _) => const DraftingScreen()),
      GoRoute(path: '/reply', builder: (_, _) => const ReplyScreen()),
      GoRoute(path: '/safety', builder: (_, _) => const SafetyScreen()),
      GoRoute(path: '/held-back', builder: (_, _) => const HeldBackScreen()),
      GoRoute(
        path: '/identifiers',
        builder: (_, state) => IdentifiersScreen(types: state.extra as List<String>? ?? const ['ID']),
      ),
      GoRoute(path: '/limit', builder: (_, _) => const LimitScreen()),
      GoRoute(
        path: '/offline',
        builder: (_, state) => OfflineScreen(error: state.extra),
      ),
      GoRoute(path: '/gallery', builder: (_, _) => const GalleryScreen()),
    ],
  );
}
