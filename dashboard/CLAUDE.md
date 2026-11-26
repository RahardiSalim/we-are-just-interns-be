# dashboard

Next.js agent dashboard on Vercel. Agents see the escalated-incident queue live, open a ticket (clip, highlighted transcript, event timeline, LLM summary) and record a decision.

Follow the root [CLAUDE.md](../CLAUDE.md) rules and [contracts/ARCHITECTURE.md](../contracts/ARCHITECTURE.md).

- Stack: Next.js (App Router), TypeScript, Tailwind, shadcn/ui, Firebase JS SDK (Auth + Firestore reads only), wavesurfer.js. No map: we store no location; show the GoJek order ID so agents can look the trip up there.
- Layout: `src/app/` routes, `src/components/`, `src/lib/firebase.ts`, `src/lib/api.ts` (all writes go to FastAPI), `src/types/api.d.ts` (generated from `contracts/openapi.json`).
- No ML, no secrets, no Firestore writes here. Clip audio only via `GET /incidents/{id}/clip-url`.
- Show times in WIB.
- Config: `NEXT_PUBLIC_FIREBASE_*`, `NEXT_PUBLIC_API_URL`, `NEXT_PUBLIC_USE_EMULATORS`. See `.env.example`.
- Mock mode: with no `NEXT_PUBLIC_FIREBASE_API_KEY`, the page skips login and shows `src/lib/mock.ts`. Firebase code loads only in live mode (`LiveHome`, imported with `ssr: false`). Env vars are baked in at build time, so redeploy after changing them.
- Read `AGENTS.md` first: this Next.js version differs from older docs; the bundled guides are in `node_modules/next/dist/docs/`.
- Firestore types live in `src/types/firestore.ts` and mirror `contracts/firestore-schema.md`.
- Pages: `/` the queue (high priority first), `/incidents/[id]` the case page (`CaseView`, described in ARCHITECTURE.md "Agent case page"). Live data in `LiveCase`, mock data in `CaseClient`; `useAgent` is the shared agent sign-in.
- Mock mode reads `contracts/fixtures/demo-ride.json` (same as the backend seed) and plays `public/demo-ride.m4a`. `next.config.ts` sets `turbopack.root` to the repo so that import works.
- Labels, colours per flag kind and time formats live in `src/lib/labels.ts`; reuse them.

Commands (from `dashboard/`): `npm run dev`, `npm run build`, `npm run lint`. Deploy: push to `main` (Vercel, Root Directory `dashboard`).
