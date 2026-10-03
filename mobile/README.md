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
No Flutter on your computer? Every CI run builds this live app for Android: open the run under **Actions → ci**, download **yourcounselor-live-android** from *Artifacts*, unzip it and install on the phone (allow "install unknown apps" when asked):
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

GitHub runs analyze, tests, the parity check and an Android build on every pull request. The iPhone build runs when you start the workflow by hand (Actions → ci → Run workflow).

## Privacy and safety in the app

- **No keys in the app.** The sign-in session is kept in the Keychain (iPhone) or Keystore-backed storage (Android).
- **Case text and replies live in memory only.**
  - They are never written to disk.
  - The draft is cleared once a reply is delivered.
  - Everything is wiped on sign-out.
- **History** (past consults) is read from the server each time the tab opens and is never stored on the phone.
  - Clinicians see only their own consults. Labels go through the same identifier check as case text.
  - "Delete" hides a consult from History; the de-identified copy stays on the server for safety review
    until the 12-month retention ends.
  - Admins can open any clinician's consults from the Admin area; every view is recorded in `admin_audit`.
  - Needs `db/migrations/002_consult_history.sql` run once in Supabase.
- **Keyboard learning and suggestions are off** in case fields.
- **Send is locked** until the clinician ticks "no identifiers". The server cleans the text again anyway.
- **Screen protection:** Android blocks screenshots and recording on case screens; iPhone blurs the app in the app switcher (iOS can't block screenshots).
- **Android backups are off**, and nothing is sent to crash or analytics tools.

## Before the beta
1. **Live test on real phones:** the Android and iPhone native code (screen protection) has not yet run on a device.
2. **Supabase set-up** as above, and the backend deployed (plan Step 8).
3. **Psychologist review** of `lib/core/deid/cleaner.dart` (a safety file), and the open cleaner and inspector findings in the pull request.
