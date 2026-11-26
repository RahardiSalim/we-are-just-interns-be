"use client";

import dynamic from "next/dynamic";
import { useParams } from "next/navigation";
import { useState } from "react";
import { CaseView } from "@/components/CaseView";
import { MOCK, mockIncidents, mockTrips } from "@/lib/mock";

// Loaded only in live mode, so Firebase never initialises without config.
const LiveCase = dynamic(() => import("@/components/LiveCase"), { ssr: false });

export function CaseClient() {
  const { id } = useParams<{ id: string }>();
  return MOCK ? <MockCase id={id} /> : <LiveCase id={id} />;
}

function MockCase({ id }: { id: string }) {
  const found = mockIncidents.find((i) => i.id === id);
  const [status, setStatus] = useState(found?.status);
  if (!found || !status) return <p className="p-8">Case not found.</p>;
  return (
    <CaseView
      incident={{ ...found, status }}
      trip={mockTrips[found.tripId] ?? null}
      loadAudio={async () => "/demo-ride.m4a"}
      onDecide={async () => setStatus("closed")}
    />
  );
}
