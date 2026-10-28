/// Riverpod wiring: which implementation each part of the app uses in the
/// current [AppMode]. Tests override these providers with fakes.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'api/api_exceptions.dart';
import 'api/api_models.dart';
import 'auth/auth_service.dart';
import 'billing/billing_repository.dart';
import 'calendar/calendar_repository.dart';
import 'education/education_repository.dart';
import 'billing/payment_gateway.dart';
import 'api/billing_models.dart';
import 'api/calendar_models.dart';
import 'config.dart';
import 'repositories.dart';

final authServiceProvider = Provider<AuthService>(
  (ref) => AppConfig.mode == AppMode.live ? SupabaseAuthService() : DevAuthService(AppConfig.devToken),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final auth = ref.watch(authServiceProvider);
  return ApiClient(baseUrl: AppConfig.backendUrl, token: auth.accessToken, timeout: AppConfig.consultTimeout);
});

/// Create account: sends the details before the email code. Preview builds send nothing.
final startSignupProvider = Provider<Future<void> Function(String email, ProfileSubmission details)>(
  (ref) => AppConfig.previewMode
      ? (_, _) => Future<void>.delayed(const Duration(milliseconds: 300))
      : (email, details) => ref.read(apiClientProvider).startSignup(email, details),
);

/// Account → Delete account. Preview builds delete nothing.
final deleteAccountProvider = Provider<Future<void> Function()>(
  (ref) => AppConfig.previewMode
      ? () => Future<void>.delayed(const Duration(milliseconds: 300))
      : () => ref.read(apiClientProvider).deleteAccount(),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => AppConfig.previewMode ? PreviewProfileRepository() : ApiProfileRepository(ref.watch(apiClientProvider)),
);

final consultRepositoryProvider = Provider<ConsultRepository>(
  (ref) => AppConfig.previewMode ? PreviewConsultRepository() : ApiConsultRepository(ref.watch(apiClientProvider)),
);

final consultationRepositoryProvider = Provider<ConsultationRepository>(
  (ref) =>
      AppConfig.previewMode ? PreviewConsultationRepository() : ApiConsultationRepository(ref.watch(apiClientProvider)),
);

final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => AppConfig.previewMode ? PreviewHistoryRepository() : ApiHistoryRepository(ref.watch(apiClientProvider)),
);

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AppConfig.previewMode ? PreviewAdminRepository() : ApiAdminRepository(ref.watch(apiClientProvider)),
);

/// The signed-in clinician's profile and verified level. Re-read with `ref.invalidate(meProvider)`.
final meProvider = FutureProvider.autoDispose<Me>((ref) => ref.watch(profileRepositoryProvider).me());

// --- plans, payments and the own Anthropic key ------------------------------------------------

final billingRepositoryProvider = Provider<BillingRepository>(
  (ref) => AppConfig.previewMode ? PreviewBillingRepository() : ApiBillingRepository(ref.watch(apiClientProvider)),
);

final paymentGatewayProvider = Provider<PaymentGateway>(
  (ref) => AppConfig.previewMode ? const UnsupportedPaymentGateway() : RazorpayGateway(),
);

/// Credits, plans, own-key status and notices. Re-read after a report or a purchase.
final billingStatusProvider = FutureProvider.autoDispose<BillingStatus>(
  (ref) => ref.watch(billingRepositoryProvider).status(),
);

/// The plans on sale, straight from the admin's pricing (never hardcoded in the app).
final billingPlansProvider = FutureProvider.autoDispose<BillingPlans>(
  (ref) => ref.watch(billingRepositoryProvider).plans(),
);

/// The clinician chose to write reports with their own Anthropic key. Session only: it is asked
/// again after the app restarts, so nobody pays Anthropic without knowing it.
class OwnKeyChoice extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final useOwnKeyProvider = NotifierProvider<OwnKeyChoice, bool>(OwnKeyChoice.new);

// --- calendar and online booking ----------------------------------------------------------------

final calendarRepositoryProvider = Provider<CalendarRepository>(
  (ref) => AppConfig.previewMode ? PreviewCalendarRepository() : ApiCalendarRepository(ref.watch(apiClientProvider)),
);

/// Settings, booking link, hours, time off and counts. Re-read after any change.
/// No automatic retries. Riverpod's default retries a failed request up to 10 times over about 40 seconds
/// and shows "loading" all that time, even when the server has answered (a plan that doesn't include
/// something, an account still being checked). Screens show the answer at once and offer their own Retry.
Duration? noAutomaticRetry(int retryCount, Object error) => null;

/// The Calendar tab's data. The plan is decided from `/v1/me` (read at sign-in and app start), so an
/// account without appointments is told at once, with no calendar request. It is kept for the signed-in
/// account (signing out re-reads `meProvider`, which resets it) and loaded in the background when the
/// home screen opens, so the tab shows at once; opening the tab refreshes it behind the scenes.
final calendarHomeProvider = FutureProvider.autoDispose<CalendarHome>((ref) async {
  final me = await ref.watch(meProvider.future);
  if (!me.has('appointments')) {
    throw const PlanRequired(feature: 'appointments', message: 'Appointments are in Practice, BYOK Scale and Scale.');
  }
  ref.keepAlive();
  return ref.watch(calendarRepositoryProvider).home();
});

// --- dropped connections ---------------------------------------------------------------------

/// How long to keep looking for a reply after the connection drops mid-request, and how often.
/// The server allows a reply up to 5 minutes, so 6 minutes covers it. Tests shorten this.
final consultRecoveryProvider = Provider<({Duration within, Duration every})>(
  (ref) => (within: const Duration(minutes: 6), every: const Duration(seconds: 5)),
);

// --- Education ----------------------------------------------------------------------------------

final educationRepositoryProvider = Provider<EducationRepository>(
  (ref) => AppConfig.previewMode ? PreviewEducationRepository() : ApiEducationRepository(ref.watch(apiClientProvider)),
);

/// The pages with fresh signed links. Re-read whenever the Education tab is opened.
final educationPagesProvider = FutureProvider.autoDispose<EducationCatalog>(
  (ref) => ref.watch(educationRepositoryProvider).pages(),
);
