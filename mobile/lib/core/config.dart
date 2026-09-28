/// Build-time switches.
///
/// `PREVIEW_MODE` stays on until the app is wired to the backend: screens use
/// the sample content in `core/demo/preview_data.dart` and nothing is sent
/// anywhere. Build with `--dart-define=PREVIEW_MODE=false` once the API client lands.
abstract final class AppConfig {
  static const previewMode = bool.fromEnvironment('PREVIEW_MODE', defaultValue: true);

  /// Mirrors `ConsultIn.text` limits in `app/main.py`.
  static const minCaseLength = 3;
  static const maxCaseLength = 12000;

  /// Mirrors `DAILY_TURN_LIMIT` in `.env.example`.
  static const dailyConsultLimit = 40;
}
