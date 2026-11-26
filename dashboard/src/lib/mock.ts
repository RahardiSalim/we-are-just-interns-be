import type { Timestamp } from "firebase/firestore";
import ride from "../../../contracts/fixtures/demo-ride.json";
import type { Incident, Marker, Trip } from "@/types/firestore";

// shortcut: no Firebase config means mock mode (no login, fake data); set NEXT_PUBLIC_FIREBASE_API_KEY to go live.
export const MOCK = !process.env.NEXT_PUBLIC_FIREBASE_API_KEY;

// Fixed times: the page is prerendered, and Next.js rejects Date.now() during prerender.
const at = (iso: string) => ({ toDate: () => new Date(iso) }) as Timestamp;
const deleteAt = at("2026-12-03T12:00:00Z");

// Same story as backend/app/services/seed.py, plus two more cases to fill the queue.
export const mockIncidents: Incident[] = [
  {
    id: "demo-incident-1",
    tripId: "GR-DEMO-1",
    reportedBy: "rider1",
    trigger: "auto",
    status: "escalated",
    severity: "high",
    label: "sexual_harassment",
    score: 0.8,
    // The phone's 30 s window when it flagged, as the backend seed stores it.
    transcript: ride.transcript
      .filter((l) => l.at <= 22)
      .map((l) => ({ start: +(l.at - 1).toFixed(1), end: +(l.end - 1).toFixed(1), text: l.text, flagged: [9.8, 18.2, 22].includes(l.at) })),
    summary: "Pemicu: deteksi otomatis di ponsel pada trip GR-DEMO-1. Penilaian otomatis: sexual_harassment (80%).",
    clipPath: null,
    source: "device",
    assignedAgent: null,
    createdAt: at("2026-11-26T19:42:00+07:00"),
    deleteAt,
  },
  {
    id: "demo-incident-2",
    tripId: "GR-DEMO-2",
    reportedBy: "rider2",
    trigger: "manual_unsafe",
    status: "under_review",
    severity: "high",
    label: "threat",
    score: 0.84,
    transcript: [
      { start: 0, end: 5.1, text: "Pak, ini kok lewat jalan kecil? Di aplikasi lurus terus.", flagged: false },
      { start: 5.1, end: 9.4, text: "Udah diem aja, jangan banyak tanya.", flagged: true },
      { start: 9.4, end: 14, text: "Kalau lapor-lapor, saya tahu rumah kamu.", flagged: true },
    ],
    summary:
      "Penumpang menekan \"Saya merasa tidak aman\" saat pengemudi keluar dari rute. Pengemudi menyuruh penumpang diam dan mengancam jika melapor.",
    clipPath: null,
    source: "cloud",
    assignedAgent: "agent1",
    createdAt: at("2026-11-26T19:25:00+07:00"),
    deleteAt,
  },
  {
    id: "demo-incident-3",
    tripId: "GR-DEMO-3",
    reportedBy: "rider1",
    trigger: "sos",
    status: "escalated",
    severity: "medium",
    label: "uncomfortable",
    score: 0.63,
    transcript: [
      { start: 0, end: 4, text: "Mbak udah punya pacar belum?", flagged: true },
      { start: 4, end: 7.5, text: "Maaf Pak, saya lagi telepon.", flagged: false },
    ],
    summary:
      "Check-in tidak dijawab dalam 90 detik setelah pertanyaan pribadi dari pengemudi, sehingga kasus dieskalasi otomatis.",
    clipPath: null,
    source: "device",
    assignedAgent: null,
    createdAt: at("2026-11-26T19:07:00+07:00"),
    deleteAt,
  },
];

// The demo ride the backend seeds too: same audio (public/demo-ride.m4a) and timings.
export const mockTrips: Record<string, Trip> = {
  "GR-DEMO-1": {
    id: "GR-DEMO-1",
    riderId: "rider1",
    driverId: "driver1",
    mode: "goride",
    status: "ended",
    consent: { rider: true, driver: true },
    recordings: { rider: {
      contentType: ride.contentType,
      pieces: 1,
      live: false,
      durationSec: ride.durationSec,
      markers: ride.markers as Marker[],
      transcript: ride.transcript,
      status: "uploaded",
      review: {
        source: "rules",
        summary: "Perjalanan 00:30 dengan 7 kalimat terdengar. 3 kalimat ditandai, paling berat: sexual_harassment.",
        label: "sexual_harassment",
        confidence: 0.8,
        moments: [
          { at: 9.8, label: "uncomfortable", reason: "Mengandung frasa yang ditandai." },
          { at: 18.2, label: "uncomfortable", reason: "Mengandung frasa yang ditandai." },
          { at: 22.0, label: "sexual_harassment", reason: "Mengandung frasa yang ditandai." },
        ],
        note: "No AI model is connected yet. Rule-based review shown.",
      },
    } },
  },
};
