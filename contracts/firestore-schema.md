# Firestore schema

Data truth for all three apps. Only the backend writes; clients read. Audio lives in Cloud Storage, never in Firestore. All timestamps are UTC server time.

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
| `consent` | `{ rider: bool, driver: bool }` |
| `startedAt`, `endedAt` | timestamp |

Read by: rider, driver, agents.

## trips/{tripId}

`tripId` is the GoJek order ID. No location, route or GPS is stored anywhere; GoJek holds those./events/{eventId}

| Field | Type |
|---|---|
| `type` | `sos` \| `manual_unsafe` \| `warning` (planned) |
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
| `clipPath` | Cloud Storage path |
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
| `action` | `view_clip` \| `decide` \| `appeal_review` |
| `ts` | timestamp |

Read by: agents. Written by: backend only.

## audioRequests/{requestId} (planned)

An agent asking a phone for audio it still holds (see ARCHITECTURE.md "On-device listening").

| Field | Type |
|---|---|
| `incidentId`, `tripId` | string |
| `userId` | uid of the phone's owner (one request per phone) |
| `requestedBy` | agent uid |
| `status` | `pending` \| `uploaded` \| `expired` (the phone had already deleted it, or never came online) |
| `clipPaths` | Cloud Storage paths, once uploaded |
| `requestedAt`, `uploadedAt` | timestamp |

Read by: agents; the phone owner reads their own. Written by: backend.

## Retention

- Firestore TTL policy on `incidents.deleteAt`.
- Cloud Storage lifecycle rule deletes clips after 7 days.
- Open cases push `deleteAt` forward.
- On the phones (not Firestore): all trip audio and transcripts, encrypted, deleted after 7 days.

## Stretch

`socialPosts/{postId}`: `text`, `postedAt`, `matchedTripId`, `viralScore`.
