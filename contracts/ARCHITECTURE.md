# GoSafe architecture (build spec)

Single source of truth for building the three apps. Where the earlier "System design" doc disagrees, this file wins.

## Stack

| Part | Pick | Notes |
|---|---|---|
| Android app | Flutter (Android only) | Listens for the whole trip on both phones (see "On-device listening"). Foreground service with the `microphone` type; `sherpa_onnx` for voice detection + Whisper; ONNX Runtime for IndoBERT. |
| Backend | FastAPI on Cloud Run | Same Google project as Firebase, so Firestore, Storage and FCM work with no extra keys. No speech or classifier models on the server: those run on the phones. |
| Database | Firestore | Not relational. Holds no location data (see "No location data"). |
| Files | Cloud Storage for Firebase | Requires the **Blaze** plan (fails with 402/403 on Spark). Add a budget alert. |
| Dashboard | Next.js on Vercel (Hobby) | No ML and no secrets in Next.js. Reads Firestore, calls FastAPI. |
| Repo | One monorepo | Vercel and Cloud Run both deploy from a sub-folder. |

Cost: Cloud Run free tier covers a 2 GiB instance for roughly 62 h/month if it scales to zero.

## How the pieces connect

- Mobile app and dashboard **read** Firestore live, **write** through FastAPI.
- The app uploads audio straight to Cloud Storage using a signed URL from FastAPI.
- FCM is not used yet: during a ride the phone's own foreground service raises every alert.
- Email (plain SMTP): whoever presses SOS gets a "ticket created, being processed" email; after a decision, the rider (and the driver when contacted, warned or suspended) is told what the safety team decided, with the agent's message when there is one. Tickets are numbered `GS-XXXX-XXXX` (from the incident ID) in emails and on the dashboard.
- Neither client ever holds admin credentials.

## On-device listening (mobile)

How the app implements this, step by step (window, classifier scoring, decision rules, screens, payloads): [mobile/README.md](../mobile/README.md).

Agreed 2026-11-26. **The mobile app is the core:** everything from speech-to-text to flagging and responding runs on the phone. The backend only receives reports, escalates them, and serves the agent dashboard.

**The app (hackathon build).** No login screen: each install signs in anonymously, so the backend still knows whose ride and report it is; in production the GoJek app's own login replaces this. No rider/driver choice: one flow on the consumer's phone, "Start ride", consent, record.

**Consent.** Only the consumer is asked, in a prompt when the ride starts. The driver chose earlier in their own settings; turning it on is what gives them the **Safe Ride badge**, and drivers who leave it off don't get the badge. The ride is recorded only if the consumer says yes **and** the driver has Safe Ride on. Without both, nothing is recorded and SOS still works.

**Pipeline on the phone.**
1. Microphone: records the whole ride (16 kHz mono, AAC `.m4a`).
2. Silero VAD (voice detection) via `sherpa_onnx`, so speech-to-text only runs while someone is talking. *Not built yet.*
3. Whisper (`cahya/whisper-small-id`, ONNX int8) via `sherpa_onnx` on each utterance as it ends. sherpa-onnx has no official streaming Indonesian model, so VAD + Whisper is the plan. *Not built yet: a scripted conversation stands in.*
4. IndoBERT (ONNX int8, ONNX Runtime) on a sliding window of the last 15 s of text → `label` + `score`. Needs its WordPiece tokenizer in Dart. *Not built yet: a keyword filter stands in.*

**Responses.** The two thresholds are set by the modelling team from their test set. Every message is short and caring, never alarming.

| Level | When | What happens |
|---|---|---|
| Warning | `score` ≥ warning threshold | A kind, neutral message on the phone with "I'm fine" and "Report". At most once every 10 minutes. Nothing is sent; the moment is marked on the phone. |
| High | `score` ≥ high threshold for `threat` / `sexual_harassment` | The flag goes to the backend **immediately** (`trigger: auto`), escalated for an agent. The phone asks "Are you okay?", **quietly first**: vibration only, every 10 s. No answer at **60 s**: the phone goes **Live**. No answer at **120 s**: the loud alarm, and "shout TOLONG", which then counts as "I need help". |
| Report driver / Report passenger | A person presses it, any time, or "Report" on a warning | Sent immediately (`trigger: manual_unsafe`), then "Do you need help right now?": "Yes, get help" is an SOS. |
| SOS | The SOS button, "I need help", the safe phrase, or a shout for help | Sent immediately and the phone goes **Live**. The buttons are always on screen and never wait for the model. |

