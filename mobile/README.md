# CareLoop — Flutter Android app

A native Flutter client for the exact same CareLoop backend (`../server`) that the web app talks
to — same REST API, same pipeline, same consent state machine. This is a second frontend on top
of unchanged shared business logic, not a reimplementation of the product.

## Screens (parity with the web app)

- Login (role-agnostic, same demo accounts)
- Family dashboard + add dependent
- Member profile: Overview (summary card), Trends (fl_chart line graphs, range-type-aware
  shading), Year-over-year, Upload (photo/PDF picker + golden-fixture demo buttons), Review queue,
  Documents, Consent & Privacy
- Appointments: booking + consent approve/deny
- Provider console: appointment list with live polling
- Appointment workspace: check-in → consent (in-app/OTP) → unlock → consult → e-prescription →
  complete
- Admin dictionary-governance review queue

## Pointing it at a backend

The app defaults to `http://10.0.2.2:4000/api` — the Android emulator's special alias for your
host machine's `localhost`, so it talks to `npm run dev:server` (see `../server`) out of the box
**when run on an emulator**. For a physical device or a real deployment, override at build time:

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://your-deployed-server.example.com/api
```

or, for a physical device on the same Wi-Fi as your dev machine during testing:

```bash
flutter build apk --debug --dart-define=API_BASE_URL=http://<your-lan-ip>:4000/api
```

## Building

```bash
flutter pub get
flutter analyze          # 0 issues
flutter build apk --debug     # -> build/app/outputs/flutter-apk/app-debug.apk
flutter build apk --release   # -> build/app/outputs/flutter-apk/app-release.apk (signed with the
                               #    template's debug keystore — fine for sideloading/testing, NOT
                               #    for Play Store; swap in a real signing config first)
```

Requires Flutter 3.x, a JDK, and the Android SDK (compileSdk/targetSdk 36 — bumped explicitly in
`android/app/build.gradle.kts` because `file_picker`'s transitive `flutter_plugin_android_lifecycle`
dependency requires it; Flutter's own template default was 34).

## Notes

- Auth token is stored via `shared_preferences` (unencrypted local storage) — fine for this demo,
  swap for `flutter_secure_storage` before anything real.
- `image_picker`/`file_picker` request runtime permissions on first use; no extra manifest setup
  was needed beyond what `flutter create` scaffolds plus the SDK bump above.
- Same simplifications as the web app apply here (see `../README.md`) since both talk to the same
  backend — payer module not built, unit-conversion table is small, tier-3 matching without an
  API key is a local heuristic, etc.
