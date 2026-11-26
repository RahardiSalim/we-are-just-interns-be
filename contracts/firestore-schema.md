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
| `recordings` | `{ rider?, driver? }`: each phone's recording, only after a report, a high flag or an SOS; see below |
| `startedAt`, `endedAt` | timestamp |

Read by: rider, driver, agents.

### `trips/{tripId}.recordings.{rider|driver}`

One per phone, however many incidents the ride has. Every incident of the ride reaches it through `incidents.tripId`. The audio is in numbered pieces at `recordings/{tripId}/{rider|driver}/{n:06}.{aac|m4a|ogg|wav}`; ADTS pieces join byte for byte.

| Field | Type |
|---|---|
| `pieces` | number of audio pieces uploaded so far (numbered from 0) |
| `live` | bool: the phone is streaming (emergency) |
| `contentType` | `audio/aac` (ADTS, what the phone records) \| `audio/mp4` \| `audio/ogg` \| `audio/wav` |
| `durationSec` | number |
| `markers` | `[ { at, kind: warning \| high \| sos \| manual_unsafe, label, score, text } ]`: the phone's flags, `at` in seconds from the start of the recording |
| `transcript` | `[ { at, end, text } ]`: the phone's speech-to-text for the whole ride, seconds from the start |
| `status` | `uploading` \| `live` \| `uploaded` |
| `uploadedBy` | uid |
| `updatedAt` | timestamp |
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
| `trigger` | `sos` \| `manual_unsafe` (a report) \| `auto` (the phone's classifier hit the high threshold). The most urgent of all `reports` |
| `reports` | `[ { trigger, by, label, score, at } ]`: every report that joined this case, from either phone (one case per ride) |
| `live` | bool: a phone of this ride is streaming right now |
| `windowStart`, `windowEnd` | timestamp (the audio window the reporter flagged) |
| `status` | `awaiting_upload` \| `processing` \| `failed` \| `escalated` \| `under_review` \| `closed` |
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
- On the phone: every recorded ride is kept for 7 days, encrypted (30-second audio pieces plus its details), then deleted. Only a ride flagged high or with an SOS is uploaded; the rest never leave the phone.

## Stretch

`socialPosts/{postId}`: `text`, `postedAt`, `matchedTripId`, `viralScore`.
