"use client";

import { onIdTokenChanged, signOut, type User } from "firebase/auth";
import { useEffect, useState } from "react";
import { IncidentQueue } from "@/components/IncidentQueue";
import { LoginForm } from "@/components/LoginForm";
import { auth } from "@/lib/firebase";

export default function LiveHome() {
  const [user, setUser] = useState<User | null | undefined>(undefined); // undefined = still checking
  const [notice, setNotice] = useState<string>();

  useEffect(
    () =>
      onIdTokenChanged(auth, async (u) => {
        if (u && (await u.getIdTokenResult()).claims.role !== "agent") {
          setNotice("This dashboard is for safety agents only.");
          await signOut(auth); // fires this listener again with null
          return;
        }
        if (auth.currentUser === u) setUser(u); // skip if they signed out while the role check ran
      }),
    [],
  );

  if (user === undefined) return null;
  if (!user) return <LoginForm key={notice} notice={notice} />;

  return (
    <main className="mx-auto w-full max-w-3xl px-4 py-8">
      <header className="mb-6 flex items-center gap-4">
        <h1 className="text-xl font-semibold">Open incidents</h1>
        <span className="ml-auto text-sm text-neutral-500">{user.email}</span>
        <button onClick={() => signOut(auth)} className="text-sm underline">
          Sign out
        </button>
      </header>
      <IncidentQueue />
    </main>
  );
}
