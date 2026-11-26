"use client";

import Link from "next/link";
import { useRef, useState } from "react";
import type { DecisionAction } from "@/lib/api";
import { isHarmful, kindStyle, labelText, mmss, triggerText, wib } from "@/lib/labels";
import type { Incident, Marker, Review, Trip } from "@/types/firestore";

const actions: { value: DecisionAction; text: string; hint: string }[] = [
  { value: "contact_rider", text: "Contact rider", hint: "Call the rider to check on them and offer support." },
  { value: "warn_driver", text: "Warn driver", hint: "Send the driver a formal warning." },
  { value: "suspend_driver", text: "Suspend driver", hint: "Pause the driver's account pending investigation." },
  { value: "dismiss", text: "Dismiss", hint: "Nothing unsafe happened." },
];

/** How close to a flag the audio must play before it counts as "listened". */
const LISTEN_WINDOW = 3;

export function CaseView({
  incident,
  trip,
  loadAudio,
  onDecide,
}: {
  incident: Incident;
  trip: Trip | null;
  /** Fetches a playable URL. Called only when the agent chooses to listen (it's audit-logged). */
  loadAudio: () => Promise<string>;
  onDecide: (action: DecisionAction, note: string) => Promise<unknown>;
}) {
  const rec = trip?.recording?.status === "uploaded" ? trip.recording : null;
  const review = rec?.review;
  const audio = useRef<HTMLAudioElement>(null);
  const [src, setSrc] = useState<string>();
  const [audioError, setAudioError] = useState<string>();
  const [now, setNow] = useState(0);
  const [listened, setListened] = useState(false);
  const [readReport, setReadReport] = useState(false);
  const [action, setAction] = useState<DecisionAction>();
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  const flagTimes = [...(rec?.markers ?? []).map((m) => m.at), ...(review?.moments ?? []).map((m) => m.at)];
  const phoneFlag = strongest(rec?.markers ?? []);
  const closed = incident.status === "closed";
  const canDecide = rec ? listened : readReport;

  async function playAt(sec: number) {
    try {
      const url = src ?? (await loadAudio());
      setSrc(url);
      const el = audio.current!;
      if (el.src !== url) {
        const ready = new Promise((ok, fail) => {
          el.addEventListener("loadedmetadata", ok, { once: true });
          el.addEventListener("error", () => fail(el.error?.message ?? "unplayable audio"), { once: true });
        });
        el.src = url;
        el.load(); // preload="none" never fetches metadata on its own
        await ready;
      }
      el.currentTime = Math.max(0, sec - 1); // a second of lead-in for context
      await el.play();
    } catch (e) {
      setAudioError(`Could not load the recording: ${e}`);
    }
  }

  function onTime() {
    const t = audio.current?.currentTime ?? 0;
    setNow(t);
    if (!audio.current?.paused && flagTimes.some((at) => t >= at && t <= at + LISTEN_WINDOW)) setListened(true);
  }

  async function submit() {
    if (!action) return;
    setBusy(true);
    setError(undefined);
    try {
      await onDecide(action, note);
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="mx-auto w-full max-w-6xl px-4 py-6">
      <Link href="/" className="text-sm text-neutral-500 hover:underline">← Queue</Link>

      <header className="mt-2 flex flex-wrap items-center gap-2">
        <h1 className="mr-2 text-2xl font-semibold">Order {incident.tripId}</h1>
        <Chip className={incident.severity === "high" ? "bg-red-600 text-white" : "bg-amber-500 text-white"}>
          {incident.severity === "high" ? "High priority" : "Medium priority"}
        </Chip>
        <Chip className="bg-neutral-100 dark:bg-neutral-800">{triggerText[incident.trigger]}</Chip>
        <Chip className="bg-neutral-100 dark:bg-neutral-800">{incident.status.replaceAll("_", " ")}</Chip>
        <span className="ml-auto text-sm text-neutral-500">Reported {wib.format(incident.createdAt.toDate())} WIB</span>
      </header>

      <div className="mt-6 grid gap-6 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)]">
        <div className="flex min-w-0 flex-col gap-6">
          <Card title="Ride recording">
            {rec ? (
              <>
                <p className="mb-3 text-sm text-neutral-500">
                  Jump straight to a flag; you don&apos;t need to hear the whole ride. Playback is logged.
                </p>
                <FlagTimeline rec={rec} now={now} onSeek={playAt} />
                <audio ref={audio} controls preload="none" onTimeUpdate={onTime} className="mt-3 w-full" />
                {!src && (
                  <button onClick={() => playAt(rec.markers[0]?.at ?? 0)} className="mt-2 text-sm font-medium underline">
                    Load recording
                  </button>
                )}
                {audioError && <p role="alert" className="mt-2 text-sm text-red-600">{audioError}</p>}
              </>
            ) : (
              <p className="text-sm text-neutral-500">
                {trip?.recording
                  ? "The phone is still uploading the full ride."
                  : "No full recording: it uploads after the ride ends, and only for rides with a high flag or an SOS."}
              </p>
            )}
          </Card>

          <Card title={rec ? "Transcript (whole ride)" : "Transcript (the phone's 30 s window)"}>
            {rec ? (
              <ol className="flex flex-col gap-1">
                {rec.transcript.map((line, i) => {
                  const marker = rec.markers.find((m) => Math.abs(m.at - line.at) < 0.5);
                  const next = rec.transcript[i + 1]?.at ?? Infinity;
                  const active = src && now >= line.at && now < next;
                  return (
                    <li key={line.at}>
                      <button
                        onClick={() => playAt(line.at)}
                        className={`flex w-full gap-3 rounded border-l-4 px-3 py-1.5 text-left text-sm ${
                          marker ? kindStyle[marker.kind].line : "border-transparent"
                        } ${active ? "ring-2 ring-neutral-400" : ""}`}
                      >
                        <span className="font-mono text-neutral-500">{mmss(line.at)}</span>
                        <span className="flex-1">{line.text}</span>
                        {marker && <span className={`shrink-0 rounded px-1.5 text-xs ${kindStyle[marker.kind].chip}`}>{kindStyle[marker.kind].text}</span>}
                      </button>
                    </li>
                  );
                })}
              </ol>
            ) : (
              <ol className="flex flex-col gap-1 text-sm">
                {incident.transcript.map((t) => (
                  <li key={t.start} className={`rounded border-l-4 px-3 py-1.5 ${t.flagged ? kindStyle.high.line : "border-transparent"}`}>
                    <span className="mr-3 font-mono text-neutral-500">{mmss(t.start)}</span>
                    {t.text}
                  </li>
                ))}
              </ol>
            )}
          </Card>
        </div>

        <div className="flex min-w-0 flex-col gap-6">
          <Card title="AI review" aside={review && <SourceBadge review={review} />}>
            {review ? (
              <div className="flex flex-col gap-3 text-sm">
                <Verdict
                  phone={phoneFlag ? `${kindStyle[phoneFlag.kind].text}${phoneFlag.label ? ` · ${labelText[phoneFlag.label]}` : ""}` : incident.label ? labelText[incident.label] : "None"}
                  ai={labelText[review.label]}
                  confidence={review.confidence}
                  agree={isHarmful(review.label) === isHarmful(phoneFlag?.label ?? incident.label)}
                />
                <p>{review.summary}</p>
                {review.moments.length > 0 && (
                  <div>
                    <h3 className="mb-1 font-medium">Why (click to listen)</h3>
                    <ul className="flex flex-col gap-1">
                      {review.moments.map((m) => (
                        <li key={m.at} className="flex gap-2">
                          <button onClick={() => playAt(m.at)} className="font-mono text-blue-700 underline dark:text-blue-300">
                            {mmss(m.at)}
                          </button>
                          <span>
                            <span className="font-medium">{labelText[m.label]}:</span> {m.reason}
                          </span>
                        </li>
                      ))}
                    </ul>
                  </div>
                )}
                {review.note && <p className="text-xs text-neutral-500">{review.note}</p>}
                <p className="rounded bg-neutral-100 p-2 text-xs dark:bg-neutral-800">
                  AI can be wrong. Listen to the flagged moments yourself before deciding.
                </p>
              </div>
            ) : (
              <p className="text-sm text-neutral-500">
                {rec ? "Reviewing the ride…" : "Appears once the full recording has been uploaded."}
              </p>
            )}
          </Card>

          <Card title="Phone's report">
            <p className="text-sm">{incident.summary ?? "No summary."}</p>
          </Card>

          <Card title="Decision">
            {closed ? (
              <p className="text-sm">This case is closed.</p>
            ) : (
              <div className="flex flex-col gap-3">
                <fieldset className="flex flex-col gap-2">
                  {actions.map((a) => (
                    <label key={a.value} className="flex cursor-pointer gap-2 rounded border border-neutral-200 p-2 text-sm dark:border-neutral-700">
                      <input type="radio" name="action" value={a.value} checked={action === a.value} onChange={() => setAction(a.value)} />
                      <span>
                        <span className="font-medium">{a.text}</span>
                        <span className="block text-neutral-500">{a.hint}</span>
                      </span>
                    </label>
                  ))}
                </fieldset>
                <textarea
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                  placeholder="Note for the case file (what you heard, who you contacted)"
                  className="min-h-20 rounded border border-neutral-300 p-2 text-sm dark:border-neutral-700 dark:bg-neutral-900"
                />
                {rec ? (
                  <p className={`text-xs ${listened ? "text-emerald-700 dark:text-emerald-400" : "text-neutral-500"}`}>
                    {listened ? "✓ You listened to a flagged moment." : "Listen to at least one flagged moment to decide."}
                  </p>
                ) : (
                  <label className="flex gap-2 text-xs">
                    <input type="checkbox" checked={readReport} onChange={(e) => setReadReport(e.target.checked)} />
                    I read the phone&apos;s report and transcript.
                  </label>
                )}
                {error && <p role="alert" className="text-sm text-red-600">{error}</p>}
                <button
                  disabled={!action || !canDecide || busy}
                  onClick={submit}
                  className="rounded bg-emerald-700 px-3 py-2 font-medium text-white disabled:opacity-40"
                >
                  {busy ? "Saving…" : "Record decision"}
                </button>
              </div>
            )}
          </Card>
        </div>
      </div>
    </main>
  );
}

function strongest(markers: Marker[]): Marker | undefined {
  const rank = { sos: 3, high: 2, manual_unsafe: 1, warning: 0 } as const;
  return [...markers].sort((a, b) => rank[b.kind] - rank[a.kind])[0];
}

function FlagTimeline({ rec, now, onSeek }: { rec: NonNullable<Trip["recording"]>; now: number; onSeek: (at: number) => void }) {
  const pct = (at: number) => `${Math.min(100, (at / Math.max(rec.durationSec, 1)) * 100)}%`;
  return (
    <div>
      <div className="relative h-8 rounded bg-neutral-100 dark:bg-neutral-800" aria-label="Flags along the ride">
        <div className="absolute inset-y-0 left-0 rounded bg-neutral-300/60 dark:bg-neutral-600/60" style={{ width: pct(now) }} />
        {rec.markers.map((m) => (
          <button
            key={`${m.kind}-${m.at}`}
            onClick={() => onSeek(m.at)}
            title={`${kindStyle[m.kind].text} at ${mmss(m.at)}`}
            aria-label={`${kindStyle[m.kind].text} at ${mmss(m.at)}`}
            className={`absolute top-1 h-6 w-2 -translate-x-1/2 rounded ${kindStyle[m.kind].dot}`}
            style={{ left: pct(m.at) }}
          />
        ))}
      </div>
      <div className="mt-1 flex justify-between font-mono text-xs text-neutral-500">
        <span>00:00</span>
        <span>{mmss(rec.durationSec)}</span>
      </div>
      <div className="mt-3 flex flex-wrap gap-2">
        {rec.markers.map((m) => (
          <button key={`${m.kind}-${m.at}`} onClick={() => onSeek(m.at)} className={`rounded px-2 py-1 text-xs ${kindStyle[m.kind].chip}`}>
            ▶ {mmss(m.at)} · {kindStyle[m.kind].text}
            {m.label ? ` · ${labelText[m.label]}` : ""}
            {m.score != null ? ` ${Math.round(m.score * 100)}%` : ""}
          </button>
        ))}
      </div>
    </div>
  );
}

function Verdict({ phone, ai, confidence, agree }: { phone: string; ai: string; confidence: number; agree: boolean }) {
  return (
    <div className="grid grid-cols-2 gap-2">
      <div className="rounded border border-neutral-200 p-2 dark:border-neutral-700">
        <div className="text-xs text-neutral-500">Phone flagged</div>
        <div className="font-medium">{phone}</div>
      </div>
      <div className="rounded border border-neutral-200 p-2 dark:border-neutral-700">
        <div className="text-xs text-neutral-500">AI reads it as</div>
        <div className="font-medium">{ai}</div>
        <div className="mt-1 h-1.5 rounded bg-neutral-200 dark:bg-neutral-700">
          <div className="h-1.5 rounded bg-neutral-700 dark:bg-neutral-300" style={{ width: `${Math.round(confidence * 100)}%` }} />
        </div>
        <div className="text-xs text-neutral-500">{Math.round(confidence * 100)}% confident</div>
      </div>
      <div className={`col-span-2 rounded px-2 py-1 text-xs ${agree ? "bg-emerald-50 text-emerald-900 dark:bg-emerald-950 dark:text-emerald-200" : "bg-amber-50 text-amber-900 dark:bg-amber-950 dark:text-amber-200"}`}>
        {agree ? "The AI agrees with the phone's flag." : "The AI reads this differently from the phone. Listen carefully."}
      </div>
    </div>
  );
}

function SourceBadge({ review }: { review: Review }) {
  const text = { "sahabat-ai": "Sahabat-AI", gemini: "Gemini", rules: "Rule-based" }[review.source];
  return <span className="rounded bg-neutral-100 px-2 py-0.5 text-xs dark:bg-neutral-800">{text}</span>;
}

function Card({ title, aside, children }: { title: string; aside?: React.ReactNode; children: React.ReactNode }) {
  return (
    <section className="rounded-lg border border-neutral-200 p-4 dark:border-neutral-800">
      <div className="mb-3 flex items-center gap-2">
        <h2 className="font-semibold">{title}</h2>
        <span className="ml-auto">{aside}</span>
      </div>
      {children}
    </section>
  );
}

function Chip({ className, children }: { className: string; children: React.ReactNode }) {
  return <span className={`rounded px-2 py-0.5 text-sm font-medium ${className}`}>{children}</span>;
}
