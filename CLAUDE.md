# GoSafe

Ride-safety system for GoRide/GoCar: an Android app records audio on trigger (SOS / "I feel unsafe"), a FastAPI backend transcribes and classifies it, and a Next.js dashboard lets support agents review escalated cases. Hackathon project.

Read before writing code:
- [contracts/ARCHITECTURE.md](contracts/ARCHITECTURE.md): stack, API contract, incident lifecycle, deployment, phases
- [contracts/firestore-schema.md](contracts/firestore-schema.md): collections, fields, enums
- `contracts/openapi.json`: exported from FastAPI (`backend/scripts/export_openapi.py`), committed

| Folder | App | Deploys to |
|---|---|---|
| `backend/` | FastAPI | Cloud Run (`asia-southeast2`) |
| `dashboard/` | Next.js | Vercel (root dir `dashboard/`) |
| `mobile/` | Flutter, Android only | Firebase App Distribution |
| `firebase/` | rules, indexes, `firebase.json` | `firebase deploy` |

## Architecture rules

1. Clients read Firestore, write through the API. Firestore rules deny all client writes.
2. Only the backend holds admin credentials (Cloud Run service account). No service-account JSON in any app.
3. One contract: `openapi.json` is the API truth, `firestore-schema.md` the data truth. When either changes, regenerate dashboard TS types and mobile Dart models in the same PR.
4. Edge-ready payloads: `POST /incidents` takes optional `deviceTranscript` / `deviceLabel` / `deviceScore`; if present, skip cloud STT.
5. Incident `status` is one field, changed only by the backend.
6. Server timestamps are UTC; the UI converts to WIB.

## Don't

- Write to Firestore or Storage directly from the app or dashboard.
- Commit secrets, `.env` files, service-account JSON or `google-services.json`.
- Add dependencies without asking.
- Change the API or schema without updating `contracts/` in the same change.
