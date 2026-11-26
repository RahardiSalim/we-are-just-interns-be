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

| Field | Type |
|---|---|
| `riderId`, `driverId` | uid |
| `mode` | `goride` \| `gocar` |
| `status` | `active` \| `ended` |
| `plannedRoute` | encoded polyline |
| `consent` | `{ rider: bool, driver: bool }` |
| `startedAt`, `endedAt` | timestamp |

Read by: rider, driver, agents.

## trips/{tripId}/events/{eventId}

| Field | Type |
|---|---|
| `type` | `gps` \| `stop` \| `deviation` \| `sos` \| `manual_unsafe` \| `checkin_sent` \| `checkin_reply` |
| `ts` | timestamp |
| `lat`, `lng` | number |
| `data` | map |

Read by: agents. (`stop` and `deviation` are kept in the enum but nothing produces them yet; see ARCHITECTURE.md Decisions.)

## incidents/{incidentId}

| Field | Type |
|---|---|
| `tripId` | string |
| `reportedBy` | uid |
| `trigger` | `sos` \| `manual_unsafe` |
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

## Retention

- Firestore TTL policy on `incidents.deleteAt`.
- Cloud Storage lifecycle rule deletes clips after 7 days.
- Open cases push `deleteAt` forward.

## Stretch

`socialPosts/{postId}`: `text`, `postedAt`, `matchedTripId`, `viralScore`.
