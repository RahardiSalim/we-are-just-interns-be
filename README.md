# GoSafe

**Go easy, arrive safe.** Edge AI for GoRide and GoCar that hears when a ride goes wrong and gets help without a tap.

GoTo Hackathon 2026 · Team *We are just interns*: Rahardi Salim, Nur Adi Kusuma, Fadhil Muhammad, Akmal Ramadhan

## The problem

Every safety button in a ride-hailing app waits for the passenger to press it. In the worst minutes, she can't: her hands are busy, the phone is taken, or the order has already been closed. Most harassment is spoken, and spoken words leave no evidence. After the ride, a safety agent weighs two stories with no record, and a falsely accused driver has nothing to show either.

## What GoSafe does

During a ride, both the rider's and the driver's phones listen, transcribe and judge the conversation **on the phone**. A normal ride never leaves the phone.

| What happens in the car | What GoSafe does |
|---|---|
| Normal talk | Nothing. The recording stays on the phone, encrypted, and is deleted after 7 days. |
| Personal or uncomfortable questions | A kind nudge on the phone: "I'm fine" or "Report". Nothing is sent yet. |
| Harassment or a threat | The safety team is alerted at once and the phone asks "Are you okay?". No answer: the ride goes Live at 60 s, and an alarm sounds at 120 s. |
| The rider can't touch the phone | A secret safe phrase, or a shout for help, raises an SOS hands-free. |
| Any time | SOS and Report are always on screen. With no signal, SOS offers to call 112. |

A Gojek safety agent then reviews the case on the dashboard: they jump to the flagged moments on the recording, read an AI review that cites the exact lines, decide, and both rider and driver get the outcome by email. The AI only flags; a person decides.

## How it works

```
Rider & driver phones (Flutter, Android)
  mic → voice detection (Silero) → speech to text (Whisper, Indonesian) → classifier (IndoBERT-lite) → rules
  normal ride: stays on the phone, AES-256-GCM, deleted after 7 days
        │  only a flag + audio, after a serious flag, a report or an SOS
        ▼
FastAPI backend ── Firestore (cases, read live) ── Cloudflare R2 (audio, 10-minute signed links)
        │                    │
        │                    └── Agent dashboard (Next.js): queue, evidence, AI review, decision
        └── AI review (LLM, advises only) · outcome emails
```

- **Edge AI:** Whisper maleo base for Indonesian (82 MB), Silero voice detection (0.9 MB) and an IndoBERT-lite classifier (35 MB, ONNX) run inside the app, so speech is judged on the phone and works with no signal.
- **Privacy and security:** consent from both sides (the rider agrees, the driver turns on Safe Ride), no location data, recordings encrypted with an Android Keystore key, audio reachable only through short-lived signed links, and every playback logged.
- **One rule for the backend:** clients only read; every write goes through the API, which checks the login and role on every call.

## Measured so far

On our own scripted ride recordings (one speaker) and an Android emulator, not yet on real phones:

- 15 of 16 danger lines caught; 2 of 42 harmless lines raised anything
- 0 invented lines on 264 s of silence and noise
- 23.7 s of speech transcribed and judged in 6.1 s on the phone

## Repository

| Folder | What it is |
|---|---|
| [`mobile/`](mobile/README.md) | Flutter app for riders and drivers, with the edge AI models bundled in `assets/models/` |
| [`backend/`](backend/CLAUDE.md) | FastAPI service: incidents, recordings, AI review, emails |
| [`dashboard/`](dashboard/CLAUDE.md) | Next.js dashboard for Gojek safety agents |
| [`stt/`](stt/README.md) | Speech-to-text pipeline, evaluation harness and classifier training |
| [`contracts/`](contracts/ARCHITECTURE.md) | Architecture, API contract (`openapi.json`), Firestore schema, design tokens |
| `firebase/` | Firestore rules and indexes |
| `scripts/` | `demo.sh` runs everything locally for a demo |

## Run it

See [LOCAL_SETUP.md](LOCAL_SETUP.md). In short: `scripts/demo.sh` starts the Firebase emulators, seeds demo accounts, and runs the backend and dashboard on your laptop; then `flutter run` the app from `mobile/`.

## Demo

- Dashboard: https://we-are-just-interns-be.vercel.app/
- Android APK: built on demand by the `mobile` CI workflow
