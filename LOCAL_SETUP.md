# Run GoSafe yourself

How to start the system on your laptop, and what you must get from the team because it is **not in the repository** (secrets, models, audio, settings on other people's accounts).

Two ways to run it:

| | A. Everything on your laptop | B. Against the deployed demo |
|---|---|---|
| Needs | The tools below, no accounts, no secrets | The same, plus the secrets below |
| Data | Firebase emulators (wiped when you stop) | The real project `gosafe-hackathon` |
| Use it for | Development, tests, a demo with no internet | Checking what the team deployed, simulating a phone |

## 1. Install once

| Tool | For | Install (macOS) |
|---|---|---|
| Java 21 | Firebase emulators | `brew install openjdk@21`, then put `/opt/homebrew/opt/openjdk@21/bin` on your `PATH` |
| Node.js and npm | Dashboard, Firebase CLI | `brew install node` |
| Firebase CLI | Emulators, deploying rules | `npm install -g firebase-tools` |
| uv | Backend and `stt/` (Python 3.12+) | `brew install uv` |
| Flutter 3.50+ and the Android SDK | Mobile app only | See [mobile/README.md](mobile/README.md). Android only; web is a preview |

## 2. Path A: everything on your laptop

```bash
git clone git@github.com:RahardiSalim/we-are-just-interns-be.git && cd we-are-just-interns-be
(cd dashboard && npm ci)
(cd backend && uv sync)
scripts/demo.sh
```

`scripts/demo.sh` starts the emulators, seeds six accounts, the backend and the dashboard, and prints the `flutter run` line with your laptop's IP. Ctrl+C stops everything.

- Dashboard: http://localhost:3000. Sign in as `agent1@gosafe.test`; the password is `SEED_PASSWORD` in `backend/.env.example` (emulator only).
- Backend: http://localhost:8000/health. Emulator UI: http://127.0.0.1:4000.
- Phone: `cd mobile && flutter pub get`, then run the line `demo.sh` prints. The phone must be on the same Wi-Fi as the laptop.
- No `backend/.env` is needed. If you create one, leave the `R2_*` lines empty, otherwise audio goes to the real R2 bucket instead of the Storage emulator.

## 3. Path B: against the deployed demo

| Piece | Where |
|---|---|
| Backend | Render service `gosafe-api`, https://gosafe-api-1izo.onrender.com. **Free tier: it sleeps after about 15 minutes. Open `/health` and wait before a demo** |
| Dashboard | Vercel, https://we-are-just-interns-be.vercel.app |
| Database and login | Firebase project `gosafe-hackathon` (Spark plan), Firestore in `asia-southeast2` |
| Audio | Cloudflare R2 bucket `gosafe-hackathon` |
| AI review | OpenRouter, a free model (`LLM_MODEL`) |

Run the dashboard locally against it: copy `dashboard/.env.example` to `dashboard/.env.local` and fill `NEXT_PUBLIC_FIREBASE_*` from Firebase console > Project settings > Your apps > `gosafe-dashboard` (public values, not secrets). Then set `NEXT_PUBLIC_API_URL` to the Render URL and `NEXT_PUBLIC_USE_EMULATORS=false`.

Accounts: `agent1@gosafe.test`, `agent2@gosafe.test` (dashboard), `rider1`, `rider2`, `driver1`, `driver2` (all `@gosafe.test`). The password is whatever `SEED_PASSWORD` was when the project was seeded: ask the team.

## 4. What is not in the repo

Nothing below is committed, and none of it should ever be. Ask the owner in the last column.

| Item | What it is | Where it goes | Who has it |
|---|---|---|---|
| `backend/.env` | R2 keys, SMTP password, LLM key. Template: `backend/.env.example` | `backend/.env` (git-ignored) | Akmal |
| Firebase service-account key | Lets the backend or `scripts.seed` act as admin on `gosafe-hackathon`. Only needed to run the backend or seed against the real project | A file **outside the repo**, then `GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json`. On Render it is a Secret File | Akmal (Firebase console > Project settings > Service accounts) |
| `dashboard/.env.local` | Public Firebase web config | `dashboard/.env.local` (git-ignored) | Firebase console |
| `google-services.json` | Android Firebase config | Not needed with the emulators. Not wired for the real project yet (see section 6) | |
| Phone models | Whisper maleo base, Silero VAD, IndoBERT-lite clf-lite-5x (ONNX), about 118 MB | **Committed** in `mobile/assets/models/`: nothing to download for the app | In the repo |
| STT model for the laptop benchmark | `maleo-ai/whisper-small-id`, whisper.cpp ggml q8_0, 264.5 MB. Public, pinned by revision and hash | `stt/models/maleo-small-id-q8_0/`, download commands in [stt/models/README.md](stt/models/README.md) | Hugging Face |
| Text classifier | DistilBERT, 11 labels, 268 MB. **Cannot be rebuilt; provenance unknown and not validated** | A folder **outside the repo** (it is over GitHub's 100 MB file limit and never goes in git). Point scripts at it with a path | The classifier owner, shared as a zip |
| Audio and datasets | Recordings, noisy test sets, the DataHive conversations (CC BY 4.0, Hugging Face) | Git-ignored folders in `stt/`. Never commit audio | Download or record again |
| Settings on other people's accounts | Cloudflare R2 CORS policy, Render env vars and Secret File, Vercel env vars, Firebase Auth sign-in methods and rules | Not files: they live in each service's dashboard | See the checklist below |

### Checklist for a fresh Firebase / Render / Vercel setup

1. **Firebase:** create the project, then Firestore in `asia-southeast2` (production mode) and Authentication with **Email/Password** and **Anonymous** enabled. Deploy rules and indexes: `cd firebase && firebase deploy --only firestore:rules,firestore:indexes --project <id>`.
2. **Seed** (once, from `backend/`): `GCP_PROJECT=<id> GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json SEED_PASSWORD='<your password>' uv run python -m scripts.seed`. Use your own password, not the emulator default.
3. **R2:** a bucket, an S3 access key, and a **CORS policy** that allows `GET`, `HEAD` and `PUT` from the dashboard's origin (and `http://localhost:3000`) with headers `*` and exposed `Content-Length`, `Content-Range`, `Accept-Ranges`, `ETag`. Without it the dashboard says "Could not load the recording: Failed to fetch".
4. **Render:** a Docker web service from branch `main`, root directory `backend`. Env vars: `GCP_PROJECT`, `GOOGLE_APPLICATION_CREDENTIALS=/etc/secrets/firebase-sa.json`, `ENABLE_DEV_ROUTES=false`, `R2_*`, `SMTP_*`, `EMAIL_FROM`, `LLM_*`. A Secret File named `firebase-sa.json` holds the service-account key.
5. **Vercel:** root directory `dashboard`. Set the six `NEXT_PUBLIC_*` variables, then redeploy: they are baked in at build time.

## 5. Tests

| Part | Command | Needs |
|---|---|---|
| Backend | `cd backend && uv run pytest -q` runs the offline tests; the rest skip without emulators. Full run: `cd firebase && firebase emulators:exec --only auth,firestore "cd ../backend && uv run pytest -q"` | uv, Java 21 for the full run |
| STT | `cd stt && python -m pytest -q` | `pip install numpy scipy soundfile pytest`; no model |
| Dashboard | `cd dashboard && npm run lint && npm run build` | `npm ci` |
| Mobile | `cd mobile && flutter analyze && flutter test` | Flutter |

## 6. Known limits (read before a demo)

- **Edge AI is tested on the emulator only.** On Android the app transcribes and classifies on the phone (`mobile/lib/services/edge_ai.dart`). Speed, memory and battery on a real phone were not measured, and the emulator's microphone gives silence, so live speech was tested only from a WAV file (`WHISPER_TEST_WAV`). `DEMO_SCRIPT=demo` plays the scripted conversation instead.
- **The mobile app only knows the emulators.** `mobile/lib/main.dart` hard-codes the offline project `demo-gosafe`. Using `gosafe-hackathon` needs a code change (Firebase options from `--dart-define`) and an Android app registered in Firebase.
- **Render free tier sleeps**, and OpenRouter free models are rate-limited (HTTP 429). Without the LLM the review falls back to rules.
- **The review source is labelled "Sahabat-AI"** for any LLM, because the schema has only that value. Whatever model is configured, the dashboard shows that name.
- **Decision emails go to the accounts' addresses.** The seeded `@gosafe.test` addresses cannot receive mail.
- **The service-account key on Render** goes against architecture rule 2. Rotate it after the demo.
- Details of the deployed stack: [contracts/ARCHITECTURE.md](contracts/ARCHITECTURE.md), "Demo deployment".
