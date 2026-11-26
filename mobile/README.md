# GoSafe mobile app: technical and logic guide

The mobile app is the core of GoSafe. It runs on the consumer's phone. During a ride it records, turns speech into text, judges the conversation and responds, all on the phone. The backend only receives what the phone sends: flags during the ride, and the full recording after a serious one.

This guide describes the app as it is built today. The product decisions behind it are in [contracts/ARCHITECTURE.md](../contracts/ARCHITECTURE.md), section "On-device listening".

## Status

| Part | State |
|---|---|
| Start ride, consent prompt, no login (anonymous sign-in) | Built |
| Microphone recording for the whole ride | Built (`record` package, AAC on Android, WAV in the browser preview) |
| Decision engine (15 s window, classifier, rules) | Built and tested |
| Warning, high flag sent at once, "Are you okay?", SOS, Report driver / passenger | Built and tested |
| Rider and driver on the same app (switch on the home screen, demo only) | Built and tested (driver mode not yet run on a device) |
| Share levels: local, at end, live (see "What leaves the phone, and when") | Built and tested; Live tested on the Android emulator |
| Every ride kept on the phone for 7 days, encrypted, in 30-second pieces (10-second when Live) | Built and tested |
| SOS with no signal: offers 112, retries until sent | Built and tested |
| Voice detection, speech-to-text | **Temporary**: a scripted conversation stands in |
| Classifier | **Temporary**: an Indonesian keyword filter stands in for IndoBERT |
| Recording in the background | Built: a microphone foreground service ("GoSafe is keeping this ride safe") keeps recording and listening with the screen locked. Tested on the Android emulator |
| High flag check, quiet first | Built: vibration every 10 s; Live at 60 s with no answer; loud alarm and "shout TOLONG" at 120 s. No Firebase needed: the service keeps the app alive during the ride. Tested on the Android emulator |
| Encryption on the phone | Built: every 30-second piece and the ride's details are AES-256-GCM encrypted with an Android Keystore key as they're saved, and decrypted only to upload |
| Push when the app is fully closed | Not built: needs FCM and a real Firebase project. During a ride the service keeps the app open, so it isn't needed then |

## How one ride works

```mermaid
flowchart TD
    A[Open the app: signed in silently] --> B[Tap Start ride]
    B --> C{Consent prompt: Keep this ride safe?}
    C -- Not now --> D[Ride without recording. SOS still works]
    C -- Yes, record --> E{Driver has Safe Ride on?}
    E -- No --> D
    E -- Yes --> F{Microphone allowed?}
    F -- No --> D
    F -- Yes --> G[Record and listen for the whole ride]
    G --> H[Tap End ride]
    D --> H
    H --> I{Share level of the ride}
    I -- Local --> K[Nothing leaves the phone]
    I -- At end --> J[Upload every piece, transcript and flags. No signal: retry every minute]
    I -- Live --> J2[Already streamed: send the last piece and close]
    J --> L[Kept encrypted on the phone for 7 days, then deleted]
    J2 --> L
    K --> L
```

- **No login.** Each install signs in anonymously in the background, so the backend still knows whose ride and report it is. In the real product the GoJek app's own login replaces this.
- **Rider or driver.** A switch on the home screen picks whose phone this is (demo only; in production these are two apps). The rider is asked for consent; the driver isn't, because their **Safe Ride** switch is their consent. The driver's phone joins the rider's ride (`POST /trips` with `role: driver`), so the rider must start first.
- **The driver decided earlier.** Drivers turn recording on or off in their own settings. Turning it on gives them the **Safe Ride badge**, which the consumer sees during the ride ("Your driver has Safe Ride on"). If the driver left it off, nothing is recorded.
- **No location.** The app never asks for location permission. A ride is identified by the GoJek order ID; for the demo the backend generates one.

## What leaves the phone, and when

Each ride has a **share level** that only goes up: **local → at end → live**.