**What leaves the phone.** Each ride has a share level that only goes up (`Share` in `mobile/lib/services/ride_store.dart`):

| Level | What leaves the phone | Reached by |
|---|---|---|
| Local | Nothing. Audio, transcript and flags stay encrypted on the phone for 7 days | Ride start, warnings, "I'm fine" |
| At end | When the ride ends: every audio piece, the transcript and every flag, so the cloud computes nothing again | A report; a high flag |
| Live | Now: every piece so far, transcript and flags; then each new 10-second piece and line until the ride ends | SOS, "I need help", "Yes, get help", the safe phrase, a shout for help, a high flag unanswered for 60 s |

Both phones (rider and driver) run the same app and logic and each uploads its own recording. Reports from either phone about the same ride join **one case**.

**Uploads.** Audio goes up in numbered pieces, so a retry never duplicates and Live can stream. With no signal, uploads wait on the phone and are retried every minute (within the 7 days). The backend refuses a recording without a `high`, `sos` or `manual_unsafe` marker. In the cloud, recordings are deleted after 7 days unless a case is open.

**Rules.**
- **No check-ins from the backend:** the phone asks its own user. The backend never asks the other person, which would tell a driver they've been reported.
- **Motorbike drivers:** a GoRide driver can't tap while riding, so the safe phrase and "shout TOLONG" matter most on the driver's phone.
- **A person decides:** customer service reviews every case. The model never warns, suspends or bans a driver on its own record.
- **Nothing covers the SOS button:** messages appear at the top of the screen, never over the bottom buttons.

**Biggest risks.** Whisper's speed and battery use on both phones over a full driver shift: measure on a mid-range phone in week one, and try Whisper-base if small is too slow. The second risk is the Dart tokenizer for IndoBERT.

## Architecture rules

