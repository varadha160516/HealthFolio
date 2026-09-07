# CareLoop

An implementation of the CareLoop Master PRD: family health records, an AI-driven lab-report
parsing pipeline, trend graphs & year-over-year comparison, and a doctor check-in/consent/consult
workflow. Built as a web app (React + Express + SQLite), packaged for Android via Capacitor per
the PRD's own recommended path (Section 12.1), **and** as a separate native Flutter Android app
(`mobile/`) — both frontends talk to the same unmodified backend/API.

## Status: what's real vs. what's a documented stand-in

| Area | Status |
|---|---|
| Family/member data model, auth, roles (Section 2, 3.1) | Fully implemented |
| Parsing pipeline — all 11 stages, 3-tier matching, range resolution, confidence routing (Section 4) | Fully implemented |
| Lab-report vision extraction (Section 4.3) | **Swappable adapter.** Calls the real Claude API when `ANTHROPIC_API_KEY` is set on the server; otherwise runs a deterministic mock adapter (two golden fixtures + a randomized-but-plausible generator) so the full pipeline is demonstrable without a key. No other code changes needed to go live — see "Turning on real extraction" below. |
| Canonical parameter dictionary (Section 5) | Loaded verbatim from `CareLoop_Parameter_Dictionary.json`, versioned |
| Trend graphs & YoY comparison (Section 6) | Fully implemented, including `range_type`-aware flagging/shading and qualitative status timelines |
| Doctor console state machine, consent (in-app + OTP), audit log (Section 7-8) | Fully implemented and covered by automated tests |
| Payer module (Section 9) | **Not built** — explicitly deprioritized per the PRD's own build order (12.2) until 1-4 are solid |
| Real-time consent channel | Implemented as short-interval polling (2-4s), which the PRD itself names as one half of "push notification + live status poll" (Section 8.1). No push-notification provider is wired up. |
| Member-uploaded prescription photos (Section 3.4) | OCR'd via the same swappable adapter and stored directly; no separate review gate (the PRD only fully specs the provider-issued path in detail) |
| Non-lab-report document types (radiology, discharge summary, vaccination, insurance) | Stored as-is (source of truth, Section 3.2 #1); no field-level extraction pipeline — only lab reports and prescriptions have one, matching the PRD's stated scope (Section 1) |
| Auth | Simple email/password + in-memory bearer sessions. Fine for local/demo use; swap for real JWT/OAuth + a persistent session store before any real deployment. |
| File storage | Local disk (`server/uploads/`), served straight from the API. Swap for signed URLs against real object storage (S3/GCS) before production (Section 11). |

## Repo layout

```
server/   Express + TypeScript API, SQLite (via Node's built-in node:sqlite), the parsing pipeline
web/      React + TypeScript member app, provider console, admin queue (Vite)
web/android/   Capacitor-generated native Android project (web app wrapped for Android)
mobile/   Native Flutter Android app — separate frontend, same backend API (see mobile/README.md)
PRD.md    The source PRD (copied in for reference)
server/src/dictionary/parameter_dictionary.json   The seed canonical dictionary
```

## Running it locally

Requires Node 22+ (uses the built-in `node:sqlite` module — no native build tools needed, which
matters if you don't have Python/a C++ toolchain available for something like better-sqlite3).

```bash
npm install                  # installs both workspaces
npm run dev:server           # http://localhost:4000 — seeds a demo family on first run
npm run dev:web              # http://localhost:5173 — proxies /api to the server
```

Demo logins (password `password123` for all): `priya@example.com` (family coordinator),
`dr.rao@example.com` (doctor), `frontdesk@example.com` (clinic front desk),
`admin@careloop.app` (platform admin, dictionary-governance queue).

On the member Upload tab, "Load Tata 1mg-style CBC report" / "Load PharmEasy/Thyrocare trends
report" replay the two golden fixtures (Section 4.8) through the real pipeline — no need for an
actual lab report photo to see matching, range resolution, and confidence routing work end to end.

### Running the tests

```bash
npm run test:server
```

Uses Node's built-in test runner (`node:test`) against an in-memory database. Covers: the two
golden fixtures (layout-agnostic matching, printed-range preservation, interpretive-rule no-flag
rule, tier-4 new-candidate routing), tier-2/tier-3 disambiguation, and the full consent state
machine (access denied at every state except `consent_granted`/`in_consultation`, revoked
immediately on completion — Section 12.4's explicit testing requirement).

### Turning on real extraction

Set `ANTHROPIC_API_KEY` (and optionally `CARELOOP_EXTRACTION_MODEL`, `CARELOOP_MATCH_MODEL`) on
the **server** process before starting it. That's the only step — `server/src/pipeline/extract.ts`
picks the real adapter automatically and every downstream stage is unchanged. Budget for real API
cost per uploaded document at that point.

## Building the Android app

Two independent Android builds exist, both producing real, verified `.apk` files (a full
JDK 17 + Android SDK 36 + Gradle toolchain was installed to build and confirm both — this section
reflects what's actually been done, not just what the commands would do).

### Option A — Capacitor (the web app, wrapped)

```bash
cd web
echo "VITE_API_BASE_URL=https://your-deployed-server.example.com/api" > .env.production
npm run build
npx cap sync android
cd android
./gradlew assembleDebug      # -> app/build/outputs/apk/debug/app-debug.apk
```

### Option B — Flutter (a separate native client, see `mobile/README.md`)

```bash
cd mobile
flutter pub get
flutter build apk --release --dart-define=API_BASE_URL=https://your-deployed-server.example.com/api
# -> build/app/outputs/flutter-apk/app-release.apk
```

Both were built and installed-artifact-verified (`aapt dump badging`) in this environment. Two
real bugs were caught and fixed doing this — worth knowing if you extend either: the Flutter
release build initially lacked `android.permission.INTERNET` (Flutter's debug/profile builds get
it from a tooling-only manifest overlay that release builds don't share — declared explicitly in
`mobile/android/app/src/main/AndroidManifest.xml` now), and it also needed a network security
config permitting cleartext HTTP for local dev testing (`android/app/src/main/res/xml/network_security_config.xml`) since Android 9+ blocks plain HTTP by default and the whole
local-dev workflow depends on it.

A release/signed build additionally needs a real keystore for Play Store distribution; both
options currently sign release builds with their respective template's debug keystore, which is
fine for sideloading/testing but not for store submission — treat signing-key management as a
deployment concern separate from getting the build itself working (PRD 12.3).

**Toolchain installed on this machine** (so future builds don't need to re-download anything):
Temurin JDK 17 at `C:\devtools\jdk_extracted\jdk-17.0.20+8`, Android SDK at
`C:\devtools\android-sdk` (platforms 34/35/36, build-tools 28.0.3/35.0.0/36.0.0), Flutter 3.47.0
at `C:\devtools\flutter`. `JAVA_HOME`/`ANDROID_HOME` were set as persistent Windows user
environment variables, so a fresh terminal window should pick them up automatically; if a shell
doesn't see them, source `C:\devtools\env.sh`.

## Known simplifications worth knowing about before extending this

- **Unit conversion** (pipeline stage 6) only covers a handful of common conversions (glucose,
  cholesterol, creatinine, urea, g/L↔g/dL). Anything else with a unit mismatch is correctly routed
  to review rather than guessed, per spec — but the conversion table itself is small and should
  grow with real-world reports.
- **Tier-3 semantic matching** without an API key falls back to a local character-trigram
  heuristic (`server/src/pipeline/normalize.ts` / `match.ts`) as a stand-in for a real medical
  embedding model. It's deliberately conservative (tuned to avoid the "NLR vs Neutrophils" class of
  false positive) but it's not a substitute for the real thing — and per the PRD, tier-3 matches are
  never auto-accepted regardless, so the failure mode is "needs review," not "silently wrong."
  Setting `ANTHROPIC_API_KEY` swaps this for a real LLM judgment call automatically.
- **Multi-page grouping** (Section 3.3) treats one upload batch (all files selected together) as
  one logical document. Stitching together pages uploaded in *separate* actions that later turn
  out to share a Lab Visit ID isn't implemented.
- Sessions are in-memory (a server restart logs everyone out) and auth is intentionally minimal —
  this is a working demo of the product logic, not a hardened auth system.
