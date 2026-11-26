import type { Metadata } from "next";
import { Plus_Jakarta_Sans } from "next/font/google";
import Link from "next/link";
import "./globals.css";

// Stand-in for Asphalt's Maison Neue (licensed); see contracts/DESIGN.md.
const jakarta = Plus_Jakarta_Sans({ variable: "--font-jakarta", subsets: ["latin"], weight: ["400", "600", "700"] });

export const metadata: Metadata = {
  title: "GoSafe Agent Dashboard",
  description: "Escalated ride-safety incidents for GoSafe agents",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="id" data-auth={process.env.NEXT_PUBLIC_FIREBASE_API_KEY ? "out" : "in"} className={`${jakarta.variable} h-full antialiased`}>
      <body className="min-h-full font-sans text-body-moderate lg:flex">
        {/* Dark side nav on desktop (GoCorp style), a top bar on small screens. Hidden until an agent signs in (globals.css). */}
        <aside className="app-nav bg-ink text-white lg:sticky lg:top-0 lg:h-screen lg:w-60 lg:shrink-0">
          <div className="flex h-14 items-center gap-2 px-6 lg:h-16">
            <Link href="/" className="flex items-center gap-2">
              <svg aria-hidden viewBox="0 0 24 24" className="size-6 fill-brand">
                <path d="M12 2 4 5v6c0 5 3.4 9.7 8 11 4.6-1.3 8-6 8-11V5l-8-3Zm-1.2 14.2-3.5-3.5 1.4-1.4 2.1 2.1 4.9-4.9 1.4 1.4-6.3 6.3Z" />
              </svg>
              <span className="text-title-tiny font-bold">GoSafe</span>
            </Link>
            <span className="text-body-small text-white/70 lg:hidden">Safety team</span>
          </div>
          <nav aria-label="Main" className="hidden px-3 lg:block">
            <p className="px-3 pt-2 pb-2 text-caption text-white/70">Safety team</p>
            <Link href="/" className="flex h-10 items-center gap-3 rounded-chip bg-white/10 px-3 text-title-tiny font-semibold">
              <span aria-hidden className="h-5 w-1 rounded-full bg-brand" />
              Open cases
            </Link>
          </nav>
        </aside>
        <div className="flex min-w-0 flex-1 flex-col">{children}</div>
        {/* Soft green curves along the bottom (GoTransit style); behind the content, decoration only. */}
        <svg
          aria-hidden
          viewBox="0 0 1440 200"
          preserveAspectRatio="none"
          className="app-curves pointer-events-none fixed right-0 bottom-0 -z-10 h-40 w-full lg:h-52 lg:w-[calc(100%-15rem)]"
        >
          <path d="M0 120C240 60 480 60 720 110s480 70 720 0v90H0Z" className="fill-brand-tint" />
          <path d="M0 160c300-50 560-40 820 0s420 30 620-20v60H0Z" className="fill-brand/[0.07]" />
          <path d="M0 185c260-25 520-20 760 0s440 15 680-10v25H0Z" className="fill-brand/[0.1]" />
        </svg>
      </body>
    </html>
  );
}
