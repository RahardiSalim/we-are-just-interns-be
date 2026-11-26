"use client";

import { collection, onSnapshot, orderBy, query, where } from "firebase/firestore";
import { useEffect, useState } from "react";
import { IncidentList } from "@/components/IncidentList";
import { db } from "@/lib/firebase";
import type { Incident } from "@/types/firestore";

export function IncidentQueue() {
  const [incidents, setIncidents] = useState<Incident[] | null>(null);
  const [error, setError] = useState("");

  useEffect(() => {
    const q = query(
      collection(db, "incidents"),
      where("status", "in", ["escalated", "under_review"]),
      orderBy("createdAt", "desc"),
    );
    return onSnapshot(
      q,
      (snap) => setIncidents(snap.docs.map((d) => ({ id: d.id, ...d.data() }) as Incident)),
      (e) => setError(e.message),
    );
  }, []);

  if (error) return <p role="alert" className="text-red-600">Could not load incidents: {error}</p>;
  if (!incidents) return <p className="text-neutral-500">Loading…</p>;
  return <IncidentList incidents={incidents} />;
}
