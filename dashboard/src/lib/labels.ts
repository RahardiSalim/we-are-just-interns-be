import type { Incident, Label, MarkerKind } from "@/types/firestore";

export const labelText: Record<Label, string> = {
  normal: "Normal",
  uncomfortable: "Uncomfortable",
  sexual_harassment: "Sexual harassment",
  threat: "Threat",
};

export const triggerText: Record<Incident["trigger"], string> = {
  sos: "SOS",
  manual_unsafe: "I feel unsafe",
  auto: "Auto-detected on phone",
};

/** One colour per flag kind, used for pins, chips and transcript lines alike. */
export const kindStyle: Record<MarkerKind, { text: string; dot: string; chip: string; line: string }> = {
  warning: {
    text: "Warning",
    dot: "bg-amber-500",
    chip: "bg-amber-100 text-amber-900 dark:bg-amber-950 dark:text-amber-200",
    line: "border-amber-500 bg-amber-50 dark:bg-amber-950/40",
  },
  high: {
    text: "High flag",
    dot: "bg-red-600",
    chip: "bg-red-100 text-red-900 dark:bg-red-950 dark:text-red-200",
    line: "border-red-600 bg-red-50 dark:bg-red-950/40",
  },
  sos: {
    text: "SOS",
    dot: "bg-rose-900",
    chip: "bg-rose-200 text-rose-950 dark:bg-rose-950 dark:text-rose-200",
    line: "border-rose-900 bg-rose-50 dark:bg-rose-950/40",
  },
  manual_unsafe: {
    text: "I feel unsafe",
    dot: "bg-orange-500",
    chip: "bg-orange-100 text-orange-900 dark:bg-orange-950 dark:text-orange-200",
    line: "border-orange-500 bg-orange-50 dark:bg-orange-950/40",
  },
};

export const mmss = (sec: number) =>
  `${String(Math.floor(sec / 60)).padStart(2, "0")}:${String(Math.floor(sec % 60)).padStart(2, "0")}`;

export const wib = new Intl.DateTimeFormat("id-ID", { timeZone: "Asia/Jakarta", dateStyle: "medium", timeStyle: "short" });

const harmful = new Set<Label>(["threat", "sexual_harassment"]);
export const isHarmful = (l: Label | null | undefined) => !!l && harmful.has(l);

/** Queue order: high severity first, then newest. */
export const byPriority = (a: Incident, b: Incident) =>
  Number(b.severity === "high") - Number(a.severity === "high") ||
  b.createdAt.toDate().getTime() - a.createdAt.toDate().getTime();
