// Mirrors contracts/firestore-schema.md. Update both together.
import type { Timestamp } from "firebase/firestore";

export type IncidentStatus =
  | "awaiting_upload"
  | "processing"
  | "failed"
  | "dismissed"
  | "checkin_pending"
  | "resolved_ok"
  | "escalated"
  | "under_review"
  | "closed";

export type Severity = "low" | "medium" | "high";
export type Label = "normal" | "uncomfortable" | "sexual_harassment" | "threat";

export interface TranscriptLine {
  start: number;
  end: number;
  text: string;
  flagged: boolean;
}

export interface Incident {
  id: string;
  tripId: string;
  reportedBy: string;
  trigger: "sos" | "manual_unsafe";
  status: IncidentStatus;
  severity: Severity | null;
  label: Label | null;
  score: number | null;
  transcript: TranscriptLine[];
  summary: string | null;
  clipPath: string | null;
  source: "device" | "cloud";
  assignedAgent: string | null;
  createdAt: Timestamp;
  deleteAt: Timestamp;
}
