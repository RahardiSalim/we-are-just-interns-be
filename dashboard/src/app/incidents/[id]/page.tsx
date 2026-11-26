import { Suspense } from "react";
import { CaseClient } from "@/components/CaseClient";

// The case id comes from the URL at request time, so the client part sits in Suspense.
export default function CasePage() {
  return (
    <Suspense fallback={<p className="p-8 text-neutral-500">Loading…</p>}>
      <CaseClient />
    </Suspense>
  );
}
