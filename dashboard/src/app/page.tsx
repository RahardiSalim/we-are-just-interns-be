"use client";

import dynamic from "next/dynamic";
import { IncidentList } from "@/components/IncidentList";
import { PageHero } from "@/components/PageHero";
import { MOCK, mockIncidents } from "@/lib/mock";

// Loaded only in live mode, so Firebase never initialises without config.
const LiveHome = dynamic(() => import("@/components/LiveHome"), { ssr: false });

export default function Home() {
  if (!MOCK) return <LiveHome />;

  return (
    <main>
      <PageHero
        title="Open cases"
        sub="Highest priority first. Opening a case assigns it to you."
        aside={<span className="rounded-full bg-canvas px-2.5 py-0.5 text-caption font-semibold text-fg">Mock data</span>}
      />
      <div className="mx-auto -mt-12 w-full max-w-3xl px-6 pb-8">
        <IncidentList incidents={mockIncidents} />
      </div>
    </main>
  );
}
