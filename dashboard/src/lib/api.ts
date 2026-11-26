// All writes go through FastAPI with the agent's Firebase ID token.
import type { Phone } from "@/types/firestore";
import { auth } from "@/lib/firebase";

const BASE = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";

async function call<T>(method: "GET" | "POST", path: string, body?: unknown): Promise<T> {
  const token = await auth.currentUser?.getIdToken();
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
  return res.json() as Promise<T>;
}

export type DecisionAction = "dismiss" | "warn_driver" | "suspend_driver" | "contact_rider";

export const api = {
  /** Takes an escalated case: status under_review, assigned to this agent. */
  openCase: (id: string) => call("POST", `/incidents/${id}/open`),
  decide: (id: string, action: DecisionAction, note: string) => call("POST", `/incidents/${id}/decision`, { action, note }),
  /** Short-lived signed URLs for every audio piece, per phone. The backend logs every call. */
  recordingUrls: (tripId: string) =>
    call<Partial<Record<Phone, { contentType: string; urls: string[] }>>>("GET", `/trips/${tripId}/recording-urls`),
};
