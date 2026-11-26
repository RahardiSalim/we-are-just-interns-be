# Firestore schema

Data truth for all three apps. Only the backend writes; clients read. Audio lives in object storage (Cloudflare R2 when `R2_BUCKET` is set, otherwise Firebase Storage or its emulator), never in Firestore. All timestamps are UTC server time.

## users/{uid}

| Field | Type |
|---|---|
| `role` | `rider` \| `driver` \| `agent` (also set as a custom claim) |
| `displayName` | string |
| `fcmToken` | string |
| `audioConsent` | bool |
| `safeRideBadge` | bool |

Read by: owner, agents.

## trips/{tripId}

`tripId` is the GoJek order ID. No location, route or GPS is stored anywhere; GoJek holds those.

| Field | Type |
|---|---|
| `riderId`, `driverId` | uid |
| `mode` | `goride` \| `gocar` |
| `status` | `active` \| `ended` |
| `consent` | `{ rider: bool, driver: bool }`: rider from the consent prompt, driver from their Safe Ride setting (`users.audioConsent`) |
| `recording` | only after a ride with a high flag or SOS; see below |
| `startedAt`, `endedAt` | timestamp |

Read by: rider, driver, agents.

### `trips/{tripId}.recording`

One per ride, however many incidents the ride has. Every incident of the ride reaches it through `incidents.tripId`.

| Field | Type |
|---|---|
| `path` | object key of the audio, `recordings/{tripId}.m4a` (or `.ogg` / `.wav`) |
| `contentType` | `audio/mp4` \| `audio/ogg` \| `audio/wav` |
| `durationSec` | number |
| `markers` | `[ { at, kind: warning \| high \| sos \| manual_unsafe, label, score, text } ]`: the phone's flags, `at` in seconds from the start of the recording |
| `transcript` | `[ { at, end, text } ]`: the phone's speech-to-text for the whole ride, seconds from the start |
| `status` | `awaiting_upload` \| `uploaded` |
| `uploadedBy` | uid |
| `createdAt`, `uploadedAt` | timestamp |
| `review` | written after upload: `{ source: sahabat-ai \| gemini \| rules, model, summary, label, confidence, moments: [ { at, label, reason } ], note, createdAt }`. Phone numbers are masked; every `moments.at` is a real transcript line |

## trips/{tripId}/events/{eventId}

| Field | Type |
|---|---|
| `type` | `sos` \| `manual_unsafe` |
| `ts` | timestamp |
| `data` | map (for `warning`: `{label, score, by}`) |

Read by: agents.

## incidents/{incidentId}

| Field | Type |
|---|---|
| `tripId` | string |
| `reportedBy` | uid |
| `trigger` | `sos` \| `manual_unsafe` \| `auto` (the phone's classifier hit the high threshold) |
| `windowStart`, `windowEnd` | timestamp (the audio window the reporter flagged) |
| `status` | `awaiting_upload` \| `processing` \| `failed` \| `dismissed` \| `checkin_pending` \| `resolved_ok` \| `escalated` \| `under_review` \| `closed` |
| `severity` | `low` \| `medium` \| `high` |
| `label` | `normal` \| `uncomfortable` \| `sexual_harassment` \| `threat` |
| `score` | number 0–1 |
| `transcript` | `[ { start, end, text, flagged } ]` (seconds from window start) |
| `summary` | string (LLM, escalations only) |
| `clipPath` | object storage key of the reporter's clip, if any |
| `source` | `device` \| `cloud` |
| `assignedAgent` | uid |
| `decision` | `{ action: dismiss \| warn_driver \| suspend_driver \| contact_rider, note, agentId, ts }` |
| `createdAt`, `deleteAt` | timestamp |
| `error` | string, only when `status` is `failed` |

Read by: reporter (own, limited fields), agents.

## checkins/{checkinId}

| Field | Type |
|---|---|
| `incidentId` | string |
| `userId` | uid |
| `status` | `sent` \| `ok` \| `need_help` \| `no_reply` |
| `required` | bool: false for a GoRide driver, whose silence never escalates |
| `sentAt`, `repliedAt` | timestamp |

Read by: that user, agents.

## auditLogs/{logId}

| Field | Type |
|---|---|
| `agentId` | uid |
| `incidentId` | string |
| `action` | `view_clip` \| `view_recording` \| `decide` \| `appeal_review` |
| `tripId` | string, for `view_recording` |
| `ts` | timestamp |

Read by: agents. Written by: backend only.

## Retention

- Firestore TTL policy on `incidents.deleteAt`.
- Object storage: a lifecycle rule deletes clips after 7 days (on R2, set it in the bucket's Object Lifecycle Rules).
- Open cases push `deleteAt` forward.
- On the phone: the ride recording is deleted after the ride unless it was flagged high or had an SOS, in which case it's uploaded and then deleted from the phone.

## Stretch

`socialPosts/{postId}`: `text`, `postedAt`, `matchedTripId`, `viralScore`.
