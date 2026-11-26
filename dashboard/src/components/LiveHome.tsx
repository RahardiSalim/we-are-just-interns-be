"use client";

import { signOut } from "firebase/auth";
import { IncidentQueue } from "@/components/IncidentQueue";
import { LoginForm } from "@/components/LoginForm";
import { auth } from "@/lib/firebase";
import { useAgent } from "@/lib/useAgent";

export default function LiveHome() {
  const { user, notice } = useAgent();

  if (user === undefined) return null;
  if (!user) return <LoginForm key={notice} notice={notice} />;

  return (
    <main className="mx-auto w-full max-w-3xl px-6 py-8">
      <header className="mb-6 flex items-center gap-4">
        <h1 className="text-title-medium font-bold">Open cases</h1>
        <span className="ml-auto text-body-small text-muted">{user.email}</span>
        <button onClick={() => signOut(auth)} className="text-body-small underline">
          Sign out
        </button>
      </header>
      <IncidentQueue />
    </main>
  );
}
