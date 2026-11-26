import type { Incident, Label, MarkerKind } from "@/types/firestore";

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

export const mmss = (sec: number) =>
  `${String(Math.floor(sec / 60)).padStart(2, "0")}:${String(Math.floor(sec % 60)).padStart(2, "0")}`;

export const wib = new Intl.DateTimeFormat("id-ID", { timeZone: "Asia/Jakarta", dateStyle: "medium", timeStyle: "short" });

const harmful = new Set<Label>(["threat", "sexual_harassment"]);
export const isHarmful = (l: Label | null | undefined) => !!l && harmful.has(l);

/** Queue order: high severity first, then newest. */
export const byPriority = (a: Incident, b: Incident) =>
  Number(!!b.live) - Number(!!a.live) || // a phone streaming an emergency comes first
  Number(b.severity === "high") - Number(a.severity === "high") ||
  b.createdAt.toDate().getTime() - a.createdAt.toDate().getTime();
