"use client";

import dynamic from "next/dynamic";
import { IncidentList } from "@/components/IncidentList";
import { MOCK, mockIncidents } from "@/lib/mock";

// Loaded only in live mode, so Firebase never initialises without config.
const LiveHome = dynamic(() => import("@/components/LiveHome"), { ssr: false });

export default function Home() {
  if (!MOCK) return <LiveHome />;

  return (
    <main className="mx-auto w-full max-w-3xl px-4 py-8">
      <header className="mb-6 flex items-center gap-4">
        <h1 className="text-xl font-semibold">Open incidents</h1>
        <span className="ml-auto rounded bg-neutral-100 px-2 py-0.5 text-sm text-neutral-600 dark:bg-neutral-800 dark:text-neutral-300">
          Mock data
        </span>
      </header>
      <IncidentList incidents={mockIncidents} />
    </main>
  );
}
