import type { Metadata } from "next";
import { Plus_Jakarta_Sans } from "next/font/google";
import "./globals.css";

// Stand-in for Asphalt's Maison Neue (licensed); see contracts/DESIGN.md.
const jakarta = Plus_Jakarta_Sans({ variable: "--font-jakarta", subsets: ["latin"], weight: ["400", "600", "700"] });

export const metadata: Metadata = {
  title: "GoSafe Agent Dashboard",
  description: "Escalated ride-safety incidents for GoSafe agents",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="id" className={`${jakarta.variable} h-full antialiased`}>
      <body className="flex min-h-full flex-col font-sans text-body-moderate">
        <div className="border-b border-line bg-canvas">
          <div className="mx-auto flex h-14 w-full max-w-6xl items-center gap-2 px-6">
            <svg aria-hidden viewBox="0 0 24 24" className="size-6 fill-brand">
              <path d="M12 2 4 5v6c0 5 3.4 9.7 8 11 4.6-1.3 8-6 8-11V5l-8-3Zm-1.2 14.2-3.5-3.5 1.4-1.4 2.1 2.1 4.9-4.9 1.4 1.4-6.3 6.3Z" />
            </svg>
            <span className="text-title-tiny font-bold">GoSafe</span>
            <span className="text-body-small text-muted">Safety team</span>
          </div>
        </div>
        {children}
      </body>
    </html>
  );
}
