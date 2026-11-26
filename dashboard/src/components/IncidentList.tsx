import type { Incident } from "@/types/firestore";

const wib = new Intl.DateTimeFormat("id-ID", {
  timeZone: "Asia/Jakarta",
  dateStyle: "medium",
  timeStyle: "short",
});

const labelText: Record<string, string> = {
  normal: "Normal",
  uncomfortable: "Uncomfortable",
  sexual_harassment: "Sexual harassment",
  threat: "Threat",
};

export function IncidentList({ incidents }: { incidents: Incident[] }) {
  if (incidents.length === 0) return <p className="text-neutral-500">No open incidents.</p>;

  return (
    <ul className="flex flex-col gap-3">
      {incidents.map((i) => (
        <li key={i.id} className="rounded-lg border border-neutral-200 p-4 dark:border-neutral-800">
          <div className="flex flex-wrap items-center gap-2 text-sm">
            <span className={`rounded px-2 py-0.5 font-medium ${i.severity === "high" ? "bg-red-100 text-red-800 dark:bg-red-950 dark:text-red-200" : "bg-amber-100 text-amber-800 dark:bg-amber-950 dark:text-amber-200"}`}>
              {i.severity ?? "unrated"}
            </span>
            <span className="font-medium">{i.label ? labelText[i.label] : "Unlabelled"}</span>
            {i.score != null && <span className="text-neutral-500">{Math.round(i.score * 100)}%</span>}
            <span className="ml-auto text-neutral-500">{wib.format(i.createdAt.toDate())} WIB</span>
          </div>
          <p className="mt-1 text-sm text-neutral-500">
            {i.trigger === "sos" ? "SOS" : "I feel unsafe"} · trip {i.tripId} · {i.status.replaceAll("_", " ")}
          </p>
          {i.summary && <p className="mt-2">{i.summary}</p>}
          {i.transcript.some((t) => t.flagged) && (
            <ul className="mt-2 flex flex-col gap-1 text-sm">
              {i.transcript.filter((t) => t.flagged).map((t) => (
                <li key={t.start} className="rounded bg-red-50 px-2 py-1 dark:bg-red-950/50">
                  <span className="mr-2 font-mono text-neutral-500">{t.start.toFixed(0)}s</span>
                  {t.text}
                </li>
              ))}
            </ul>
          )}
        </li>
      ))}
    </ul>
  );
}
