# mobile

Flutter app, Android only, for riders and drivers. Both phones listen for the whole trip, transcribe and classify on the phone, show warnings, send automatic reports at "high", and keep encrypted audio for 7 days. SOS / "I feel unsafe" are always available.

Follow the root [CLAUDE.md](../CLAUDE.md) rules. The design is in [contracts/ARCHITECTURE.md](../contracts/ARCHITECTURE.md), section "On-device listening": read it before touching recording, models or storage.

- Stack: Flutter (Dart), firebase_auth, cloud_firestore (reads only), firebase_messaging, `sherpa_onnx` (Silero VAD + Whisper), ONNX Runtime (IndoBERT).
- Layout: `lib/features/trip/`, `lib/features/safety/` (warning, "Are you OK?", report), `lib/services/` (API client, auth, listener, encrypted store), `lib/models/` (Dart models generated from `contracts/`).
- Listening runs in an Android foreground service with `foregroundServiceType="microphone"`: 16 kHz mono in, Opus to disk. It starts only after both consents and stops at trip end.
- Storage: AES-GCM with an Android Keystore key. Never offer playback or export in the UI. Delete everything older than 7 days on every app start and trip end.
- No location: never request location permission or send GPS / route. A trip is the GoJek order ID (`POST /trips` with `orderId`).
- Never gate SOS / "I feel unsafe" on the model, and never block the driver's screen while riding (GoRide): the driver's "Are you OK?" must not need an answer.
- All writes go to FastAPI. Audio uploads go to the signed URL from the API, using the returned `uploadMethod` (PUT in the cloud, POST on the emulator), then call the matching `/finalize` or `/done`.
- Config: `google-services.json` (not committed), `--dart-define=API_URL=...`, `DEMO_MODE`.
- Flutter 3.50+: Material widgets come from `package:material_ui/material_ui.dart`, not `package:flutter/material.dart`.
- Built: login (Firebase Auth), trip by order ID, consent, the decision engine (`lib/engine/safety_engine.dart`: 30 s window, warning with 10-min cooldown, one automatic report per trip), warning banner, "Are you OK?" (dialog, or a banner for a GoRide driver), SOS / "I feel unsafe", answering backend check-ins (Firestore listener).
- Mocked: speech input is `lib/services/mock_listener.dart` (a scripted conversation); the classifier is `KeywordClassifier`. Swap in sherpa_onnx (VAD + Whisper) and IndoBERT behind the same interfaces.
- Not built yet: the microphone foreground service, encrypted 7-day storage and clip upload, FCM, audio requests.
- Firebase points at the local emulators (`USE_EMULATORS`, default true; `EMULATOR_HOST` defaults to 10.0.2.2 on Android, 127.0.0.1 on web).

Commands (from `mobile/`):

| Task | Command |
|---|---|
| Install | `flutter pub get` |
| Check | `flutter analyze` and `flutter test` (engine + screen tests, no backend needed) |
| Run on phone/emulator | `flutter run --dart-define=API_URL=http://10.0.2.2:8000` (emulator) or your tunnel URL |
| Quick UI preview, no phone | `flutter run -d chrome` with the emulators and backend running (web is for previews only; the product is Android). Sign in as `rider1@gosafe.test` |
| APK | `flutter build apk --dart-define=API_URL=https://...` (needs the Android SDK) |
