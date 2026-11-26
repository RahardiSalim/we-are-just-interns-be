"use client";

import { signOut } from "firebase/auth";
import { IncidentQueue } from "@/components/IncidentQueue";
import { LoginForm } from "@/components/LoginForm";
import { PageHero } from "@/components/PageHero";
import { auth } from "@/lib/firebase";
import { useAgent } from "@/lib/useAgent";

export default function LiveHome() {
  const { user, notice } = useAgent();

  if (user === undefined) return null;
  if (!user) return <LoginForm key={notice} notice={notice} />;

  return (
    <main>
      <PageHero
        title="Open cases"
        sub="Highest priority first. Opening a case assigns it to you."
        aside={
          <>
            <span>{user.email}</span>
            <button onClick={() => signOut(auth)} className="rounded-full border border-white px-3 py-1 font-semibold hover:bg-white/10">
              Sign out
            </button>
          </>
        }
      />
      <div className="mx-auto -mt-12 w-full max-w-3xl px-6 pb-8">
        <IncidentQueue />
      </div>
    </main>
  );
}
