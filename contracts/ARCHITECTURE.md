# GoSafe architecture (build spec)

Single source of truth for building the three apps. Where the earlier "System design" doc disagrees, this file wins.

## Stack

| Part | Pick | Notes |
|---|---|---|
| Android app | Flutter (Android only) | Listens for the whole trip on both phones (see "On-device listening"). Foreground service with the `microphone` type; `sherpa_onnx` for voice detection + Whisper; ONNX Runtime for IndoBERT. |
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

## On-device listening (mobile)

Agreed 2026-11-26. The phone listens and judges; the backend only hears about it when a person reports or the model is confident something is wrong.

**Who records.** Rider and driver both consent at trip start, and **both phones** record for the whole trip. Recording on both means the victim's copy survives if the other person deletes the app. Without both consents nothing is recorded.

**Pipeline on each phone.**
1. Silero VAD (voice detection) via `sherpa_onnx`, so speech-to-text only runs while someone is talking.
2. Whisper (`cahya/whisper-small-id`, ONNX int8) via `sherpa_onnx` on each utterance as it ends. Text arrives a few seconds behind speech. sherpa-onnx has no official streaming Indonesian model; the only one found is a third-party upload we couldn't verify, so VAD + Whisper is the plan.
3. IndoBERT (ONNX int8, ONNX Runtime) on a sliding window of the last 30 s of text → `label` + `score`. It needs its WordPiece tokenizer in Dart (or a model export that includes it).

**Storage on the phone.** All audio (Opus, about 7 MB per hour) and all transcripts, flagged or not, stay on each phone for **7 days**, then are deleted.
- Encrypted with AES-GCM using an Android Keystore key, so only the app can read it. Users can't play it back or export it in the app.
- It leaves the phone only through a report, an automatic "high" report, or an agent's audio request.
- The consent screen states this, including the 7 days (UU PDP: purpose and retention must be stated).

**Responses.** The two thresholds are set by the modelling team from their test set.

| Level | When | What happens |
|---|---|---|
| Warning | `score` ≥ warning threshold | A neutral message on **both** phones: the conversation seems off, tell us if you're uncomfortable, please keep it respectful. Plus a Report button. At most once per trip or once every 10 minutes. Logged as a trip event; no incident. |
| High | `score` ≥ high threshold for `threat` / `sexual_harassment` | At the same moment: an "Are you OK?" check-in to both, **and** an incident with `trigger: auto` plus the flagged clip goes to customer service. A "need help" answer raises the case's priority. |
| SOS / "I feel unsafe" | A person presses it, any time | Unchanged. The buttons are always on screen and never wait for the model. |

**Rules.**
- **Motorbike drivers:** a GoRide driver can't tap while riding, so the driver's silence never counts as "no reply". The rider's answer decides. In GoCar both answers count.
- **A person decides:** customer service reviews every case. The model never warns, suspends or bans a driver on its own record.

**Biggest risks.** Whisper's speed and battery use on both phones over a full driver shift: measure on a mid-range phone in week one, and try Whisper-base if small is too slow. The second risk is the Dart tokenizer for IndoBERT.

## Architecture rules

1. **Clients read Firestore, write through the API.** Firestore rules deny all client writes.
2. **Only the backend holds admin credentials.** Cloud Run service account. No service-account JSON in any app, ever.
3. **One contract.** `contracts/openapi.json` is the API truth, `contracts/firestore-schema.md` the data truth. When either changes, regenerate TypeScript types (dashboard) and Dart models (mobile) in the same pull request.
4. **The phone judges first.** `POST /incidents` carries the on-device transcript, label and score. The backend uses them as given, and only runs cloud STT when a report arrives without a transcript.
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
| `POST /incidents/{id}/open` | Dashboard (agent) | Takes an `escalated` ticket: `under_review`, `assignedAgent` = caller |
| `GET /incidents/{id}/clip-url` | Dashboard (agent) | Short-lived signed read URL; writes an audit log |
| `POST /incidents/{id}/decision` | Dashboard (agent) | `dismiss` \| `warn_driver` \| `suspend_driver` \| `contact_rider` + note |
| `POST /dev/seed`, `POST /dev/reset` | Team only | Loads users, trips, sample incidents. Disabled when `ENABLE_DEV_ROUTES` is off |

**Planned for on-device listening** (not built yet):

