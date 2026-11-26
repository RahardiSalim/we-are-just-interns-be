import Link from "next/link";
import { byPriority, labelText, triggerText, wib } from "@/lib/labels";
import type { Incident } from "@/types/firestore";

export function IncidentList({ incidents }: { incidents: Incident[] }) {
  if (incidents.length === 0) return <p className="text-neutral-500">No open cases.</p>;

  return (
    <ul className="flex flex-col gap-3">
      {[...incidents].sort(byPriority).map((i) => (
        <li key={i.id}>
          <Link
            href={`/incidents/${i.id}`}
            className="block rounded-lg border border-neutral-200 p-4 transition hover:border-neutral-400 dark:border-neutral-800 dark:hover:border-neutral-600"
          >
            <div className="flex flex-wrap items-center gap-2 text-sm">
              <span className={`rounded px-2 py-0.5 font-medium text-white ${i.severity === "high" ? "bg-red-600" : "bg-amber-500"}`}>
                {i.severity === "high" ? "High" : "Medium"}
              </span>
              <span className="font-medium">{i.label ? labelText[i.label] : "Unlabelled"}</span>
              {i.score != null && <span className="text-neutral-500">{Math.round(i.score * 100)}%</span>}
              <span className="ml-auto text-neutral-500">{wib.format(i.createdAt.toDate())} WIB</span>
            </div>
            <p className="mt-1 text-sm text-neutral-500">
              {triggerText[i.trigger]} · order {i.tripId} · {i.status.replaceAll("_", " ")}
            </p>
            {i.summary && <p className="mt-2 line-clamp-2">{i.summary}</p>}
            <p className="mt-2 text-sm font-medium">Open case →</p>
          </Link>
        </li>
      ))}
    </ul>
  );
}
