"use client";

import { onIdTokenChanged, signOut, type User } from "firebase/auth";
import { useEffect, useState } from "react";
import { auth } from "@/lib/firebase";

/** The signed-in agent: undefined while checking, null when signed out. Non-agents are signed out. */
export function useAgent() {
  const [user, setUser] = useState<User | null | undefined>(undefined);
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

  // Layout shows the side nav only for a signed-in agent.
  useEffect(() => {
    document.documentElement.dataset.auth = user ? "in" : "out";
  }, [user]);

  return { user, notice };
}
