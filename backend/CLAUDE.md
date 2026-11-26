# backend

FastAPI service on Cloud Run. Owns every write to Firestore and Storage, signs upload/read URLs, runs STT → IndoBERT → severity → check-in/escalation, and sends FCM pushes.

Follow the root [CLAUDE.md](../CLAUDE.md) rules and [contracts/ARCHITECTURE.md](../contracts/ARCHITECTURE.md).

- Stack: Python 3.12, FastAPI, firebase-admin, google-cloud-speech (Chirp 3), ONNX Runtime for IndoBERT (no full PyTorch in the image).
- Layout: `app/api/` routes, `app/services/` Firestore/Storage/FCM/STT/LLM, `app/ml/` classifier, `app/models/` Pydantic, `app/core/` config + auth; `scripts/seed.py`, `scripts/export_openapi.py`; `tests/`.
- Auth: verify the Firebase ID token on every route except `/health`; check the `role` claim.
- Config: env vars only (see ARCHITECTURE.md). `/dev/*` routes only when `ENABLE_DEV_ROUTES=true`.
- Local: Firebase emulators + `uvicorn app.main:app --reload`. Tests use pytest against the emulators.
- After changing any route: run `scripts/export_openapi.py` and commit `contracts/openapi.json`.