| What happened | You answer | Level | What leaves the phone |
|---|---|---|---|
| Nothing | | Local | Nothing. Kept encrypted on the phone 7 days |
| Warning (medium) | "I'm fine", or ignore it | Local | Nothing. The flag is kept on the phone with the ride |
| Warning, or any time | **Report driver** (or passenger) → "I'm safe for now" | At end | The report goes now (`manual_unsafe`). When the ride ends: every audio piece, the transcript and every flag |
| Warning, or any time | **Report driver** → **Yes, get help** | Live | An SOS, and Live (below) |
| High flag | "I'm okay" | At end | The flag went to an agent at once. When the ride ends: the whole ride |
| High flag | "I need help" | Live | An SOS, and Live |
| High flag | no answer | Live at 60 s | See the timeline below |
| Any time | SOS button, the safe phrase, or a shout for help | Live | An SOS, and Live |

**Live** means: at once, every audio piece so far, the transcript and the flags; then a new 10-second piece and the new lines every 10 seconds until the ride ends. The case is marked **LIVE** at the top of the agents' queue, and the agent can listen while the ride goes on.

**A high flag nobody answers** (quiet first, so the phone doesn't give the user away):

| Time after the flag | Phone | Agent |
|---|---|---|
| 0 s | The flag is sent. "Are you okay?" on screen, and a **silent** notification that only vibrates | The case appears, high priority |
| every 10 s | Another vibration | |
| 60 s | Goes **Live** (still silent) | LIVE badge; the agent can listen and call the rider |
| 120 s | The **loud alarm** (repeats until answered), and on screen: "If you're in danger, shout TOLONG. Our safety team is listening." Hearing "tolong" or "help" now counts as "I need help" | |

Answering at any point stops the buzzing or the alarm. "tolong" only counts during the alarm, so "tolong belok kiri" in normal talk does nothing.

**One case per ride.** The rider's and the driver's phones can both report the same ride; the backend joins every report into one case and makes it high priority if any of them is an SOS or a high flag. Each phone keeps and uploads its own recording, and the agent can play either.

## What the phone stores, and when

Each recorded ride gets a folder in the app's private storage, `rides/<order ID>/`. Every file in it is encrypted (AES-256-GCM, with a key that lives in the Android Keystore and never leaves the phone). Nothing is stored for a ride that isn't recorded.

| When | What is written | File |
|---|---|---|
| "Yes, record" and the mic starts | The ride's details: order ID, start time, audio format | `meta.enc` |
| Every line heard | That line and its time from the start | `meta.enc` (rewritten) |
| Every warning, high flag, SOS or report | A marker: time, kind, label, score, the line | `meta.enc` (rewritten) |
| Every 30 seconds (10 when Live) | The latest audio (AAC, ADTS frames) | `000000.aac.enc`, `000001.aac.enc`, … |
| A piece uploaded | How many pieces are up | `meta.enc` |
| End ride | The last piece, the length, "ended" | the next piece, `meta.enc` |
| Upload succeeded | "uploaded" | `meta.enc` |
| App start, then every minute | Rides older than 7 days are deleted. Unfinished rides from a crash are closed. Flagged rides not yet sent are uploaded | |

Why pieces: if the app is killed, the phone restarts or the battery dies, the ride up to the last 15 seconds is already saved and encrypted. ADTS pieces join byte for byte, so the upload is one file.

## When things go wrong

| Situation | What happens |
|---|---|
| SOS with no signal | A red banner: "We can't reach our safety team right now. We'll keep trying. If you are in danger, call 112." with a **Call 112** button (opens the dialer with 112 filled in; the rider presses call). The app retries the SOS every 5 to 10 seconds until it goes through, then shows "We're on it" |
| High flag or a report with no signal | Retried in the background, waiting longer each time (up to a minute) |
| End ride with no signal | The recording stays queued: "We'll send the recording to our safety team as soon as you're online." Retried every minute while the app is open, for up to 7 days |
| App killed or phone off mid-ride | Pieces up to the last 15 seconds are saved. At next launch the ride is closed (its length taken from the last line or marker) and, if it was flagged, uploaded |
| Alarm, phone call, music, or a Bluetooth headset disconnecting during the ride | Recording continues (`audioInterruption: none`, `audioRouteChange: follow`) |
| App reinstalled | The Keystore key is gone, so old rides can't be opened; they're deleted |

## Hands-free SOS: the safe phrase

On a motorbike, tapping SOS is the hard part. The rider or the driver can say a natural-sounding sentence instead, by default **"Pak, nanti lewat jalan biasa aja ya"**. When speech-to-text hears it, the phone sends an SOS **silently**: no dialog and no alarm the driver could notice. The backend always escalates an SOS straight to an agent, and never sends a check-in that would reach the driver.

- **No model needed.** It matches the speech-to-text output (`lib/engine/safe_phrase.dart`): words are lower-cased and stripped of punctuation, then compared word by word, allowing one slip per six words (a word missed, or a word one letter off, like "aja" → "saja" or "ya" → "yah"). The phrase can sit inside a longer sentence.
- **Once per ride.** Saying it again doesn't send a second SOS.
- **Setting it:** each person sets their own, rider and driver alike: **Safe phrase → Set / Change** on the home screen. It's kept on the phone, encrypted like the rides (`safe_phrase.enc`), never sent anywhere. 4 to 12 words; shorter phrases are refused because they'd fire by accident. Until one is set, the default is `--dart-define=SAFE_PHRASE=...` ("Pak, nanti lewat jalan biasa aja ya").
- **Demo:** `flutter run --dart-define=DEMO_SCRIPT=safe_phrase` plays a short ride where the rider says the phrase.
- **Limits:** it only works as well as speech-to-text hears the rider on a moving motorbike, which needs testing with the real model. Pick a phrase that's rare in normal rides, so it never fires by accident.

## The listening pipeline

```mermaid
flowchart LR
    M[Microphone, whole ride] --> REC[(Ride recording)]
    M -.-> V[Voice detection]
    V -.-> S[Speech-to-text per utterance]
    S --> W[15-second window]
    W --> K[Classifier: label + score]
    K --> E[Decision rules]
    E --> R{Action}
    R -- none --> X[Keep listening]
    R -- warn --> Y[Kind warning on screen, marked in the recording]
    R -- high --> Z[Flag sent to the backend at once + Are you okay?]
```

The microphone really records. Voice detection and speech-to-text (the dotted part) are still in the making, so `mock_listener.dart` stands in: it plays a scripted Indonesian conversation, one line every 3 seconds. Everything from the window onwards is the real logic.

### Step 1: the 15-second window

Every finished utterance is added to a list with the time it was heard. Lines older than 15 seconds are dropped. The classifier always judges the whole window, so a remark is read in context. When the phone sends a flag, this window is the evidence; each line's `start` and `end` are seconds from the first line in the window.

### Step 2: the classifier (temporary keyword filter)

`KeywordClassifier` looks for Indonesian phrases, including Jakarta slang, in three groups:

| Label | Example phrases |
|---|---|
| `threat` | bunuh, pukul, hajar, pisau, culik, "diem aja", "jangan banyak tanya", "tahu rumah", "jangan lapor" |
| `sexual_harassment` | "cantik banget", seksi, pegang, cium, raba, "ke hotel", "mampir ke tempat", "tempat saya", "buka baju" |
| `uncomfortable` | "tinggal sendiri", sendirian, "punya pacar", "rumahnya di mana", "minta nomor", "umur berapa", sayang |

How it scores the window:

- It counts every matched **phrase** in the window, per label. Two phrases in one sentence count as two.
- The window gets the most severe label that has any match, in the order threat, sexual harassment, uncomfortable. No match means `normal`.
- Score = 0.5 + 0.15 × (number of phrases for that label), capped at 0.95. A `normal` window scores 0.5.
- Each line is marked `flagged` if it contains any phrase. The dashboard highlights flagged lines.

### Step 3: the decision rules

`SafetyEngine` turns each verdict into one action. It checks in this order:

1. **Already flagged high on this ride?** Then do nothing more. A person at customer service has the case. Warnings stop too.
2. **High:** the label is `threat` or `sexual_harassment` and the score is at least **0.8**.
3. **Warning:** any label other than `normal`, a score of at least **0.6**, and no warning in the last **10 minutes**.
4. Otherwise, nothing.

| Setting | Value today | Who sets the real value |
|---|---|---|
| Warning threshold | 0.6 | Modelling team, from their test set |
| High threshold | 0.8 | Modelling team, from their test set |
| Window | 15 s | Fixed by the design |
| Warning cooldown | 10 min | Fixed by the design |

What that means with the keyword filter:

| Heard within 30 s | Score | Result |
|---|---|---|
| Ordinary talk | 0.50 | Nothing |
| One uncomfortable phrase ("Udah punya pacar belum?") | 0.65 | Warning |
| One harassment phrase | 0.65 | Warning only |
| Two harassment phrases ("Cantik banget sih, nanti mampir ke tempat saya") | 0.80 | High |
| One threat phrase | 0.65 | Warning |
| Two threat phrases | 0.80 | High |

### The demo conversation, step by step

| Time | Line | What happens |
|---|---|---|
| 3 s | Selamat sore Mbak, sesuai aplikasi ya, ke Senayan. | Nothing |
| 6 s | Iya Pak, lewat Sudirman aja. | Nothing |
| 9 s | Mbak kerja di mana? Udah punya pacar belum? | **Warning** (uncomfortable, 0.65), marked |
| 12 s | Hmm, Pak, fokus nyetir aja ya. | Nothing |
| 15 s | Tinggal sendiri ya? Rumahnya di mana? | Nothing (warning cooldown) |
| 18 s | Cantik banget sih, nanti mampir ke tempat saya dulu. | **High** (sexual harassment, 0.80): flag sent, "Are you okay?" |
| 21 s | Pak, saya mau turun di depan aja. | Nothing (already flagged) |

At "End ride", this ride had a high flag, so the full recording uploads with two markers: the warning at 9 s and the high flag at 18 s.

## What the person sees

Every message is short and caring, never alarming. All the wording lives in one place, `SafetyText` in `lib/features/safety/are_you_ok.dart`.

| Moment | Message | Buttons |
|---|---|---|
| Start ride | **Keep this ride safe?** "We'd like to record audio during this ride. It's only reviewed if something seems wrong, and it's deleted after 7 days." | Not now / Yes, record |
| Warning | "Hey, this conversation seems to be getting uncomfortable. Let's keep it kind. If you feel unsafe, we're right here." | I'm fine / Report |
| High flag | **Are you okay?** "Something didn't sound right, so we've let our safety team know. Tap if you need help." | I'm okay / I need help |
| "I need help" or SOS | "We're on it. Our safety team will contact you right away." | |
| "I'm okay" | "Glad you're okay. We're still here if anything changes." | |
| Report driver / Report passenger | **We've reported this driver** (or passenger) "Our safety team will review this ride. Do you need help right now?" | I'm safe for now / Yes, get help |
| "I'm safe for now" | "Thanks for telling us. We'll look into it after your ride." | |
| Live | "Our safety team is following this ride live." | |
| High flag unanswered for 120 s | "If you're in danger, shout TOLONG. Our safety team is listening." | |
| End of a flagged ride | "Ride ended. The recording was sent to our safety team." | |
| End of a flagged ride, no signal | "Ride ended. We'll send the recording to our safety team as soon as you're online." | |
| End of any other ride | "Ride ended. Nothing needed checking. The recording stays locked on this phone for 7 days, then it's deleted." | |
| SOS with no signal | "We can't reach our safety team right now. We'll keep trying. If you are in danger, call 112." | Call 112 |
| Screen locked, high flag | Notification **Are you okay?** "Something didn't sound right. Tap to tell us you're okay." Vibration only for 2 minutes, then the alarm sound | Tap opens the app |
| During the ride | Ongoing notification "GoSafe is keeping this ride safe" | |

These messages appear in a card at the **top** of the screen, never as a pop-up at the bottom: nothing may cover the SOS button. SOS, Report and "End ride" stay pinned at the bottom, and everything above them scrolls.

## What the phone sends, and when

**During the ride, at once.** Only what needs a person now:

| `trigger` | Sent when | What the backend does |
|---|---|---|
| `auto` | The engine reached "high" | Escalates straight away: the highest priority for customer service |
| `sos` | SOS button, "I need help", or the safe phrase heard | Always escalates at once, never a check-in (a check-in would also ask the driver, which would give away a silent SOS). If processing fails, it's still escalated so an agent sees it |
| `manual_unsafe` | Report driver / passenger, or Report on a warning | Goes to an agent as medium priority (high if the label is harmful). Nobody else is asked anything |

Each one is `POST /incidents`, then `POST /incidents/{id}/finalize`, with the phone's evidence. If the ride already has an open case, the report joins it (`merged: true`) and there's nothing to finalize:

```json
{
  "tripId": "GR-8FBA186A",
  "trigger": "auto",
  "windowStart": "2026-11-26T08:59:12Z",
  "windowEnd": "2026-11-26T08:59:34Z",
  "deviceTranscript": [
    {"start": 6, "end": 10, "text": "Mbak kerja di mana? Udah punya pacar belum?"},
    {"start": 15, "end": 19, "text": "Cantik banget sih, nanti mampir ke tempat saya dulu."}
  ],
  "deviceLabel": "sexual_harassment",
  "deviceScore": 0.8
}
```

Warnings are **not** sent during the ride. They stay on the phone as markers.

**The recording (at end, or live).** One phone's recording, in pieces:

1. `PUT /trips/{id}/recording` with the details: `durationSec`, `contentType` (`audio/aac`), `markers`, `transcript`, `pieces` (how many are up), `live`, `done`.
2. For each piece not sent yet: `POST /trips/{id}/recording/pieces/{n}` gives an upload URL; the phone uploads the piece there. Sending a piece twice overwrites it, so retries are safe.
3. `PUT /trips/{id}/recording` again with the new `pieces` count. Live repeats this every 10 seconds; the last call has `done: true`, which starts the AI review.

```json
PUT /trips/GR-8FBA186A/recording
{
  "durationSec": 25.0, "contentType": "audio/aac", "pieces": 2, "live": false, "done": true,
  "markers": [
    {"at": 9.0, "kind": "warning", "label": "uncomfortable", "score": 0.65, "text": "Mbak kerja di mana? Udah punya pacar belum?"},
    {"at": 18.0, "kind": "high", "label": "sexual_harassment", "score": 0.8, "text": "Cantik banget sih, nanti mampir ke tempat saya dulu."}
  ],
  "transcript": [
    {"at": 3.0, "text": "Selamat sore Mbak, sesuai aplikasi ya, ke Senayan."},
    {"at": 6.0, "text": "Iya Pak, lewat Sudirman aja."}
  ]
}
```

The backend refuses a recording with no `high`, `sos` or `manual_unsafe` marker, so this privacy rule also holds if the app has a bug. Agents get links to every piece with `GET /trips/{id}/recording-urls` (logged), and the dashboard joins them to play.

Other calls: `POST /trips` (with `riderConsent`, or `role: driver`), `POST /me/consent` (the driver's Safe Ride switch) and `POST /trips/{id}/end`. The app reads one thing straight from Firestore: the ride's consents.

## Privacy rules the code follows

- Nothing is recorded unless the consumer said yes **and** the driver has Safe Ride on.
- No location: no permission, no GPS, no route.
- During the ride only high flags and button presses leave the phone, plus the recording itself when the ride is Live (an emergency).
- A recording leaves the phone only after a report, a high flag or an SOS. Any other ride never leaves the phone.
- Every ride is kept on the phone for 7 days (as the consent prompt says), in the app's private folder, encrypted piece by piece as it's recorded (the key never leaves the Android Keystore). After 7 days it's deleted, sent or not. The app has no playback or export.
- While recording, Android always shows the "GoSafe is keeping this ride safe" notification: listening is never hidden.
- A person at customer service reviews every case. The app never warns, suspends or bans a driver on its record.

## Code map

| File | Job |
|---|---|
| `lib/main.dart` | Starts Firebase (pointed at the emulators), signs in anonymously (fresh each launch in emulator mode), builds the ride screen with the real API, microphone and Firestore |
| `lib/theme.dart` | Design tokens and the app theme from [contracts/DESIGN.md](../contracts/DESIGN.md) (`GoSafeColors`, `GoSafeType`, `goSafeTheme`) |
| `lib/features/trip/trip_screen.dart` | The ride: start, consent, recording, listening, every response, and the upload decision at the end |
| `lib/features/safety/are_you_ok.dart` | All the wording (`SafetyText`), the consent prompt and the "Are you okay?" dialog |
| `lib/engine/safety_engine.dart` | The 15-second window, the decision rules, and `Marker` |
| `lib/engine/classifier.dart` | The `Classifier` interface and the temporary keyword filter |
| `lib/services/recorder.dart` | Microphone recording for the whole ride as a stream, saved in 30-second pieces (`TripRecorder`: start, stop) |
| `lib/services/ride_store.dart` | `RideMeta` (a ride's details), the `RideStore` interface, `tidy` (the 7-day rule), and an in-memory store for the web preview and tests |
| `lib/services/file_ride_store.dart` | The on-phone store: one folder per ride, every file sealed through `Vault` |
| `lib/services/ride.dart` | The channel to the Android side: listening service, alerts, dialer, seal and open |
| `android/app/src/main/kotlin/com/gosafe/gosafe/` | `MainActivity` (the channel), `RideService` (foreground service and `Alerts` notification channels), `Vault` (Keystore AES-GCM) |
| `lib/services/api.dart` | Calls to the backend, including the recording upload |
| `lib/services/mock_listener.dart` | The scripted conversation standing in for voice detection and speech-to-text |

## Swapping in the real models

Two interfaces keep the stand-ins replaceable without touching the screen or the engine:

- **Speech:** `TripScreen.listen` is a `Stream<String> Function()`, one finished utterance per item. Replace `scriptedListener` with a sherpa_onnx listener that runs Silero voice detection, then Whisper on each utterance. It can read the same microphone audio the recorder captures.
- **Classifier:** `Classifier.classify(List<String> lines)` returns a label, a score and per-line flags. Replace `KeywordClassifier` with IndoBERT in ONNX Runtime, plus a Dart port of its tokenizer.

Then set the real thresholds in `SafetyEngine`.

## Tests

`flutter test` runs 30 tests with no backend needed.

| File | Covers |
|---|---|
| `test/engine_test.dart` | Classifier labels, flags and scores. Engine: ordinary talk, warning and cooldown, high once per ride, the 15-second window, a threat below the high threshold |
| `test/trip_screen_test.dart` | Consent yes starts recording and listening; "Not now" records nothing and SOS works; no recording without Safe Ride or the mic; a warning ignored stays on the phone; a report sends at end, and "Yes, get help" goes Live; a high flag answered okay sends at end, "I need help" goes Live; a high flag nobody answers buzzes, goes Live at 60 s, alarms at 120 s, and a shout sends SOS; "tolong" in normal talk does nothing; offline uploads retry; a killed ride is closed and sent; rides over 7 days are deleted; SOS offline offers 112; the safe phrase sends a silent SOS and goes Live; driver mode joins with no consent prompt; a driver with no ride waiting is told |
| `test/file_ride_store_test.dart` | Pieces are counted and read back by number; details round-trip (role, share level, pieces sent); a deleted ride leaves no folder; unreadable details are dropped |

## Testing with a real voice (laptop models)

Until Whisper and the classifier run on the phone, the web app can use them on the laptop: `stt/dev_server.py` runs Akmal's speech-to-text pipeline (Silero voice detection, Whisper maleo small, the hallucination filter) and the team's DistilBERT classifier.

1. Put the models in `stt/models/` (git-ignored): `maleo-small-id-q8_0/ggml-small-id-q8_0.bin` (see `stt/models/README.md`) and `classifier/` (from `gosafe-classifier-distilbert-11.zip`).
2. From `stt/`: `uv run --no-project --python 3.12 --with numpy --with scipy --with soundfile --with pywhispercpp --with torch --with transformers --with safetensors --with silero-vad python dev_server.py --port 7088 --whisper models/maleo-small-id-q8_0/ggml-small-id-q8_0.bin --classifier models/classifier` (add `--save-dir <folder outside the repo>` to keep every received piece for replay).
3. From `mobile/`: `flutter run -d chrome --dart-define=DEV_ML=http://localhost:7088`, or `flutter build web --dart-define=DEV_ML=http://localhost:7088` and serve `build/web`.

How it works (`lib/services/dev_ml.dart`):
- The mic is sent in **15-second pieces**. A sentence still going at the end of a piece is carried into the next one, so it's never cut.
- Each line shows the classifier's raw label next to it, e.g. `CONTACT_SOLICIT 0.99`.
- **Classifier rule:** the keywords decide on their own; the team model alone can only add a warning, and only at 0.9 or more (it isn't validated: about 11% of friendly chat gets a harmful label); where both agree, the higher score counts. Its 11 labels map onto the app's 4 in `devLabelMap` (our mapping; the team should confirm it).
- **Keywords** allow Indonesian suffixes ("buka bajunya") and include swear words (uncomfortable: a warning, never high) and slurs (sexual harassment).
- The service prints KEPT or DROP for every segment. It keeps real speech before an invented YouTube outro ("like share dan subscribe") instead of dropping the whole segment.
- Web only: on Android the ride recorder and this listener would compete for the mic.

## Speech-to-text on the phone (experiment)

The scripted conversation can be replaced by real speech-to-text that runs **inside the app**: whisper.cpp through the `whisper_ggml` package, with the same Indonesian model the benchmark picked (`maleo-ai/whisper-small-id`, ggml q8_0, see `stt/models/README.md`). It is off unless `WHISPER_MODEL` is set, so nothing changes by default. The words are judged by the app's own classifier (the keyword filter), not the team model.

| Flag | What it does |
|---|---|
| `--dart-define=WHISPER_MODEL=<path>` | The ggml file **on the phone**. Turns the feature on. The model (264 MB) is not in the app or the repo |
| `--dart-define=WHISPER_VAD=<path>` | Optional Silero ggml file (about 1 MB) so silence never reaches the decoder and sentences split at pauses. Not tried yet |
| `--dart-define=WHISPER_TEST_WAV=<path>` | Hear a 16 kHz mono WAV instead of the microphone, to test without a mic |
| `--dart-define=WHISPER_CHUNK_SECS=6` | Audio is decoded in pieces this long. Shorter shows words sooner and works the phone harder |

On an emulator (debug build) the app can only read its own private folder, so copy the files in with `adb push` to `/data/local/tmp/`, then `adb shell run-as com.gosafe.gosafe cp ... files/` and use `/data/user/0/com.gosafe.gosafe/files/<file>` in the flags.

`lib/services/on_device_stt.dart` holds it: the microphone is read on its own while pieces are decoded, a sentence still going at the end of a piece is carried into the next, and `SpeechFilter` is the hallucination filter of `stt/stt_service.py` ported to Dart (invented "like dan subscribe" outros, `[BLANK_AUDIO]`, loops like "hai hai hai"; a line with "tolong" is never dropped as a loop). The log shows `mic level`, `decoded Xs of audio in Y ms` and each line as KEPT or DROP.

What this does **not** show: speed, memory and battery on a real phone were not measured. The only run was on an arm64 emulator on a Mac laptop, where a 6 s piece took 3 to 5 s to decode, with one 31 s spike on a looping piece. It also does not mask phone numbers, plates or emails (the Python module does), and the score Whisper gives for "no speech" is not available, so the filter is weaker than the Python one.

## Running it

Start the emulators, seed data and backend as described in the root [CLAUDE.md](../CLAUDE.md), under "Run everything locally". Then, from `mobile/`:

| Target | Command | Microphone |
|---|---|---|
| Chrome | `flutter run -d chrome` | Works; Chrome asks for permission |
| Android emulator | `flutter run` (reaches this Mac at `10.0.2.2`) | Uses the Mac's microphone. If the emulator freezes when recording starts (macOS mic prompt), start it with `-no-audio`: it records silence |
| Real phone, same Wi-Fi | Run `scripts/demo.sh` from the repo root, then the `flutter run` line it prints | Works |

Claude Code's browser pane blocks microphones, so there the app takes the "not recording" path.

### Against a real Firebase project and a deployed backend

The app talks to the emulators unless told otherwise. For a real project (for example the demo's `gosafe-hackathon` with the backend on Render) pass the project's public client settings; there is no `google-services.json` to add:

```bash
flutter run \
  --dart-define=USE_EMULATORS=false \
  --dart-define=API_URL=https://<backend host> \
  --dart-define=FIREBASE_PROJECT_ID=<project id> \
  --dart-define=FIREBASE_API_KEY=<Android app API key> \
  --dart-define=FIREBASE_APP_ID=<Android app id, 1:<number>:android:<hash>> \
  --dart-define=FIREBASE_SENDER_ID=<project number>
```

Take the values from Firebase console > Project settings > Your apps > the Android app (package `com.gosafe.gosafe`), or `firebase apps:sdkconfig ANDROID <app id> --project <project id>`. The same flags work for `flutter build apk`. Anonymous sign-in must be enabled in Firebase Authentication. Without these flags the app keeps using the offline `demo-gosafe` emulator project.
