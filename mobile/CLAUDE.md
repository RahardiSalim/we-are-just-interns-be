# mobile

Flutter app, Android only, on the rider's and the driver's phone (a Rider / Driver switch on the home screen for the demo; in production they're two apps). It records the ride (after consent), transcribes and classifies on the phone, shows kind warnings, sends high flags at once, and after a high or SOS ride uploads the full recording with markers. SOS / "I feel unsafe" are always available.

Follow the root [CLAUDE.md](../CLAUDE.md) rules. How the app works today, step by step: [README.md](README.md); keep it in sync when you change the engine, screens or payloads. The design is in [contracts/ARCHITECTURE.md](../contracts/ARCHITECTURE.md), section "On-device listening": read it before touching recording, models or storage.

- Stack: Flutter (Dart), firebase_auth, cloud_firestore (reads only), firebase_messaging, `sherpa_onnx` (Silero VAD + Whisper), ONNX Runtime (IndoBERT).
- Layout: `lib/features/trip/`, `lib/features/safety/` (warning, "Are you OK?", report), `lib/services/` (API client, auth, listener, encrypted store), `lib/models/` (Dart models generated from `contracts/`).
- Recording starts only when the consumer said yes and the driver has Safe Ride on, and stops at End ride: 16 kHz mono, AAC `.m4a` (WAV on web). It keeps going with the screen locked through `RideService`, a foreground service with `foregroundServiceType="microphone"` (Kotlin, `android/app/src/main/kotlin/`), reached from Dart via `lib/services/ride.dart`. minSdk 26.
- Every recorded ride is stored on the phone for 7 days (`RideStore`): 30-second encrypted audio pieces (10-second when Live) plus `RideMeta` (markers, transcript), saved as the ride goes. What leaves the phone follows the ride's `Share` level: a report or high flag uploads at End ride, an SOS streams Live; retried every minute until sent. Never offer playback or export in the UI. Everything stored on the phone is AES-GCM encrypted with an Android Keystore key.
- No location: never request location permission or send GPS / route. A trip is the GoJek order ID (`POST /trips` with `orderId`).
- Never gate SOS / Report on the model. What leaves the phone follows `Share` (local → at end → live); see the README "What leaves the phone, and when".
- All writes go to FastAPI. Audio uploads go to the signed URL from the API, using the returned `uploadMethod` (PUT in the cloud, POST on the emulator), then call the matching `/finalize` or `/done`.
- Config: `google-services.json` (not committed), `--dart-define=API_URL=...`, `DEMO_MODE`.
- Flutter 3.50+: Material widgets come from `package:material_ui/material_ui.dart`, not `package:flutter/material.dart`.
- Built: anonymous sign-in (no login screen), Start ride with the consumer's consent prompt (the driver's consent is their Safe Ride setting), microphone recording of the whole ride (`lib/services/recorder.dart`), the decision engine, kind warnings, high flags sent at once with "Are you okay?", SOS / "I feel unsafe", and after a high or SOS ride the full recording uploaded with markers and transcript (otherwise kept on the phone 7 days). SOS with no signal offers 112 and retries until sent.
- Temporary: speech input is `lib/services/mock_listener.dart` (a scripted conversation); the classifier is `KeywordClassifier`. Swap in sherpa_onnx (VAD + Whisper) and IndoBERT behind the same interfaces.
- Built natively, no Firebase: background recording, the alarm on a high flag (`TripScreen.alert`, loud), lock-screen "Are you okay?" for check-ins, and AES-GCM encryption of the recording with an Android Keystore key (`Vault.kt`).
- The safe phrase is each user's own (home screen, stored encrypted via `RideStore.setSafePhrase`), matched fuzzily by `SafePhrase`.
- Not built yet: FCM (push when the app is fully closed).
- Style: only the tokens in `lib/theme.dart` (from [contracts/DESIGN.md](../contracts/DESIGN.md)); no raw colours or sizes in feature code. Safety colours mean the same as on the dashboard.
- All user-facing wording lives in `SafetyText` (`lib/features/safety/are_you_ok.dart`): short, caring, never alarming. Never show messages as bottom snackbars: nothing may cover the SOS button.
- Firebase points at the local emulators (`USE_EMULATORS`, default true; `EMULATOR_HOST` defaults to 10.0.2.2 on Android, 127.0.0.1 on web).

Commands (from `mobile/`):

| Task | Command |
|---|---|
| Install | `flutter pub get` |
| Check | `flutter analyze` and `flutter test` (engine + screen tests, no backend needed) |
| Run on phone/emulator | `flutter run --dart-define=API_URL=http://10.0.2.2:8000` (emulator) or your tunnel URL |
| Quick UI preview, no phone | `flutter run -d chrome` with the emulators and backend running (web is for previews only; the product is Android). No login needed |
| APK | `flutter build apk --dart-define=API_URL=https://...` (needs the Android SDK) |
