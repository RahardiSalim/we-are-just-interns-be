# GoSafe

Ride-safety system for GoRide/GoCar: rider and driver phones listen during the trip, transcribe and classify speech on the phone, warn both people or report automatically, and keep SOS / "I feel unsafe" always available. A FastAPI backend runs the incident flow, and a Next.js dashboard lets support agents review escalated cases. Hackathon project.

Read before writing code:
- [LOCAL_SETUP.md](LOCAL_SETUP.md): run it on your laptop, and the secrets, models and settings that are not in the repo
- [contracts/ARCHITECTURE.md](contracts/ARCHITECTURE.md): stack, API contract, incident lifecycle, deployment, phases
- [contracts/firestore-schema.md](contracts/firestore-schema.md): collections, fields, enums
- [mobile/README.md](mobile/README.md): how the mobile app's logic works (the core of the product)
- [contracts/DESIGN.md](contracts/DESIGN.md): the shared look (Gojek Asphalt): colours, type, spacing, components. Both apps use its tokens
- `contracts/openapi.json`: exported from FastAPI (`backend/scripts/export_openapi.py`), committed

| Folder | App | Deploys to |
|---|---|---|
| `backend/` | FastAPI | Cloud Run (`asia-southeast2`) |
| `dashboard/` | Next.js | Vercel (root dir `dashboard/`) |
| `mobile/` | Flutter, Android only | Firebase App Distribution |
| `firebase/` | rules, indexes, `firebase.json` | `firebase deploy` |
| `stt/` | Python, speech-to-text reference pipeline and benchmark ([stt/README.md](stt/README.md)) | Not deployed: STT runs on the phones |

## Run everything locally

No Firebase project is needed: the emulators use the offline project `demo-gosafe`.

Once: install Java 21 (`brew install openjdk@21`, then put `/opt/homebrew/opt/openjdk@21/bin` on your `PATH`), the Firebase CLI (`npm install -g firebase-tools`), and `uv`.

**One command for a demo:** `scripts/demo.sh` runs steps 1–4 below, reachable from a phone on the same Wi-Fi (or with the laptop on the phone's hotspot), and prints the `flutter run` line with the laptop's IP. Ctrl+C stops everything.

| Step | Where | Command |
|---|---|---|
| 1. Emulators (UI at http://127.0.0.1:4000) | `firebase/` | `firebase emulators:start` |
| 2. Seed 6 accounts + demo data | `backend/` | `set -a; . ./.env.example; set +a; uv run python -m scripts.seed` |
| 3. Backend | `backend/` | same env, then `uv run uvicorn app.main:app --reload` |
| 4. Dashboard, live | `dashboard/` | `NEXT_PUBLIC_FIREBASE_API_KEY=demo-key NEXT_PUBLIC_FIREBASE_PROJECT_ID=demo-gosafe NEXT_PUBLIC_USE_EMULATORS=true npm run dev` |

Sign in as `agent1@gosafe.test` with the `SEED_PASSWORD` from `backend/.env.example`. Emulator data is wiped when the emulators stop; re-run step 2.

## Architecture rules

1. Clients read Firestore, write through the API. Firestore rules deny all client writes.
2. Only the backend holds admin credentials (Cloud Run service account). No service-account JSON in any app.
3. One contract: `openapi.json` is the API truth, `firestore-schema.md` the data truth. When either changes, regenerate dashboard TS types and mobile Dart models in the same PR.
4. The phone judges first: both phones listen, transcribe and classify on-device (ARCHITECTURE.md "On-device listening"); `POST /incidents` carries `deviceTranscript` / `deviceLabel` / `deviceScore` and the backend uses them as given.
5. Incident `status` is one field, changed only by the backend.
6. Server timestamps are UTC; the UI converts to WIB.

## Don't

- Write to Firestore or Storage directly from the app or dashboard.
- Commit secrets, `.env` files, service-account JSON or `google-services.json`.
- Add dependencies without asking.
- Change the API or schema without updating `contracts/` in the same change.
