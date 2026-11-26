"use client";

import { signInWithEmailAndPassword } from "firebase/auth";
import { useState } from "react";
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
  // Signed out there is no side nav (globals.css), so the card sits in the middle of the screen.
  return (
    <main className="flex min-h-dvh flex-col items-center justify-center px-6 py-8">
      <div className="w-full max-w-md overflow-hidden rounded-card border border-line bg-canvas shadow-high">
        <div className="bg-brand-strong px-6 pt-6 pb-5 text-center text-white">
          <svg aria-hidden viewBox="0 0 24 24" className="mx-auto mb-3 size-10 fill-white">
            <path d="M12 2 4 5v6c0 5 3.4 9.7 8 11 4.6-1.3 8-6 8-11V5l-8-3Zm-1.2 14.2-3.5-3.5 1.4-1.4 2.1 2.1 4.9-4.9 1.4 1.4-6.3 6.3Z" />
          </svg>
          <h1 className="text-title-medium font-bold">Safety team sign-in</h1>
          <p className="mt-1 text-body-small">Use your GoSafe agent account.</p>
        </div>
        <form action={submit} className="flex flex-col gap-4 p-6">
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
      </div>
    </main>
  );
}
