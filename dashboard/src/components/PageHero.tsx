import Link from "next/link";
import type { ReactNode } from "react";

/** Green header with a curved bottom (Gojek app style). The page's first cards overlap it with `-mt-12`. */
export function PageHero({ title, sub, back, aside, width = "max-w-3xl", children }: {
  title: string;
  sub?: ReactNode;
  back?: boolean;
  aside?: ReactNode;
  width?: string;
  children?: ReactNode;
}) {
  return (
    <header className="rounded-b-sheet bg-brand-strong text-white">
      <div className={`mx-auto w-full ${width} px-6 pt-6 pb-20`}>
        {back && (
          <Link
            href="/"
            className="mb-4 inline-flex h-8 items-center gap-2 rounded-full bg-canvas pr-4 pl-1 text-caption font-semibold text-brand-deep transition-colors duration-200 hover:bg-brand-tint dark:text-brand"
          >
            <span aria-hidden className="flex size-6 items-center justify-center rounded-full bg-brand-strong text-white">
              <svg viewBox="0 0 24 24" className="size-4 fill-current">
                <path d="M11 6.4 9.6 5 3 11.6l6.6 6.6 1.4-1.4L6.8 12.6H21v-2H6.8L11 6.4Z" />
              </svg>
            </span>
            Queue
          </Link>
        )}
        <div className="flex flex-wrap items-center gap-3">
          <h1 className="text-title-medium font-bold">{title}</h1>
          {aside && <div className="ml-auto flex items-center gap-3 text-body-small">{aside}</div>}
        </div>
        {sub && <p className="mt-1 text-body-small">{sub}</p>}
        {children && <div className="mt-4 flex flex-wrap items-center gap-2">{children}</div>}
      </div>
    </header>
  );
}
