# dashboard

Next.js agent dashboard on Vercel. Agents see the escalated-incident queue live, open a ticket (clip, highlighted transcript, route map, LLM summary) and record a decision.

Follow the root [CLAUDE.md](../CLAUDE.md) rules and [contracts/ARCHITECTURE.md](../contracts/ARCHITECTURE.md).

- Stack: Next.js (App Router), TypeScript, Tailwind, shadcn/ui, Firebase JS SDK (Auth + Firestore reads only), MapLibre or Leaflet, wavesurfer.js.
- Layout: `src/app/` routes, `src/components/`, `src/lib/firebase.ts`, `src/lib/api.ts` (all writes go to FastAPI), `src/types/api.d.ts` (generated from `contracts/openapi.json`).
- No ML, no secrets, no Firestore writes here. Clip audio only via `GET /incidents/{id}/clip-url`.
- Show times in WIB.
- Config: `NEXT_PUBLIC_FIREBASE_*`, `NEXT_PUBLIC_API_URL`.
