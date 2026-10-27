/// Build-time settings, passed with `--dart-define` (never secrets: the app holds no keys).
///
/// | APP_MODE  | What it does                                                                  |
/// |-----------|-------------------------------------------------------------------------------|
/// | `preview` | Default. Sample data, nothing sent anywhere. For design review.               |
/// | `dev`     | Talks to a local backend started with `DEV_MODE=1` (fake model, no database), |
/// |           | signing in with the backend's dev token instead of Supabase.                  |
/// | `live`    | Supabase email sign-in + the real backend. Needs BACKEND_URL (https),         |
/// |           | SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (the public key, safe in the app).  |
library;

enum AppMode { preview, dev, live }

abstract final class AppConfig {
  static final AppMode mode = AppMode.values.byName(const String.fromEnvironment('APP_MODE', defaultValue: 'preview'));

  static bool get previewMode => mode == AppMode.preview;

  /// Android emulators reach the host computer at 10.0.2.2; iOS simulators and web use localhost.
  static const backendUrl = String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:8000');
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// `dev` mode only: the backend's DEV_TOKEN (dev-L1 / dev-L2 / dev-L3). Not a secret.
  static const devToken = String.fromEnvironment('DEV_TOKEN', defaultValue: 'dev-L2');

  /// The store reviewer's sign-in email (Google Play / App Store review). Not a secret: its fixed
  /// 6-digit code is set in Supabase (as the account's password) and given only in Play Console.
  /// No email is sent to it. Empty = no reviewer account.
  static String reviewEmail = const String.fromEnvironment('REVIEW_EMAIL'); // settable in tests

  static bool isReviewEmail(String email) =>
      reviewEmail.isNotEmpty && email.trim().toLowerCase() == reviewEmail.trim().toLowerCase();

  /// Mirrors `ConsultIn.text` limits in `app/main.py`.
  static const minCaseLength = 3;
  static const maxCaseLength = 12000;

  /// Mirrors `DAILY_TURN_LIMIT` in `.env.example`.
  static const dailyConsultLimit = 40;

  /// A Mode A reply can take 1–2 minutes (SPEC-week1 §3.1); the backend allows 300 s.
  static const consultTimeout = Duration(seconds: 300);

  /// Terms and consent version recorded at signup; the lawyer-reviewed text replaces it in Phase 4.
  // 2: names Google (Gemini), Razorpay and client bookings · 3: mobile number, offers and updates
  static const consentVersion = '2026-10-v3';

  /// Throws with a readable message when a live build is missing its settings.
  static void validate() {
    if (mode != AppMode.live) return;
    final missing = [
      if (!backendUrl.startsWith('https://')) 'BACKEND_URL (must be https)',
      if (supabaseUrl.isEmpty) 'SUPABASE_URL',
      if (supabasePublishableKey.isEmpty) 'SUPABASE_PUBLISHABLE_KEY',
    ];
    if (missing.isNotEmpty) {
      throw StateError('APP_MODE=live needs --dart-define values for: ${missing.join(', ')}');
    }
  }
}
