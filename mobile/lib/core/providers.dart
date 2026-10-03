/// Riverpod wiring: which implementation each part of the app uses in the
/// current [AppMode]. Tests override these providers with fakes.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'api/api_models.dart';
import 'auth/auth_service.dart';
import 'config.dart';
import 'repositories.dart';

final authServiceProvider = Provider<AuthService>(
  (ref) => AppConfig.mode == AppMode.live ? SupabaseAuthService() : DevAuthService(AppConfig.devToken),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final auth = ref.watch(authServiceProvider);
  return ApiClient(baseUrl: AppConfig.backendUrl, token: auth.accessToken, timeout: AppConfig.consultTimeout);
});

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => AppConfig.previewMode ? PreviewProfileRepository() : ApiProfileRepository(ref.watch(apiClientProvider)),
);

final consultRepositoryProvider = Provider<ConsultRepository>(
  (ref) => AppConfig.previewMode ? PreviewConsultRepository() : ApiConsultRepository(ref.watch(apiClientProvider)),
);

final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => AppConfig.previewMode ? PreviewHistoryRepository() : ApiHistoryRepository(ref.watch(apiClientProvider)),
);

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AppConfig.previewMode ? PreviewAdminRepository() : ApiAdminRepository(ref.watch(apiClientProvider)),
);

/// The signed-in clinician's profile and verified level. Re-read with `ref.invalidate(meProvider)`.
final meProvider = FutureProvider.autoDispose<Me>((ref) => ref.watch(profileRepositoryProvider).me());
