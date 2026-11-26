import type { Timestamp } from "firebase/firestore";
import type { Incident } from "@/types/firestore";

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
    trigger: "sos",
    status: "escalated",
    severity: "high",
    label: "sexual_harassment",
    score: 0.91,
    transcript: [
      { start: 0, end: 4.2, text: "Mbak, rumahnya di mana? Tinggal sendiri ya?", flagged: false },
      { start: 4.2, end: 9.8, text: "Cantik banget sih, mau nggak saya anterin tiap hari?", flagged: true },
      { start: 9.8, end: 13.5, text: "Pak, tolong fokus nyetir aja.", flagged: false },
      { start: 13.5, end: 19, text: "Ayo dong, nanti mampir dulu ke tempat saya.", flagged: true },
    ],
    summary:
      "Penumpang menekan SOS setelah pengemudi berulang kali menanyakan alamat dan mengajak mampir. Penumpang meminta pengemudi fokus berkendara.",
    clipPath: null,
    source: "cloud",
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
