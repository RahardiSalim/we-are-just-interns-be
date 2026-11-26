"use client";

import { doc, getDoc, onSnapshot } from "firebase/firestore";
import { useEffect, useRef, useState } from "react";
import { CaseView } from "@/components/CaseView";
import { LoginForm } from "@/components/LoginForm";
import { api } from "@/lib/api";
import { db } from "@/lib/firebase";
import { useAgent } from "@/lib/useAgent";
import type { Incident, Person, Phone, Trip } from "@/types/firestore";

/** Every uploaded piece of one phone's recording, joined into one playable file (ADTS pieces join byte for byte). */
async function loadPieces(tripId: string, phone: Phone): Promise<string> {
  const rec = (await api.recordingUrls(tripId))[phone];
  if (!rec) throw new Error("no uploaded audio from this phone yet");
  const parts = await Promise.all(rec.urls.map((u) => fetch(u).then((r) => (r.ok ? r.blob() : Promise.reject(r.status)))));
  return URL.createObjectURL(new Blob(parts, { type: rec.contentType }));
}

export default function LiveCase({ id }: { id: string }) {
  const { user, notice } = useAgent();
  const [incident, setIncident] = useState<Incident | null>();
  const [trip, setTrip] = useState<Trip | null>(null);
  const [people, setPeople] = useState<Record<string, Person>>({});
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

  // Names and phone numbers, so the agent can call the rider or driver.
  const riderId = trip?.riderId;
  const driverId = trip?.driverId;
  useEffect(() => {
    if (!user || !riderId || !driverId) return;
    Promise.all([riderId, driverId].map((uid) => getDoc(doc(db, "users", uid)))).then((snaps) =>
      setPeople(Object.fromEntries(snaps.filter((s) => s.exists()).map((s) => [s.id, s.data() as Person]))),
    );
  }, [user, riderId, driverId]);

  // Opening an escalated case takes it: under_review, assigned to this agent.
  useEffect(() => {
    if (incident?.status === "escalated" && !opened.current) {
      opened.current = true;
      api.openCase(id).catch((e) => setError(String(e)));
    }
  }, [incident?.status, id]);

  if (user === undefined) return null;
  if (!user) return <LoginForm key={notice} notice={notice} />;
  if (error) return <p role="alert" className="p-8 text-high">Could not load this case: {error}</p>;
  if (incident === undefined) return <p className="p-8 text-muted">Loading…</p>;
  if (incident === null) return <p className="p-8">Case not found.</p>;

  return (
    <CaseView
      incident={incident}
      trip={trip}
      people={people}
      loadAudio={(phone) => loadPieces(incident.tripId, phone)}
      onDecide={(decision) => api.decide(id, decision)}
    />
  );
}
