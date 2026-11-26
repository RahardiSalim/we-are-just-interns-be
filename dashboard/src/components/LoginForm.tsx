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

  return (
    <form action={submit} className="mx-auto mt-24 flex w-full max-w-sm flex-col gap-4 px-6">
      <h1 className="text-title-medium font-bold">Safety team sign-in</h1>
      <label className="flex flex-col gap-1 text-body-small">
        Email
        <input name="email" type="email" required autoComplete="username" className="h-11 rounded-chip border border-line bg-canvas px-3 focus:border-brand" />
      </label>
      <label className="flex flex-col gap-1 text-body-small">
        Password
        <input name="password" type="password" required autoComplete="current-password" className="h-11 rounded-chip border border-line bg-canvas px-3 focus:border-brand" />
      </label>
      {error && <p role="alert" className="text-body-small text-high">{error}</p>}
      <button disabled={busy} className="mt-2 h-11 rounded-full bg-brand-strong px-5 text-title-tiny font-semibold text-white hover:bg-brand-deep disabled:opacity-60">
        {busy ? "Signing in…" : "Sign in"}
      </button>
    </form>
  );
}
