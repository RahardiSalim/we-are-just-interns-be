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
      where("status", "in", ["escalated", "under_review", "closed"]), // shortcut: no limit on closed history; page it when it grows
      orderBy("createdAt", "desc"),
    );
    return onSnapshot(
      q,
      (snap) => setIncidents(snap.docs.map((d) => ({ id: d.id, ...d.data() }) as Incident)),
      (e) => setError(e.message),
    );
  }, []);

  const box = "rounded-card border border-line bg-canvas p-5 text-body-small shadow-low";
  if (error) return <p role="alert" className={`${box} text-high`}>Could not load cases: {error}</p>;
  if (!incidents) return <p className={`${box} text-muted`}>Loading cases…</p>;
  return <IncidentList incidents={incidents} />;
}
