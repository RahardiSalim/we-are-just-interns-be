import type { Incident, IncidentStatus, Label, MarkerKind } from "@/types/firestore";

export const labelText: Record<Label, string> = {
  normal: "Normal",
  uncomfortable: "Uncomfortable",
  sexual_harassment: "Sexual harassment",
  threat: "Threat",
};

export const triggerText: Record<Incident["trigger"], string> = {
  sos: "SOS",
  manual_unsafe: "Reported",
  auto: "Auto-detected on phone",
};

/** One colour per flag kind (contracts/DESIGN.md "Safety meaning"), for pins, chips and transcript lines alike. */
export const kindStyle: Record<MarkerKind, { text: string; dot: string; chip: string; line: string }> = {
  warning: { text: "Warning", dot: "bg-warn", chip: "bg-warn-tint text-fg", line: "border-warn bg-warn-tint" },
  high: { text: "High flag", dot: "bg-high", chip: "bg-high-tint text-fg", line: "border-high bg-high-tint" },
  sos: { text: "SOS", dot: "bg-sos", chip: "bg-sos-tint text-fg", line: "border-sos bg-sos-tint" },
  manual_unsafe: { text: "I feel unsafe", dot: "bg-unsafe", chip: "bg-unsafe-tint text-fg", line: "border-unsafe bg-unsafe-tint" },
};

/** Status as agents say it, with a pill colour (GoCorp-style "● Active"). */
export const statusStyle: Partial<Record<IncidentStatus, { text: string; dot: string }>> = {
  escalated: { text: "Waiting for an agent", dot: "bg-brand" },
  under_review: { text: "In review", dot: "bg-warn" },
  closed: { text: "Closed", dot: "bg-muted" },
};

export const mmss = (sec: number) =>
  `${String(Math.floor(sec / 60)).padStart(2, "0")}:${String(Math.floor(sec % 60)).padStart(2, "0")}`;

export const wib = new Intl.DateTimeFormat("id-ID", { timeZone: "Asia/Jakarta", dateStyle: "medium", timeStyle: "short" });

const harmful = new Set<Label>(["threat", "sexual_harassment"]);
export const isHarmful = (l: Label | null | undefined) => !!l && harmful.has(l);

/** GS-XXXX-XXXX from the incident ID: the same number the customer sees in emails (backend `ticket_number`). */
export const ticketNo = (id: string) => {
  const code = id.replace(/[^a-z0-9]/gi, "").toUpperCase();
  return `GS-${code.slice(0, 4)}-${code.slice(4, 8)}`;
};

/** Priority by how the ticket was raised: SOS and auto-detected are high, a report ("I feel unsafe") is a warning. */
export type Priority = "high" | "warning";
export const priorityOf = (i: Incident): Priority => (i.trigger === "manual_unsafe" ? "warning" : "high");
export const priorityStyle: Record<Priority, { text: string; badge: string }> = {
  high: { text: "High priority", badge: "bg-high text-white" },
  warning: { text: "Warning", badge: "bg-warn text-ink" },
};

/** Queue order: high priority first, then newest. */
export const byPriority = (a: Incident, b: Incident) =>
  Number(!!b.live) - Number(!!a.live) || // a phone streaming an emergency comes first
  Number(priorityOf(b) === "high") - Number(priorityOf(a) === "high") ||
  b.createdAt.toDate().getTime() - a.createdAt.toDate().getTime();
