# GoSafe architecture (build spec)

Single source of truth for building the three apps. Where the earlier "System design" doc disagrees, this file wins.

## Stack

| Part | Pick | Notes |
|---|---|---|
| Android app | Flutter (Android only) | Background recording needs an Android foreground service with the `microphone` type. `sherpa_onnx` Flutter package for the later on-device step. |
| Backend | FastAPI on Cloud Run | Same Google project as Firebase, so Firestore, Storage, FCM and Speech-to-Text work with no extra keys. IndoBERT via ONNX Runtime, not full PyTorch. |
| Database | Firestore | Not relational, no geo queries: route maths in Python. |
| Files | Cloud Storage for Firebase | Requires the **Blaze** plan (fails with 402/403 on Spark). Add a budget alert. |
| Dashboard | Next.js on Vercel (Hobby) | No ML and no secrets in Next.js. Reads Firestore, calls FastAPI. |
| Repo | One monorepo | Vercel and Cloud Run both deploy from a sub-folder. |

Cost: Cloud Run free tier covers a 2 GiB instance for roughly 62 h/month if it scales to zero.

## How the pieces connect

- Mobile app and dashboard **read** Firestore live, **write** through FastAPI.
- The app uploads audio straight to Cloud Storage using a signed URL from FastAPI.
- FCM pushes check-ins to the app.
- Neither client ever holds admin credentials.

## Architecture rules

1. **Clients read Firestore, write through the API.** Firestore rules deny all client writes.
2. **Only the backend holds admin credentials.** Cloud Run service account. No service-account JSON in any app, ever.
3. **One contract.** `contracts/openapi.json` is the API truth, `contracts/firestore-schema.md` the data truth. When either changes, regenerate TypeScript types (dashboard) and Dart models (mobile) in the same pull request.
4. **Edge-ready payloads.** `POST /incidents` accepts an optional on-device transcript and label. If present, the backend skips cloud STT.
5. **Status lives in one field.** Each incident has one `status`, changed only by the backend, following the lifecycle below.
6. **Timestamps are UTC** (Firestore server time); the UI converts to WIB.

## Data model

See [firestore-schema.md](firestore-schema.md).

## API contract

Every endpoint takes `Authorization: Bearer <Firebase ID token>`; the backend checks the token and the `role` claim.

| Method + path | Caller | Does |
|---|---|---|
| `GET /health` | Anyone | Liveness |
| `POST /me/fcm-token` | App | Saves the device push token |
| `POST /me/consent` | App | Sets `audioConsent` |
| `POST /trips` | App (rider) | Starts a demo trip with a fixture route and a driver; returns `tripId` |
| `POST /trips/{id}/events` | App | Batch of GPS points or SOS / manual-unsafe events (stored only, see Decisions) |
| `POST /trips/{id}/end` | App | Ends the trip |
| `POST /incidents` | App | Body: `tripId`, `trigger`, window start/end, optional `deviceTranscript`, `deviceLabel`, `deviceScore`. Returns `incidentId` + signed upload URL (10 min) |
| `POST /incidents/{id}/finalize` | App | Clip uploaded; returns 202 and starts processing |
| `POST /checkins/{id}/reply` | App | `ok` or `need_help` |
| `GET /incidents/{id}/clip-url` | Dashboard (agent) | Short-lived signed read URL; writes an audit log |
| `POST /incidents/{id}/decision` | Dashboard (agent) | `dismiss` \| `warn_driver` \| `suspend_driver` \| `contact_rider` + note |
| `POST /dev/seed`, `POST /dev/reset` | Team only | Loads users, trips, sample incidents. Disabled when `ENABLE_DEV_ROUTES` is off |

## Incident lifecycle

Only the backend changes `status`.

| Status | Set when | Next |
|---|---|---|
| `awaiting_upload` | `POST /incidents` | `processing` on finalize; `failed` after 10 min |
| `processing` | Finalize | STT → classifier → severity → `dismissed`, `checkin_pending` or `escalated` |
| `dismissed` | Severity low | Logged, deleted at `deleteAt` |
| `checkin_pending` | Severity medium; FCM push + `checkins` doc to rider and driver | `resolved_ok` if both reply ok; `escalated` on `need_help` or no reply in 90 s |
| `escalated` | Severity high or failed check-in; timeline + LLM summary built | `under_review` when an agent opens it |
| `under_review` | Agent opens the ticket | `closed` after a decision |
| `closed` | Decision recorded | Driver may appeal (stretch) |

