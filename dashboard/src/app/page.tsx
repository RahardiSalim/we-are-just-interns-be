"use client";

import dynamic from "next/dynamic";
import { IncidentList } from "@/components/IncidentList";
import { MOCK, mockIncidents } from "@/lib/mock";

// Loaded only in live mode, so Firebase never initialises without config.
const LiveHome = dynamic(() => import("@/components/LiveHome"), { ssr: false });

export default function Home() {
  if (!MOCK) return <LiveHome />;

  return (
    <main className="mx-auto w-full max-w-3xl px-6 py-8">
      <header className="mb-6 flex items-center gap-4">
        <h1 className="text-title-medium font-bold">Open cases</h1>
        <span className="ml-auto rounded-chip bg-surface px-2 py-0.5 text-body-small text-muted">
          Mock data
        </span>
      </header>
      <IncidentList incidents={mockIncidents} />
    </main>
  );
}
