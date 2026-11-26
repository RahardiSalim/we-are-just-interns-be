// Mirrors contracts/firestore-schema.md. Update both together.
import type { Timestamp } from "firebase/firestore";

export type IncidentStatus =
  | "awaiting_upload"
  | "processing"
  | "failed"
  | "dismissed"
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
  trigger: "sos" | "manual_unsafe" | "auto";
  status: IncidentStatus;
  severity: Severity | null;
  label: Label | null;
  score: number | null;
  transcript: TranscriptLine[];
  summary: string | null;
  clipPath: string | null;
  source: "device" | "cloud";
  /** A phone is streaming this ride to the agent right now (emergency). */
  live?: boolean;
  /** Every report that joined this case: one case per ride, from either phone. */
  reports?: { trigger: Incident["trigger"]; by: string; label: Label | null; score: number | null }[];
  assignedAgent: string | null;
  createdAt: Timestamp;
  deleteAt: Timestamp;
}

export type MarkerKind = "warning" | "high" | "sos" | "manual_unsafe";

/** A moment in the ride recording an agent should check (set by the phone). */
export interface Marker {
  at: number; // seconds from the recording start
  kind: MarkerKind;
  label?: Label | null;
  score?: number | null;
  text?: string | null;
}

/** One line of the phone's speech-to-text for the whole ride. */
export interface Utterance {
  at: number;
  end?: number | null;
  text: string;
}

/** Sahabat-AI (or Gemini, or rules) reading of the whole ride. Advice for the agent, never a verdict. */
export interface Review {
  source: "sahabat-ai" | "gemini" | "rules";
  model?: string;
  summary: string;
  label: Label;
  confidence: number;
  moments: { at: number; label: Label; reason: string }[];
  note: string | null;
}

/** One phone's recording of the ride, uploaded in numbered audio pieces. */
export interface Recording {
  contentType: string;
  durationSec: number;
  markers: Marker[];
  transcript: Utterance[];
  pieces: number;
  live: boolean;
  status: "uploading" | "live" | "uploaded";
  review?: Review | null;
}

export type Phone = "rider" | "driver";

export interface Trip {
  id: string;
  riderId: string;
  driverId: string;
  mode: "goride" | "gocar";
  status: "active" | "ended";
  consent: { rider: boolean; driver: boolean };
  recordings?: Partial<Record<Phone, Recording>>;
}
