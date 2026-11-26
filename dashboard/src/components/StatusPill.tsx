import { statusStyle } from "@/lib/labels";
import type { IncidentStatus } from "@/types/firestore";

export function StatusPill({ status }: { status: IncidentStatus }) {
  const s = statusStyle[status] ?? { text: status.replaceAll("_", " "), dot: "bg-muted" };
  return (
    <span className="inline-flex items-center gap-1.5 rounded-full border border-line bg-canvas px-2.5 py-0.5 text-caption font-semibold text-fg">
      <span aria-hidden className={`size-2 rounded-full ${s.dot}`} />
      {s.text}
    </span>
  );
}
