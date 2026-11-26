"use client";

import Link from "next/link";
import { useState } from "react";
import { StatusPill } from "@/components/StatusPill";
import { byPriority, labelText, priorityOf, priorityStyle, ticketNo, triggerText, wib } from "@/lib/labels";
import type { Incident } from "@/types/firestore";

// Each filter: label, options as [value, text]. "all" means no filter.
const FILTERS = {
  priority: { label: "Priority", options: [["high", "High"], ["warning", "Warning"]] },
  source: { label: "Source", options: [["auto", "Auto-detected"], ["sos", "SOS"], ["manual_unsafe", "Reported"]] },
  status: { label: "Status", options: [["escalated", "Waiting"], ["under_review", "In review"]] },
} as const;
type FilterKey = keyof typeof FILTERS;

const pill = (on: boolean) =>
  `h-8 rounded-full border px-3 text-caption font-semibold transition-colors duration-200 ${
    on ? "border-transparent bg-brand-tint text-brand-deep dark:text-brand" : "border-line bg-canvas text-muted hover:border-brand"
  }`;

export function IncidentList({ incidents }: { incidents: Incident[] }) {
  const [tab, setTab] = useState<"open" | "closed">("open");
  const [search, setSearch] = useState("");
  const [filter, setFilter] = useState<Record<FilterKey, string>>({ priority: "all", source: "all", status: "all" });

  const isOpen = (i: Incident) => i.status !== "closed";
  const q = search.trim().toUpperCase();
  const filtered = !!q || Object.values(filter).some((v) => v !== "all");
  const shown = incidents
    .filter((i) => (tab === "open" ? isOpen(i) : !isOpen(i)))
    .filter((i) => !q || ticketNo(i.id).includes(q) || i.tripId.toUpperCase().includes(q) || i.id.toUpperCase().includes(q))
    .filter((i) => filter.priority === "all" || priorityOf(i) === filter.priority)
    .filter((i) => filter.source === "all" || i.trigger === filter.source)
    .filter((i) => tab === "closed" || filter.status === "all" || i.status === filter.status)
    .sort(byPriority);

  return (
    <div className="flex flex-col gap-3">
      <div className="rounded-card border border-line bg-canvas p-4 shadow-low">
        <div className="flex flex-wrap items-center gap-3">
          <div role="tablist" aria-label="Cases" className="flex rounded-full bg-surface p-1">
            {(["open", "closed"] as const).map((t) => (
              <button
                key={t}
                role="tab"
                aria-selected={tab === t}
                onClick={() => setTab(t)}
                className={`h-8 rounded-full px-4 text-body-small font-semibold transition-colors duration-200 ${tab === t ? "bg-canvas text-fg shadow-low" : "text-muted"}`}
              >
                {t === "open" ? "Open" : "Closed"}{" "}
                <span className="text-muted tabular-nums">{incidents.filter((i) => (t === "open" ? isOpen(i) : !isOpen(i))).length}</span>
              </button>
            ))}
          </div>
          <label className="relative min-w-56 flex-1">
            <span className="sr-only">Search by ticket number or Order ID</span>
            <svg aria-hidden viewBox="0 0 24 24" className="absolute top-1/2 left-3 size-4 -translate-y-1/2 fill-muted">
              <path d="M10 3a7 7 0 0 1 5.6 11.2l4.6 4.6-1.4 1.4-4.6-4.6A7 7 0 1 1 10 3Zm0 2a5 5 0 1 0 0 10 5 5 0 0 0 0-10Z" />
            </svg>
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search ticket number or Order ID"
              className="h-10 w-full rounded-full border border-line bg-canvas pr-4 pl-9 text-body-small focus:border-brand"
            />
          </label>
        </div>
        <div className="mt-3 flex flex-col gap-2">
          {(Object.keys(FILTERS) as FilterKey[])
            .filter((k) => k !== "status" || tab === "open")
            .map((k) => (
              <div key={k} role="group" aria-label={FILTERS[k].label} className="flex flex-wrap items-center gap-2">
                <span className="w-16 text-caption text-muted">{FILTERS[k].label}</span>
                {[["all", "All"] as const, ...FILTERS[k].options].map(([value, text]) => (
                  <button key={value} aria-pressed={filter[k] === value} onClick={() => setFilter({ ...filter, [k]: value })} className={pill(filter[k] === value)}>
                    {text}
                  </button>
                ))}
              </div>
            ))}
        </div>
      </div>

      {shown.length === 0 ? (
        <div className="rounded-card border border-line bg-canvas p-8 text-center shadow-low">
          <p className="text-title-tiny font-semibold">{filtered ? "No cases match" : tab === "open" ? "No open cases" : "No closed cases yet"}</p>
          <p className="mt-1 text-body-small text-muted">
            {filtered ? "Try another ticket number, Order ID or filter." : "New escalations show up here on their own."}
          </p>
        </div>
      ) : (
        <ul className="flex flex-col gap-3">
          {shown.map((i) => (
            <li key={i.id}>
              <Link
                href={`/incidents/${i.id}`}
                className="block rounded-card border border-line bg-canvas p-5 shadow-low transition-colors duration-200 ease-out hover:border-brand"
              >
                <div className="flex flex-wrap items-center gap-2">
                  {i.live && <span className="animate-pulse rounded-full bg-sos px-2.5 py-0.5 text-caption font-semibold text-white">● LIVE</span>}
                  <span className={`rounded-full px-2.5 py-0.5 text-caption font-semibold ${priorityStyle[priorityOf(i)].badge}`}>
                    {priorityStyle[priorityOf(i)].text}
                  </span>
                  <span className="rounded-full bg-surface px-2.5 py-0.5 text-caption font-semibold">{triggerText[i.trigger]}</span>
                  <StatusPill status={i.status} />
                  <span className="ml-auto text-caption text-muted tabular-nums">{wib.format(i.createdAt.toDate())} WIB</span>
                </div>
                <p className="mt-3 text-title-tiny font-semibold">
                  {i.label ? labelText[i.label] : "Unlabelled"}
                  {i.score != null && <span className="ml-2 font-normal text-muted">{Math.round(i.score * 100)}% on the phone</span>}
                </p>
                {i.summary && <p className="mt-1 line-clamp-2 text-body-small text-muted">{i.summary}</p>}
                <div className="mt-4 flex flex-wrap items-center gap-x-4 gap-y-1 border-t border-line pt-3 text-body-small">
                  <span className="font-semibold tabular-nums">{ticketNo(i.id)}</span>
                  <span className="text-muted">Order {i.tripId}</span>
                  <span className="ml-auto font-semibold text-brand-deep dark:text-brand">Open case →</span>
                </div>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
