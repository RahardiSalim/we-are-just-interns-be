"use client";

import { signInWithEmailAndPassword } from "firebase/auth";
import { useState } from "react";
import { PageHero } from "@/components/PageHero";
import { auth } from "@/lib/firebase";

export function LoginForm({ notice }: { notice?: string }) {
  const [error, setError] = useState(notice ?? "");
  const [busy, setBusy] = useState(false);

  async function submit(form: FormData) {
    setBusy(true);
    setError("");
    try {
      await signInWithEmailAndPassword(auth, String(form.get("email")), String(form.get("password")));
    } catch {
      setError("Wrong email or password.");
    } finally {
      setBusy(false);
    }
  }

  const input = "h-11 rounded-chip border border-line bg-canvas px-3 font-normal focus:border-brand";
  return (
    <main>
      <PageHero title="Safety team sign-in" sub="Use your GoSafe agent account." width="max-w-md" />
      <form action={submit} className="mx-auto -mt-12 flex w-[calc(100%-3rem)] max-w-md flex-col gap-4 rounded-card border border-line bg-canvas p-6 shadow-high">
        <label className="flex flex-col gap-1 text-body-small font-semibold">
          Email
          <input name="email" type="email" required autoComplete="username" className={input} />
        </label>
        <label className="flex flex-col gap-1 text-body-small font-semibold">
          Password
          <input name="password" type="password" required autoComplete="current-password" className={input} />
        </label>
        {error && <p role="alert" className="text-body-small text-high">{error}</p>}
        <button disabled={busy} className="mt-2 h-11 rounded-full bg-brand-strong px-5 text-title-tiny font-semibold text-white hover:bg-brand-deep disabled:opacity-60">
          {busy ? "Signing in…" : "Sign in"}
        </button>
      </form>
    </main>
  );
}
