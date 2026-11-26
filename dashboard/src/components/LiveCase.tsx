"use client";

import { doc, onSnapshot } from "firebase/firestore";
import { useEffect, useRef, useState } from "react";
import { CaseView } from "@/components/CaseView";
import { LoginForm } from "@/components/LoginForm";
import { api } from "@/lib/api";
import { db } from "@/lib/firebase";
import { useAgent } from "@/lib/useAgent";
import type { Incident, Trip } from "@/types/firestore";

export default function LiveCase({ id }: { id: string }) {
  const { user, notice } = useAgent();
  const [incident, setIncident] = useState<Incident | null>();
  const [trip, setTrip] = useState<Trip | null>(null);
  const [error, setError] = useState<string>();
  const opened = useRef(false);

  useEffect(() => {
    if (!user) return;
    return onSnapshot(
      doc(db, "incidents", id),
      (s) => setIncident(s.exists() ? ({ id: s.id, ...s.data() } as Incident) : null),
      (e) => setError(e.message),
    );
  }, [user, id]);

  const tripId = incident?.tripId;
  useEffect(() => {
    if (!user || !tripId) return;
    return onSnapshot(doc(db, "trips", tripId), (s) => setTrip(s.exists() ? ({ id: s.id, ...s.data() } as Trip) : null));
  }, [user, tripId]);

  // Opening an escalated case takes it: under_review, assigned to this agent.
  useEffect(() => {
    if (incident?.status === "escalated" && !opened.current) {
      opened.current = true;
      api.openCase(id).catch((e) => setError(String(e)));
    }
  }, [incident?.status, id]);

  if (user === undefined) return null;
  if (!user) return <LoginForm key={notice} notice={notice} />;
  if (error) return <p role="alert" className="p-8 text-red-600">Could not load this case: {error}</p>;
  if (incident === undefined) return <p className="p-8 text-neutral-500">Loading…</p>;
  if (incident === null) return <p className="p-8">Case not found.</p>;

  return (
    <CaseView
      incident={incident}
      trip={trip}
      loadAudio={() => api.recordingUrl(incident.tripId)}
      onDecide={(action, note) => api.decide(id, action, note)}
    />
  );
}
