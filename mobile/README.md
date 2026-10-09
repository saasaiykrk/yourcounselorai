# Your Counselor: Flutter app (Android and iPhone)

The phone app for Your Counselor. It signs clinicians in, cleans case text on the phone, sends it to the Your Counselor backend, and shows the safety-checked reply.

## How it's built

```
Screens (lib/features/…)          what the clinician sees and taps
   │  read and watch
State (Riverpod)                  consult_controller.dart: idle → sending → reply or error
   │  call
Repositories (core/repositories)  one function per action: send consult, report, profile
   │  use
Services                          api/api_client.dart (backend) · auth/auth_service.dart (sign-in)
                                  deid/cleaner.dart (on-phone de-identification)
```

| Folder | What it holds |
|---|---|
| `lib/core/deid/cleaner.dart` | **Safety file.** Dart port of `app/deid.py`. Changes need the `clinician-reviewed` label |
| `lib/core/api/` | Backend client, JSON models, and every error the server can return |
| `lib/core/auth/` | Email-code sign-in (Supabase), with the session in encrypted phone storage |
| `lib/core/providers.dart` | Which real or preview implementation each mode uses |
| `lib/core/security/` | Screenshot blocking on case screens (Android) and app-switcher blur (iPhone) |
| `lib/core/content/safety_content.dart` | Disclaimer, crisis numbers, modes, report categories, all checked against the backend by tests |
| `lib/features/` | Screens: onboarding, consult (check panel, drafting, reply, report), safety and error states, account |
| `tool/deid_parity.py` | Regenerates `test/data/deid_parity.json` from the Python cleaner |

## Three ways to run it

| Mode | Command | What happens |
|---|---|---|
| **Preview** (default) | `flutter run` | Sample data; nothing leaves the phone. For design review. Account → *Design preview* lists every screen. Type "wants to end it" in a case to see the risk screen. |
| **Dev** | see below | Real backend on your computer in dev mode (fake AI, no database, no keys). Any email and any 6 digits sign in. |
| **Live** | see below | Real sign-in and real backend. Needs your Supabase project and a deployed backend. |

**Dev mode:**
```bash
# terminal 1, repository root
pip install -r requirements.txt
DEV_MODE=1 uvicorn app.main:app --port 8000

# terminal 2, mobile/
flutter run --dart-define=APP_MODE=dev --dart-define=BACKEND_URL=http://10.0.2.2:8000   # Android emulator
flutter run --dart-define=APP_MODE=dev --dart-define=BACKEND_URL=http://localhost:8000  # iPhone simulator or Chrome
```
Plain `http` is allowed only to your own computer, and only in debug builds.

