# Your Counselor: Flutter app (Android and iPhone)

The phone app for Your Counselor. This is the **design build**: every screen from the approved design board is built with the real brand, fonts and logo, but it uses sample content and is **not connected to the server yet**. A "Preview build" notice on the consult screen says so.

## What's in here

| Folder | What it holds |
|---|---|
| `lib/core/theme/` | Brand colours (`app_colors.dart`) and the app theme: fonts, buttons, fields |
| `lib/core/content/safety_content.dart` | Disclaimer, crisis numbers, consult modes, report categories, all mirrored from the backend |
| `lib/core/widgets/` | Shared pieces: logo, cards, status labels, crisis numbers card, step list |
| `lib/core/demo/preview_data.dart` | Sample case and reply used until the real cleaner and API are wired in |
| `lib/features/` | The screens: onboarding, consult (check panel, drafting, reply, report), safety and error states, account |
| `lib/router.dart` | Every screen's address (for example `/consult`, `/reply`) |
| `assets/` | Logo, app icon, and the Nunito fonts (bundled, never downloaded at runtime) |
| `test/` | Tests (see below) |

Tip: in the app, **Account → Design preview: all screens** jumps to any screen.

## Run it on your phone (first time)

1. Install **Flutter** by following flutter.dev → "Get started" for your computer (Windows or Mac).
2. **Android:** install **Android Studio**. On your phone, turn on *Developer options → USB debugging* and plug it in.
   **iPhone:** you need a Mac with **Xcode**; see the Flutter iOS setup page.
3. Download this project from GitHub, open a terminal in the `mobile` folder, and run:
   ```bash
   flutter pub get      # download the packages the app uses
   flutter devices      # your phone should appear in this list
   flutter run          # build and open the app on your phone
   ```
4. Anything wrong? Run `flutter doctor`; it lists what still needs setting up.

To look at it in a browser instead: `flutter run -d chrome`.

## Checks

```bash
flutter analyze   # code problems
flutter test      # all tests
```

The tests:
- draw every screen on a small (360×640) and a standard (390×844) phone, and fail if anything overflows;
- check the safety behaviours: Send stays locked until "no identifiers" is ticked, a report needs a category, and professional details need consent and a registration number;
- fail if the app's crisis numbers, disclaimer, report categories or consult modes ever drift from the backend and the crisis register (`skill/clinical-assist/references/crisis-resources.md`).

GitHub runs the same checks on every pull request (the `mobile` job in `.github/workflows/ci.yml`).

## App icon

The icons come from `assets/brand/app_icon.png`, with the mark on white because the iPhone App Store doesn't allow see-through icons. After changing the logo, run `dart run flutter_launcher_icons`.

## Already in place

- Case text is never saved on the phone, and keyboard learning and suggestions are off in case fields.
- Android backups are switched off (`allowBackup="false"`).
- No keys or secrets anywhere in the app.

## Still to come (from the build plan)

1. **The real cleaner:** a Dart port of `app/deid.py` that must pass every case in `fixtures/deid_vectors.json`. It's a safety file, so it needs the clinician-reviewed label.
2. **Sign-in and API client:** Supabase email code, then `/v1/profile`, `/v1/me`, `/v1/consult` and `/v1/incidents`, with a 300-second timeout.
3. **Screen protection:** block screenshots on case screens (Android `FLAG_SECURE`) and blur the app in the iPhone app switcher.
4. **Reply rendering:** show the server's markdown reply, including tables, in the reply screen.