1. **Clients read Firestore, write through the API.** Firestore rules deny all client writes.
2. **Only the backend holds admin credentials.** Cloud Run service account. No service-account JSON in any app, ever.
3. **One contract.** `contracts/openapi.json` is the API truth, `contracts/firestore-schema.md` the data truth. When either changes, regenerate TypeScript types (dashboard) and Dart models (mobile) in the same pull request.
4. **The phone judges first.** `POST /incidents` carries the on-device transcript, label and score. The backend uses them as given. Speech-to-text and the classifier are edge AI and run only on the phones; cloud processing is future work (see "Future work").
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
| `POST /me/consent` | Driver phone | Sets `audioConsent`: the driver's Safe Ride setting |
| `POST /trips` | App | Body: `riderConsent` (the consumer's answer), optional `orderId` (the GoJek order ID, which becomes the `tripId`; generated for the demo when missing), `mode`. Driver consent comes from the driver's Safe Ride setting. Assigns the demo driver; 409 if the order already has a trip. With `role: driver` the driver's phone joins the trip instead (by `orderId`, or for the demo the newest active trip still waiting for a driver; 404 if none) |
| `POST /trips/{id}/events` | App | Batch of SOS / manual-unsafe events with a timestamp. No location fields |
| `POST /trips/{id}/end` | App | Ends the trip |
| `PUT /trips/{id}/recording` | App | This phone's recording details: `durationSec`, `contentType`, `markers`, `transcript`, `pieces` (uploaded so far), `live`, `done`. Needs both consents and a `high`, `sos` or `manual_unsafe` marker (409 otherwise). `live` marks the ride's open case LIVE; `done` starts the AI review |
| `POST /trips/{id}/recording/pieces/{n}` | App | Upload URL + method for audio piece `n` (`recordings/{tripId}/{rider\|driver}/{n:06}.aac`). Needs the details first |
| `GET /trips/{id}/recording-urls` | Dashboard (agent) | Short-lived read URLs for every piece, per phone; writes an audit log. The dashboard joins them to play |
| `POST /incidents` | App | Body: `tripId`, `trigger` (`sos` \| `manual_unsafe` \| `auto`), window start/end, `deviceTranscript`, `deviceLabel`, `deviceScore` (`auto` requires label + score and always escalates). Returns `incidentId`, signed upload URL (10 min), `uploadMethod`. If the ride already has an open case (from either phone), the report joins it (`merged: true`, no finalize needed); an `sos` or `auto` report makes it high priority |
| `POST /incidents/{id}/finalize` | App | Clip uploaded; returns 202 and starts processing |
| `POST /incidents/{id}/open` | Dashboard (agent) | Takes an `escalated` ticket: `under_review`, `assignedAgent` = caller |
| `GET /incidents/{id}/clip-url` | Dashboard (agent) | Short-lived signed read URL; writes an audit log |
| `POST /incidents/{id}/decision` | Dashboard (agent) | `customer` (`contact` \| `none`) **or** `driver` (`contact` \| `warn` \| `suspend` \| `none`): either side may be left out (it means `none`); both `none` dismisses. Optional `customerNote` / `driverNote` (sent in that person's email) |
| `POST /dev/seed`, `POST /dev/reset` | Team only | Loads users, trips, sample incidents. Disabled when `ENABLE_DEV_ROUTES` is off |

## Incident lifecycle

Only the backend changes `status`.

| Status | Set when | Next |
|---|---|---|
| `awaiting_upload` | `POST /incidents` | `processing` on finalize (no 10-min `failed` sweep yet) |
| `processing` | Finalize | device transcript + label (keyword filter if the phone sent no label) → severity → `escalated` |
| `dismissed` | Severity low | Logged, deleted at `deleteAt` |
| `escalated` | Every processed case (severity orders the queue: LIVE first, then high, then medium); summary built | `under_review` when an agent opens it |
| `under_review` | Agent calls `POST /incidents/{id}/open` | `closed` after a decision |
| `closed` | Decision recorded; emails sent after the response (`services/mailer.py`) | Driver may appeal (stretch) |

Processing: take the phone's transcript, label and score → if the phone sent no label, the keyword filter labels the transcript → severity → for escalations, a summary from the masked transcript (template now, Sahabat-AI later). A report with no transcript at all (the models weren't ready on the phone) is judged by its trigger alone.

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
| backend | `GCP_PROJECT`, `FIREBASE_STORAGE_BUCKET`, `ENABLE_DEV_ROUTES`, `CHECKIN_TIMEOUT_SEC` (90), and for the AI review `LLM_BASE_URL` / `LLM_API_KEY` / `LLM_MODEL` (Sahabat-AI) and `GEMINI_API_KEY` / `GEMINI_MODEL` (fallback), and for decision emails `SMTP_HOST` / `SMTP_PORT` (587) / `SMTP_USER` / `SMTP_PASSWORD` / `EMAIL_FROM` (empty host: logged, not sent) |
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

### Demo deployment (hackathon, 27 Nov 2026)

Cloud Run is still the target above. For the demo, without a GCP billing account, the stack runs on free tiers:

| Piece | Where | Notes |
|---|---|---|
| backend | Render web service `gosafe-api` (free), branch `main`, root `backend/`, the same `Dockerfile` | Sleeps after about 15 min idle: call `/health` before the demo. Env vars and a Secret File are set in Render, not in the repo |
| Firestore + Auth | Firebase project `gosafe-hackathon`, Spark plan (no card) | Firestore in `asia-southeast2`. Sign-in: Email/Password (dashboard) and Anonymous (app). Rules and indexes deployed from `firebase/`; seeded with `scripts.seed` |
| Ride audio | Cloudflare R2 bucket `gosafe-hackathon` (`R2_*` env vars) | Replaces Firebase Storage, which needs Blaze |
| AI review | OpenRouter (`LLM_BASE_URL=https://openrouter.ai/api/v1`), a free model set by `LLM_MODEL` | Free models are rate-limited (429 seen on two of three tried). The review falls back to rules. Stored with `source: "sahabat-ai"` because that is the only LLM source the schema has, so the dashboard shows "Sahabat-AI" for it |
| dashboard | Vercel, as above | `NEXT_PUBLIC_*` point at `gosafe-hackathon` and the Render URL |

**Breaks rule 2:** off Google Cloud there is no attached service account, so the backend on Render reads a Firebase service-account key from a Render Secret File (`GOOGLE_APPLICATION_CREDENTIALS`). The key is only on the backend host and never in the repo or an app. Rotate it after the demo, or move back to Cloud Run.

Decision emails go to the Firebase Auth address of the rider and driver. The seeded accounts use `@gosafe.test`, which cannot receive mail.

## Phases

| Phase | Done when |
|---|---|
| 1. Walking skeleton | App logs in, calls `/health`, dashboard shows a seeded incident live |
| 2. Core flow | One full incident (SOS → on-phone transcript and label → upload → check-in → escalate → ticket) works on the deployed stack |
| 3. Polish | Event timeline, LLM summary, Safe Ride badge, metrics. Demo script runs twice with no fixes |
| 4. Freeze | Last deploy hours before judging; tag the commit; backup video recorded |

Demo-day checklist: call `/health` to warm Cloud Run, reset + seed, phone charged with mobile data on, dashboard open and logged in, backup video one click away.

## On hold

Waiting on something outside the code. Build around these with stubs or seed data until they land.

| Item | Waiting on | Until then |
|---|---|---|
| IndoBERT classifier (ONNX int8) | Modelling team: dataset + fine-tune + export | Seeded incidents carry a fixed `label` and `score` |
| Sahabat-AI summary | A hosted endpoint (`LLM_BASE_URL`, `LLM_API_KEY`) | Seeded summary |
| On-device Whisper + IndoBERT | Modelling team: ONNX exports, the warning/high thresholds, a speed and battery benchmark on a mid-range phone | The app sends a canned transcript and label so the backend flow can be tested |
| Sample audio | Team recordings | `clipPath: null` in the seed |
| Firebase project (Blaze) | Blaze plan + budget alert, for Cloud Run and Firebase Storage | Spark project `gosafe-hackathon` + R2 + Render (see "Demo deployment") |
| Backend deploy (Cloud Run) | GitHub repo variables `GCP_PROJECT`, `GCP_WIF_PROVIDER`, `GCP_DEPLOY_SA` (Workload Identity Federation) | Render (see "Demo deployment") |
| Mobile listening service | Android SDK + a real phone (the microphone service can't run in the web preview) | Mock trip screen in `mobile/` |
| Warning message wording | Team / pitch owner | Placeholder text |

## AI review of flagged rides

After a flagged ride's recording is uploaded, the backend reviews the **whole transcript** (`backend/app/services/review.py`) and stores `trips.recording.review`: a short summary in Bahasa Indonesia, a verified label with confidence, and the moments behind it, each citing a real transcript line. Phone numbers are masked before any model sees the text.

| Order | Reviewer | When |
|---|---|---|
| 1 | Sahabat-AI | `LLM_BASE_URL` points at an OpenAI-compatible server (vLLM, Ollama, or hosted) |
| 2 | Gemini | `GEMINI_API_KEY` is set; Google's OpenAI-compatible endpoint, `GEMINI_MODEL` (default `gemini-2.5-flash`) |
| 3 | Rules | Always available: the keyword filter; the review's `note` says why it fell back |

The review advises the agent and never decides. The dashboard shows it next to the phone's flag, says whether they agree, and reminds the agent that AI can be wrong.

## Agent case page

`dashboard/src/components/CaseView.tsx`, at `/incidents/{id}`. Desktop layout: recording and transcript on the left; the AI review, then the rider's and the driver's phone cards on the right (both columns end level); below them the decision across the full width, customer and driver as two separate blocks side by side. "Record decision" says what is still missing when it is off. The layout follows trust-and-safety review practice: everything for one case on one page, flagged content highlighted, reviewers jump to flagged moments instead of hearing whole rides, AI claims cite clickable evidence, and a little friction before deciding.

- **Queue** (`/`): Open and Closed tabs, search by ticket number or Order ID, and filters for priority, source (auto-detected, SOS, "I feel unsafe") and status. Priority comes from how the ticket was raised: SOS and auto-detected are **High**, "I feel unsafe" is **Warning** (the backend's `severity` is unchanged).
- **Header:** ticket number (`GS-XXXX-XXXX`, the incident ID without punctuation, first 8 characters; the same in emails), order ID, priority, trigger, status, time (WIB), and how the ticket was raised: automatically (`trigger: auto`, "the rider's/driver's phone flagged this ride") or by a person (SOS, which also emails them a ticket confirmation, or "I feel unsafe"). Opening an escalated case takes it (`under_review`, assigned to the agent).
- **Ride recording:** a waveform of the ride: played part green, unplayed grey, each flagged moment in its flag colour (warning amber, high red, SOS dark red, "I feel unsafe" orange) with a pin and a jump button. Click or use the arrow keys to seek; the bars at the playhead move while it plays. The waveform is decoded in the browser (Web Audio), so it appears only after the agent loads the audio. Audio loads only when the agent chooses to listen, through `GET /trips/{id}/recording-url`, which is audit-logged.
- **Transcript:** the whole ride, flagged lines in their flag colour; click a line to hear it. While audio plays the current line bounces once, fills a progress bar, and stays scrolled into view; lines already heard are muted.
- **Phone reports:** a card each for the rider's and the driver's phone: their name and phone number (`users.phone`, a `tel:` link so the agent can call), then the tickets that phone raised on this ride. Both phones listen, and every report joins the ride's one case, so the cards split `incident.reports` by who made each one (`by` against the trip's `riderId` / `driverId`), or say "No report from this phone on this ride".
- **AI review:** the reviewer (Sahabat-AI, Gemini or rules), the phone's flag next to the AI's reading and confidence, agree or differ, the summary, and "Why" moments as clickable timestamps.
- **Decision:** one choice for the customer (contact, or no action) **or** the driver (contact, warn, suspend, or no action), or both: the same for tickets a person raised (SOS, report) and automatic ones. A side left open means no action for that person; nothing chosen for either is a **dismiss**: the customer is told nothing needs further action and the driver gets nothing. Each side has an optional message that goes into that person's email. The rider always gets an email: "we'll contact you" if contacted, else "action taken" for a warning or suspension, else "following up" when the driver is contacted, else "no further action". The driver gets one for any driver decision except no action ("contact" says plainly it is not a warning). With a message the email is the short template plus "A message from the safety team"; without one it is the full template. Enabled only after the agent has played a flagged moment (or, without a recording, ticked that they read the report).

## Future work

- **Cloud speech-to-text and classification.** Send audio to an API (Chirp 3 `id-ID`, or a hosted IndoBERT) as a second opinion, or for phones too weak to run the models. Needs the GCP project and a way to configure it per phone, neither of which exists yet. `pipeline.transcribe` is the hook; it returns nothing today.

## Decisions (where the two source docs disagreed)

- **Severity rules for button reports** (`backend/app/services/pipeline.py`): Trigger `sos` (button, "I need help" or the safe phrase) → always high (escalate): a check-in would also ask the driver and give away a silent SOS. `threat` or `sexual_harassment` → high. Everything else → medium (check-in). If processing fails, an `sos` or `auto` case is still set to `escalated` (with `error`) so it reaches the agent queue. A person pressed the button, so the backend never dismisses these. Automatic reports only arrive at "high", so `dismissed` stays unused for now.
- **Classifier until IndoBERT lands:** an Indonesian keyword filter (`app/services/classify.py`). A `deviceLabel` from the phone always wins; the filter still marks `flagged` lines.
- **Summary until Sahabat-AI is hosted:** a template from the masked flagged lines (phone numbers masked; names not yet).
- **Retention:** 7 days by default, 30 days while a case is escalated, back to 7 days once closed.

- **The phone listens and judges** (replaces the earlier "backend decides severity, phone only on button press" plan). See "On-device listening". Button reports still go through the backend's severity rules.
- **No location data.** The app never records or sends GPS, location or route, and the backend stores none. A trip is identified by the GoJek order ID; GoJek already has the route, location and trip anomalies, and an agent looks them up there by order ID. `POST /trips/{id}/events` only stores SOS / manual-unsafe events with timestamps.