**Live mode:**
```bash
flutter run --release --dart-define-from-file=config/live.json
```
No Flutter on your computer? Start **Actions → ci → Run workflow** (manual; the app isn't built on pull requests) and, when it finishes, download **yourcounselor-live-android** from *Artifacts*, unzip it and install on the phone (allow "install unknown apps" when asked):
- `app-arm64-v8a-release.apk` for almost every phone from the last ~8 years;
- `app-armeabi-v7a-release.apk` only if that one says "problem parsing the package" on an old 32-bit phone.

Needs Android 7.0 or newer. These test builds are signed with the debug key; the Play Store build gets its own upload key.

`config/live.json` holds the Cloud Run backend address, the Supabase project address and its *publishable* key. Both are public by design, so they can live in git; no secret ever goes in the app. Admin tasks (first admin, approving clinicians) are in `db/admin.sql`. The Supabase project must:
- use **asymmetric JWT signing keys**, because the backend checks tokens with JWKS;
- have an email template that includes `{{ .Token }}`, so clinicians get a 6-digit code rather than a link;
- use **custom SMTP** for beta volume.

## Checks

```bash
flutter analyze
flutter test                                    # 153 tests
python3 tool/deid_parity.py --check             # run from the repo root as: python3 mobile/tool/deid_parity.py --check
YC_BACKEND_URL=http://127.0.0.1:8000 flutter test test/backend_integration_test.dart   # with the dev backend running
```

What the tests cover:
- **Cleaner:** every shared vector in `fixtures/deid_vectors.json`, plus an exact match with the Python cleaner on 49 cases.
- **Safety wording:** crisis numbers against the crisis register, the disclaimer against the inspector, and categories and modes against the API.
- **Every screen:** drawn on a small and a standard phone with no overflow, and the email-code box readable by screen readers.
- **Every consult outcome:** delivered, safety gate, held back, identifier found, daily limit, offline, timeout, signed out, not verified.
- **Privacy rules:**
  - the phone number and names never reach the request;
  - the draft is wiped after a delivered reply but kept after a failure;
  - follow-ups continue the same conversation.
- **Against the real dev backend:** the integration tests.

The app is built and released by its owner; CI/CD only deploys the backend. On every pull request GitHub runs just the quick cleaner parity check (`tool/deid_parity.py --check`). Analysis, tests and the Android and iPhone builds run only when you start them by hand (Actions → ci → Run workflow), so run `flutter analyze` and `flutter test` locally before releasing.

## Privacy and safety in the app

- **No keys in the app.** The sign-in session is kept in the Keychain (iPhone) or Keystore-backed storage (Android).
- **Case text and replies live in memory only.**
  - They are never written to disk.
  - The draft is cleared once a reply is delivered.
  - Everything is wiped on sign-out.
- **Guided consultation** (Consult → Guided): the case, then the **Case Snapshot** form (CR-001), then at most
  4 case-specific questions, then the fixed Consultation Report.
  - The case is checked first: what it already says is pre-filled (✓); a few fields are asked for every case
    and the rest only when this case needs them (others fold into "More details (optional)").
  - Every asked field needs a value or a status (Not known / Not yet asked / N/A), or "Skip remaining".
  - "Risk present" shows the crisis numbers straight away. The report's snapshot table is drawn by the app
    from the form: answered fields only, plus one "Ask in the next session" line. Field list and wording:
    `shared/snapshot_fields.json`, `shared/ui_copy.json` (no app update needed to change them).
  - After the report, the pencil icon on the report screen reopens the snapshot; saving offers "Update report".
  - Every answer is cleaned on the phone first (the check panel opens only when something
  is found); the server cleans it again and keeps the compact, de-identified state so a consultation can be
  continued later. Risk in an answer pauses the questions and shows the crisis numbers. Shown only when the
  server has `CONSULTATION_ENABLED=1` (see `docs/DEPLOY.md`).
- **History** (past consults) is read from the server each time the tab opens and is never stored on the phone.
  - Clinicians see only their own consults. Labels go through the same identifier check as case text.
  - "Delete" hides a consult from History; the de-identified copy stays on the server for safety review
    until the 12-month retention ends.
  - Admins can open any clinician's consults from the Admin area; every view is recorded in `admin_audit`.
  - Needs `db/migrations/002_consult_history.sql` run once in Supabase.
- **Plans & credits** (Account → Plans & credits, or the credits line on the Consult screen). Shown only when an
  admin has switched pricing on; until then every report is free.
  - Plans, prices and features come from the server (/admin → Pricing Plans); nothing is hardcoded in the app.
  - Payment: the server creates and prices the order → Razorpay checkout (`razorpay_flutter`) → the server checks
    the signature **and** asks Razorpay before any credit is added. The app never treats the checkout's
    "success" as proof. The app holds only Razorpay's public key id, sent by the server with each order.
  - No credit for a report → "No report credits left" with **See plans**; nothing is generated or charged.
  - **Use My Anthropic API Key:** typed once on a screenshot-blocked screen, sent to the server (checked with
    Anthropic, stored encrypted), never stored on the phone, and only its last 4 characters are shown again.
    The clinician switches it on for their reports; if it fails, the app says why and offers "Write without my
    key" — it never switches to the platform's key by itself.
  - Payments run on Android and iPhone only (not in the browser preview).
- **Keyboard learning and suggestions are off** in case fields.
- **Send is locked** until the clinician ticks "no identifiers". The server cleans the text again anyway.
- **Screen protection:** Android blocks screenshots and recording on case screens; iPhone blurs the app in the app switcher (iOS can't block screenshots).
- **Android backups are off**, and nothing is sent to crash or analytics tools.

## Before the beta
1. **Live test on real phones:** the Android and iPhone native code (screen protection) has not yet run on a device.
2. **Supabase set-up** as above, and the backend deployed (plan Step 8).
3. **Legal review** of the Clinician Terms and Data Processing Agreement. The app shows beta-draft summaries
   from `lib/core/content/legal_content.dart`; replace them with the reviewed text and bump `consentVersion`
   in `lib/core/config.dart` so everyone accepts the new version.
4. **Psychologist review** of `lib/core/deid/cleaner.dart` (a safety file), and the open cleaner and inspector findings in the pull request.
