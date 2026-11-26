# mobile

Flutter app, Android only, for riders and drivers. Consent toggle, "recording on" banner, demo trip, SOS / "I feel unsafe", clip upload via signed URL, and replying to FCM check-ins.

Follow the root [CLAUDE.md](../CLAUDE.md) rules and [contracts/ARCHITECTURE.md](../contracts/ARCHITECTURE.md).

- Stack: Flutter (Dart), firebase_auth, cloud_firestore (reads only), firebase_messaging. Later: sherpa_onnx for on-device STT.
- Layout: `lib/features/trip/`, `lib/features/safety/`, `lib/services/` (API client, auth, recorder), `lib/models/` (Dart models generated from `contracts/`).
- Background recording uses an Android foreground service with `foregroundServiceType="microphone"`. Record 16 kHz mono.
- All writes go to FastAPI. Audio uploads go straight to the signed URL from `POST /incidents`, then call `/finalize`.
- Config: `google-services.json` (not committed), `--dart-define=API_URL=...`, `DEMO_MODE`.
