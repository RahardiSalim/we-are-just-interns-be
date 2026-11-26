# mobile

Flutter app, Android only, on the consumer's phone. It records the ride (after consent), transcribes and classifies on the phone, shows kind warnings, sends high flags at once, and after a high or SOS ride uploads the full recording with markers. SOS / "I feel unsafe" are always available.

Follow the root [CLAUDE.md](../CLAUDE.md) rules. How the app works today, step by step: [README.md](README.md); keep it in sync when you change the engine, screens or payloads. The design is in [contracts/ARCHITECTURE.md](../contracts/ARCHITECTURE.md), section "On-device listening": read it before touching recording, models or storage.

- Stack: Flutter (Dart), firebase_auth, cloud_firestore (reads only), firebase_messaging, `sherpa_onnx` (Silero VAD + Whisper), ONNX Runtime (IndoBERT).
- Layout: `lib/features/trip/`, `lib/features/safety/` (warning, "Are you OK?", report), `lib/services/` (API client, auth, listener, encrypted store), `lib/models/` (Dart models generated from `contracts/`).
- Recording starts only when the consumer said yes and the driver has Safe Ride on, and stops at End ride: 16 kHz mono, AAC `.m4a` (WAV on web). For background recording later, use an Android foreground service with `foregroundServiceType="microphone"`.
- After End ride: upload the full recording with its markers only if the ride had a `high` or `sos` marker; otherwise `discard()` it. Never offer playback or export in the UI. If audio ever stays on the phone, encrypt it (AES-GCM, Android Keystore key).
- No location: never request location permission or send GPS / route. A trip is the GoJek order ID (`POST /trips` with `orderId`).
- Never gate SOS / "I feel unsafe" on the model. The app is the consumer's; there is no driver mode.
- All writes go to FastAPI. Audio uploads go to the signed URL from the API, using the returned `uploadMethod` (PUT in the cloud, POST on the emulator), then call the matching `/finalize` or `/done`.
- Config: `google-services.json` (not committed), `--dart-define=API_URL=...`, `DEMO_MODE`.
- Flutter 3.50+: Material widgets come from `package:material_ui/material_ui.dart`, not `package:flutter/material.dart`.
- Built: anonymous sign-in (no login screen), Start ride with the consumer's consent prompt (the driver's consent is their Safe Ride setting), microphone recording of the whole ride (`lib/services/recorder.dart`), the decision engine, kind warnings, high flags sent at once with "Are you okay?", SOS / "I feel unsafe", and after a high or SOS ride the full recording uploaded with markers (otherwise deleted).
- Temporary: speech input is `lib/services/mock_listener.dart` (a scripted conversation); the classifier is `KeywordClassifier`. Swap in sherpa_onnx (VAD + Whisper) and IndoBERT behind the same interfaces.
- Not built yet: background recording (foreground service), encryption on the phone, FCM.
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
