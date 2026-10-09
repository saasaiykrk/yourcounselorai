import 'package:go_router/go_router.dart';

import 'core/content/legal_content.dart';
import 'features/account/account_screen.dart';
import 'features/account/edit_profile_screen.dart';
import 'features/account/info_screen.dart';
import 'core/api/api_exceptions.dart';
import 'features/admin/admin_screen.dart';
import 'features/billing/billing_history_screen.dart';
import 'features/billing/own_key_screen.dart';
import 'features/billing/pricing_screen.dart';
import 'features/consult/consult_screen.dart';
import 'features/consult/drafting_screen.dart';
import 'features/consult/reply_screen.dart';
import 'features/consultation/consultation_screen.dart';
import 'features/gallery/gallery_screen.dart';
import 'features/history/history_screen.dart';
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
            routes: [GoRoute(path: '/history', builder: (_, _) => const HistoryScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/account', builder: (_, _) => const AccountScreen())],
          ),
        ],
      ),
      GoRoute(path: '/account/profile', builder: (_, _) => const EditProfileScreen()),
      GoRoute(path: '/drafting', builder: (_, _) => const DraftingScreen()),
      GoRoute(path: '/consultation', builder: (_, _) => const ConsultationScreen()),
      GoRoute(path: '/reply', builder: (_, _) => const ReplyScreen()),
      GoRoute(path: '/safety', builder: (_, _) => const SafetyScreen()),
      GoRoute(
        path: '/privacy',
        builder: (_, _) => const InfoScreen(doc: kPrivacyDoc),
      ),
      GoRoute(
        path: '/terms',
        builder: (_, _) => const InfoScreen(doc: kTermsDoc),
      ),
      GoRoute(
        path: '/dpa',
        builder: (_, _) => const InfoScreen(doc: kDpaDoc),
      ),
      GoRoute(path: '/held-back', builder: (_, _) => const HeldBackScreen()),
      GoRoute(
        path: '/identifiers',
        builder: (_, state) => IdentifiersScreen(types: state.extra as List<String>? ?? const ['ID']),
      ),
      GoRoute(path: '/limit', builder: (_, _) => const LimitScreen()),
      GoRoute(path: '/pricing', builder: (_, _) => const PricingScreen()),
      GoRoute(path: '/pricing/own-key', builder: (_, _) => const OwnKeyScreen()),
      GoRoute(path: '/pricing/history', builder: (_, _) => const BillingHistoryScreen()),
      GoRoute(
        path: '/no-credit',
        builder: (_, state) => NoCreditScreen(error: state.extra as ApiException?),
      ),
      GoRoute(
        path: '/offline',
        builder: (_, state) => OfflineScreen(error: state.extra),
      ),
      GoRoute(path: '/gallery', builder: (_, _) => const GalleryScreen()),
      GoRoute(
        path: '/history/consult',
        builder: (_, state) => HistoryConsultScreen(consultId: state.extra as String? ?? ''),
      ),
      GoRoute(path: '/admin', builder: (_, _) => const AdminScreen()),
      GoRoute(
        path: '/admin/consults',
        builder: (_, state) {
          final (id, email) = state.extra as (String, String)? ?? ('', '');
          return AdminConsultsScreen(clinicianId: id, email: email);
        },
      ),
      GoRoute(
        path: '/admin/consult',
        builder: (_, state) => AdminConsultScreen(consultId: state.extra as String? ?? ''),
      ),
      GoRoute(
        path: '/admin/report',
        builder: (_, state) => AdminReportScreen(incidentId: state.extra as String? ?? ''),
      ),
    ],
  );
}