Processing: download clip → Chirp 3 STT (`id-ID`, 16 kHz mono WAV/FLAC) unless a device transcript was sent → IndoBERT on 30 s windows → combine with trip events for severity → for escalations, Sahabat-AI (or a hosted LLM) writes the summary from the masked transcript and timeline.

Classifier labels: `normal`, `uncomfortable`, `sexual_harassment`, `threat`.

## Auth and security

- **Accounts:** email + password demo accounts (2 riders, 2 drivers, 2 agents). `backend/scripts/seed.py` creates them and sets the `role` custom claim.
- **Firestore rules:** deny every client write. A user reads their own `users` doc, trips where they are rider or driver, their own `checkins`, and incidents they reported. Agents read everything.
- **Storage rules:** deny all client access. Only signed URLs from the backend. The Cloud Run service account needs "Service Account Token Creator" on itself to sign URLs.
- **Audio:** HTTPS + Google encryption at rest + 10-min signed URLs. App-side AES-GCM is a stretch goal.
- **Privacy:** mask phone numbers and names before transcripts reach the LLM; log every clip view; no model decision bans anyone automatically.
- **Secrets:** never committed. Backend reads env vars on Cloud Run; dashboard uses Vercel env vars; `google-services.json` stays out of public repos.

| App | Config |
|---|---|
| backend | `GCP_PROJECT`, `FIREBASE_STORAGE_BUCKET`, `SPEECH_REGION`, `LLM_BASE_URL`, `LLM_API_KEY`, `ENABLE_DEV_ROUTES`, `CHECKIN_TIMEOUT_SEC` (90) |
| dashboard | `NEXT_PUBLIC_FIREBASE_*`, `NEXT_PUBLIC_API_URL` |
| mobile | `google-services.json`, `API_URL` via `--dart-define`, `DEMO_MODE` |

Local development: Firebase Local Emulator Suite (Auth, Firestore, Storage); backend with `uvicorn --reload` against the emulators.

## Deployment

| App | Where | How |
|---|---|---|
| backend | Cloud Run, `asia-southeast2` | GitHub Action on push to `main` when `backend/**` changes. 2 GiB, min instances 0, instance-based billing (keeps CPU after the 202) |
| dashboard | Vercel, root `dashboard/` | Preview per PR, production on `main` |
| mobile | Physical Android phones | `flutter build apk` → Firebase App Distribution |
| firebase | Firebase project | `firebase deploy --only firestore:rules,firestore:indexes,storage` from `firebase/` |

One shared Firebase + GCP project, emulators locally, a `DEMO_MODE` flag instead of a separate prod project.

## Phases

| Phase | Done when |
|---|---|
| 1. Walking skeleton | App logs in, calls `/health`, dashboard shows a seeded incident live |
| 2. Core flow | One full incident (SOS → upload → STT → classifier → check-in → escalate → ticket) works on the deployed stack |
| 3. Polish | Timeline map, LLM summary, Safe Ride badge, metrics. Demo script runs twice with no fixes |
| 4. Freeze | Last deploy hours before judging; tag the commit; backup video recorded |

Demo-day checklist: call `/health` to warm Cloud Run, reset + seed, phone charged with mobile data on, dashboard open and logged in, backup video one click away.

## On hold

Waiting on something outside the code. Build around these with stubs or seed data until they land.

| Item | Waiting on | Until then |
|---|---|---|
| IndoBERT classifier (ONNX int8) | Modelling team: dataset + fine-tune + export | Seeded incidents carry a fixed `label` and `score` |
| Chirp 3 STT | Firebase/GCP project on Blaze, Speech API enabled | Seeded transcript |
| Sahabat-AI summary | A hosted endpoint (`LLM_BASE_URL`, `LLM_API_KEY`) | Seeded summary |
| On-device STT / classifier | Modelling team ONNX exports, a test phone | Cloud path only |
| Sample audio + real GPS trace | Team recordings | `contracts/fixtures/demo-trip.json` (hand-made route), `clipPath: null` |
| Firebase project | Blaze plan + budget alert | Emulators (`demo-gosafe`) |
| Backend deploy | GitHub repo variables `GCP_PROJECT`, `GCP_WIF_PROVIDER`, `GCP_DEPLOY_SA` (Workload Identity Federation) | Run locally |
| Mobile app | Flutter SDK + Android phone on a dev machine | Not started |

## Decisions (where the two source docs disagreed)

- **Severity is decided in the backend** for the demo (cloud path). The on-phone path arrives later through rule 4 with no API change.
- **No trip-anomaly rules.** GoTo already records trip anomalies. `POST /trips/{id}/events` only stores GPS and SOS / manual-unsafe events for the timeline map.
