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

/** One decision for the customer and one for the driver; each note is the safety team's message in that person's email. */
/**
 * shortcut: emulator only. scripts/demo.sh signs storage links with the laptop's Wi-Fi IP so a phone can reach them;
 * some browsers on the laptop itself can't open that IP, so use the page's own host for the emulator (port 9199).
 * Real signed URLs (R2 / Cloud Storage) are left alone.
 */
const sameHost = (url: string) =>
  process.env.NEXT_PUBLIC_USE_EMULATORS === "true" ? url.replace(/^http:\/\/[^/:]+:9199\//, `http://${location.hostname}:9199/`) : url;

export type Decision = {
  customer: "contact" | "none";
  driver: "contact" | "warn" | "suspend" | "none";
  customerNote: string;
  driverNote: string;
};

export const api = {
  /** Takes an escalated case: status under_review, assigned to this agent. */
  openCase: (id: string) => call("POST", `/incidents/${id}/open`),
  decide: (id: string, decision: Decision) => call("POST", `/incidents/${id}/decision`, decision),
  /** Short-lived signed URLs for every audio piece, per phone. The backend logs every call. */
  recordingUrls: (tripId: string) =>
    call<Partial<Record<Phone, { contentType: string; urls: string[] }>>>("GET", `/trips/${tripId}/recording-urls`).then((r) => {
      for (const rec of Object.values(r)) if (rec) rec.urls = rec.urls.map(sameHost);
      return r;
    }),
};
