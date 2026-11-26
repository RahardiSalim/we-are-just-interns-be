# dashboard

Next.js agent dashboard on Vercel. Agents see the escalated-incident queue live, open a ticket (clip, highlighted transcript, route map, LLM summary) and record a decision.

Follow the root [CLAUDE.md](../CLAUDE.md) rules and [contracts/ARCHITECTURE.md](../contracts/ARCHITECTURE.md).

- Stack: Next.js (App Router), TypeScript, Tailwind, shadcn/ui, Firebase JS SDK (Auth + Firestore reads only), MapLibre or Leaflet, wavesurfer.js.
- Layout: `src/app/` routes, `src/components/`, `src/lib/firebase.ts`, `src/lib/api.ts` (all writes go to FastAPI), `src/types/api.d.ts` (generated from `contracts/openapi.json`).
- No ML, no secrets, no Firestore writes here. Clip audio only via `GET /incidents/{id}/clip-url`.
- Show times in WIB.
- Config: `NEXT_PUBLIC_FIREBASE_*`, `NEXT_PUBLIC_API_URL`, `NEXT_PUBLIC_USE_EMULATORS`. See `.env.example`; the build fails without `NEXT_PUBLIC_FIREBASE_API_KEY`.
- Read `AGENTS.md` first: this Next.js version differs from older docs; the bundled guides are in `node_modules/next/dist/docs/`.
- Firestore types live in `src/types/firestore.ts` and mirror `contracts/firestore-schema.md`.

Commands (from `dashboard/`): `npm run dev`, `npm run build`, `npm run lint`. Deploy: push to `main` (Vercel, Root Directory `dashboard`).
