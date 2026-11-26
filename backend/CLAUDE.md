# backend

FastAPI service on Cloud Run. Owns every write to Firestore and Storage, signs upload/read URLs, takes the phone's transcript and label → severity → escalation (one case per ride; no check-ins), receives each phone's recording in pieces (live during an emergency), sends FCM pushes, and emails the reporter after an SOS and the rider and driver after a decision (`services/mailer.py`). Speech-to-text and the classifier run on the phones, not here.

Follow the root [CLAUDE.md](../CLAUDE.md) rules and [contracts/ARCHITECTURE.md](../contracts/ARCHITECTURE.md).

- Stack: Python 3.12, FastAPI, firebase-admin. No ML libraries: the models are edge AI on the phones.
- Layout: `app/api/` routes, `app/services/` Firestore/Storage/FCM/LLM, `app/core/` config + auth; `scripts/seed.py`, `scripts/export_openapi.py`; `tests/`.
- Auth: verify the Firebase ID token on every route except `/health`; check the `role` claim.
- Config: env vars only (see ARCHITECTURE.md). `/dev/*` routes only when `ENABLE_DEV_ROUTES=true`.
- Models: speech-to-text and IndoBERT run on the phones. Server-side stand-ins: `services/classify.py` (keyword filter, only when the phone sent no label), `pipeline.transcribe` (returns nothing; the hook for future cloud STT), `pipeline.summarize` (template until Sahabat-AI).
- Status changes live in `services/pipeline.py` and the API handlers, inside Firestore transactions where two callers can race (finalize, check-in reply vs timeout, open, decision).
- Tests sit at the HTTP API against the emulator; only token checks, push, email, and URL signing are faked (`tests/conftest.py`).

Commands (from `backend/`, needs `uv`):

| Task | Command |
|---|---|
| Install | `uv sync` |
| Test | `uv run pytest -q` runs the 16 offline tests; the rest skip without the emulators. Full run: from `firebase/`, `firebase emulators:exec --only auth,firestore "cd ../backend && uv run pytest -q"` (wipes emulator data; re-seed after) |
| Run | `uv run uvicorn app.main:app --reload` |
| Seed | `SEED_PASSWORD=... uv run python -m scripts.seed` (accounts are `<uid>@gosafe.test`) |
| Export contract | `uv run python -m scripts.export_openapi` (after any route change; commit `contracts/openapi.json`) |
| Deploy | push to `main`; `.github/workflows/backend.yml` tests then deploys to Cloud Run |

Against the emulators, set `FIREBASE_AUTH_EMULATOR_HOST=localhost:9099` and `FIRESTORE_EMULATOR_HOST=localhost:8080` (start them from `firebase/` with `firebase emulators:start`).
