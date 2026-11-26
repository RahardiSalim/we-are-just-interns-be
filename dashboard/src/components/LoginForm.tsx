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
    <form action={submit} className="mx-auto mt-24 flex w-full max-w-sm flex-col gap-3 px-4">
      <h1 className="text-xl font-semibold">GoSafe agent sign-in</h1>
      <label className="flex flex-col gap-1 text-sm">
        Email
        <input name="email" type="email" required autoComplete="username" className="rounded border border-neutral-300 px-3 py-2 dark:border-neutral-700 dark:bg-neutral-900" />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        Password
        <input name="password" type="password" required autoComplete="current-password" className="rounded border border-neutral-300 px-3 py-2 dark:border-neutral-700 dark:bg-neutral-900" />
      </label>
      {error && <p role="alert" className="text-sm text-red-600">{error}</p>}
      <button disabled={busy} className="rounded bg-emerald-700 px-3 py-2 font-medium text-white disabled:opacity-60">
        {busy ? "Signing in…" : "Sign in"}
      </button>
    </form>
  );
}