| Change | Caller | Does |
|---|---|---|
| `POST /incidents` accepts `trigger: auto` | App | Requires `deviceLabel` + `deviceScore`. Escalates at once *and* sends the check-in to both, without changing `status` to `checkin_pending` |
| `POST /trips/{id}/events` accepts `type: warning` | App | Logs a warning with `data: {label, score}`. No incident |
| `POST /checkins/{id}/reply` on GoRide | App | The driver's no-reply is ignored: rider `ok` resolves, rider `need_help` or rider no-reply escalates |
| `POST /incidents/{id}/request-audio` | Dashboard (agent) | Creates one `audioRequests` doc per phone and pushes `{type: audio_request}` to both. Writes an audit log |
| `POST /audio-requests/{id}/upload-url` | App | Signed upload URL + `uploadMethod` for that trip's audio from this phone |
| `POST /audio-requests/{id}/done` | App | Marks the upload complete; the dashboard shows the clips |

## Incident lifecycle

Only the backend changes `status`.

| Status | Set when | Next |
|---|---|---|
| `awaiting_upload` | `POST /incidents` | `processing` on finalize (no 10-min `failed` sweep yet) |
| `processing` | Finalize | STT → classifier → severity → `dismissed`, `checkin_pending` or `escalated` |
| `dismissed` | Severity low | Logged, deleted at `deleteAt` |
| `checkin_pending` | Severity medium; FCM push + `checkins` doc to rider and driver | `resolved_ok` if both reply ok; `escalated` on `need_help` or no reply in 90 s |
| `escalated` | Severity high, failed check-in, or `trigger: auto` (planned; the check-in to both runs alongside); timeline + LLM summary built | `under_review` when an agent opens it |
| `under_review` | Agent calls `POST /incidents/{id}/open` | `closed` after a decision |
| `closed` | Decision recorded | Driver may appeal (stretch) |

Processing: download clip → Chirp 3 STT (`id-ID`, 16 kHz mono WAV/FLAC) unless a device transcript was sent → IndoBERT on 30 s windows → combine with trip events for severity → for escalations, Sahabat-AI (or a hosted LLM) writes the summary from the masked transcript and timeline.

Classifier labels: `normal`, `uncomfortable`, `sexual_harassment`, `threat`.

## Auth and security

- **Accounts:** email + password demo accounts (2 riders, 2 drivers, 2 agents). `backend/scripts/seed.py` creates them and sets the `role` custom claim.
- **Firestore rules:** deny every client write. A user reads their own `users` doc, trips where they are rider or driver, their own `checkins`, and incidents they reported. Agents read everything.
- **Storage rules:** deny all client access. Only signed URLs from the backend. The Cloud Run service account needs "Service Account Token Creator" on itself to sign URLs.
- **Audio:** on the phone, AES-GCM with an Android Keystore key (required, since audio stays on the phone for 7 days). In transit, HTTPS with 10-min signed URLs; in the cloud, Google encryption at rest.
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
| On-device Whisper + IndoBERT | Modelling team: ONNX exports, the warning/high thresholds, a speed and battery benchmark on a mid-range phone | The app sends a canned transcript and label so the backend flow can be tested |
| Sample audio + real GPS trace | Team recordings | `contracts/fixtures/demo-trip.json` (hand-made route), `clipPath: null` |
| Firebase project | Blaze plan + budget alert | Emulators (`demo-gosafe`) |
| Backend deploy | GitHub repo variables `GCP_PROJECT`, `GCP_WIF_PROVIDER`, `GCP_DEPLOY_SA` (Workload Identity Federation) | Run locally |
| Mobile listening service | Android SDK + a real phone (the microphone service can't run in the web preview) | Mock trip screen in `mobile/` |
| Warning message wording | Team / pitch owner | Placeholder text |

## Decisions (where the two source docs disagreed)

- **Severity rules for button reports** (`backend/app/services/pipeline.py`): `threat` or `sexual_harassment` → high (escalate). No label at all and trigger `sos` → high. Everything else → medium (check-in). A person pressed the button, so the backend never dismisses these. Automatic reports only arrive at "high", so `dismissed` stays unused for now.
- **Classifier until IndoBERT lands:** an Indonesian keyword filter (`app/services/classify.py`). A `deviceLabel` from the phone always wins; the filter still marks `flagged` lines.
- **Summary until Sahabat-AI is hosted:** a template from the masked flagged lines (phone numbers masked; names not yet).
- **Retention:** 7 days by default, 30 days while a case is escalated, back to 7 days once closed.

- **The phone listens and judges** (replaces the earlier "backend decides severity, phone only on button press" plan). See "On-device listening". Button reports still go through the backend's severity rules.
- **No trip-anomaly rules.** GoTo already records trip anomalies. `POST /trips/{id}/events` only stores GPS and SOS / manual-unsafe events for the timeline map.
