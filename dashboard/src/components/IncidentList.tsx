import Link from "next/link";
import { byPriority, labelText, triggerText, wib } from "@/lib/labels";
import type { Incident } from "@/types/firestore";

export function IncidentList({ incidents }: { incidents: Incident[] }) {
  if (incidents.length === 0) return <p className="text-muted">No open cases.</p>;

  return (
    <ul className="flex flex-col gap-3">
      {[...incidents].sort(byPriority).map((i) => (
        <li key={i.id}>
          <Link
            href={`/incidents/${i.id}`}
            className="block rounded-card border border-line bg-canvas p-5 transition hover:border-brand hover:shadow-low"
          >
            <div className="flex flex-wrap items-center gap-2 text-body-small">
              {i.live && <span className="animate-pulse rounded-chip bg-sos px-2 py-0.5 font-semibold text-white">● LIVE</span>}
              <span className={`rounded-chip px-2 py-0.5 font-semibold ${i.severity === "high" ? "bg-high text-white" : "bg-warn text-ink"}`}>
                {i.severity === "high" ? "High" : "Medium"}
              </span>
              <span className="font-semibold">{i.label ? labelText[i.label] : "Unlabelled"}</span>
              {i.score != null && <span className="text-muted">{Math.round(i.score * 100)}%</span>}
              <span className="ml-auto text-muted">{wib.format(i.createdAt.toDate())} WIB</span>
            </div>
            <p className="mt-1 text-body-small text-muted">
              {triggerText[i.trigger]} · order {i.tripId} · {i.status.replaceAll("_", " ")}
            </p>
            {i.summary && <p className="mt-2 line-clamp-2">{i.summary}</p>}
            <p className="mt-3 text-body-small font-semibold text-brand-deep dark:text-brand">Open case →</p>
          </Link>
        </li>
      ))}
    </ul>
  );
}
