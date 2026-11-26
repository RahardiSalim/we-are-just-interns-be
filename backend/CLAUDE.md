# backend

FastAPI service on Cloud Run. Owns every write to Firestore and Storage, signs upload/read URLs, runs STT → IndoBERT → severity → check-in/escalation, and sends FCM pushes.

Follow the root [CLAUDE.md](../CLAUDE.md) rules and [contracts/ARCHITECTURE.md](../contracts/ARCHITECTURE.md).

- Stack: Python 3.12, FastAPI, firebase-admin, google-cloud-speech (Chirp 3), ONNX Runtime for IndoBERT (no full PyTorch in the image).
- Layout: `app/api/` routes, `app/services/` Firestore/Storage/FCM/STT/LLM, `app/ml/` classifier, `app/models/` Pydantic, `app/core/` config + auth; `scripts/seed.py`, `scripts/export_openapi.py`; `tests/`.
- Auth: verify the Firebase ID token on every route except `/health`; check the `role` claim.
- Config: env vars only (see ARCHITECTURE.md). `/dev/*` routes only when `ENABLE_DEV_ROUTES=true`.
- ML pieces (classifier, STT, LLM) are on hold; see "On hold" in ARCHITECTURE.md. Stand-ins: `services/classify.py` (keyword filter), `pipeline.transcribe` (returns nothing), `pipeline.summarize` (template). Don't add `app/ml/` until a model exists.
- Status changes live in `services/pipeline.py` and the API handlers, inside Firestore transactions where two callers can race (finalize, check-in reply vs timeout, open, decision).
- Tests sit at the HTTP API against the emulator; only token checks, push, and URL signing are faked (`tests/conftest.py`).

Commands (from `backend/`, needs `uv`):

| Task | Command |
|---|---|
| Install | `uv sync` |
| Test | `uv run pytest -q` runs the 6 offline tests; the rest skip without the emulators. Full run: from `firebase/`, `firebase emulators:exec --only auth,firestore "cd ../backend && uv run pytest -q"` (wipes emulator data; re-seed after) |
| Run | `uv run uvicorn app.main:app --reload` |
| Seed | `SEED_PASSWORD=... uv run python -m scripts.seed` (accounts are `<uid>@gosafe.test`) |
| Export contract | `uv run python -m scripts.export_openapi` (after any route change; commit `contracts/openapi.json`) |
| Deploy | push to `main`; `.github/workflows/backend.yml` tests then deploys to Cloud Run |

Against the emulators, set `FIREBASE_AUTH_EMULATOR_HOST=localhost:9099` and `FIRESTORE_EMULATOR_HOST=localhost:8080` (start them from `firebase/` with `firebase emulators:start`).
