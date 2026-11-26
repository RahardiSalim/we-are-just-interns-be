"use client";

import { useEffect, useRef, useState } from "react";
import { PageHero } from "@/components/PageHero";
import { RecordingPlayer } from "@/components/RecordingPlayer";
import { StatusPill } from "@/components/StatusPill";
import type { Decision } from "@/lib/api";
import { isHarmful, kindStyle, labelText, mmss, priorityOf, priorityStyle, ticketNo, triggerText, wib } from "@/lib/labels";
import type { Incident, Marker, Person, Phone, Recording, Review, Trip } from "@/types/firestore";

const CUSTOMER: { value: Decision["customer"]; text: string; hint: string }[] = [
  { value: "contact", text: "Contact customer", hint: "Call the customer to check on them and offer support." },
  { value: "none", text: "No action / dismiss", hint: "No call. The customer still gets the outcome by email." },
];
const DRIVER: { value: Decision["driver"]; text: string; hint: string }[] = [
  { value: "contact", text: "Contact driver", hint: "Call the driver to hear their side. Not a warning." },
  { value: "warn", text: "Warn driver", hint: "Send the driver a formal warning." },
  { value: "suspend", text: "Suspend driver", hint: "Pause the driver's account pending investigation." },
  { value: "none", text: "No action", hint: "Nothing is sent to the driver." },
];

/** How close to a flag the audio must play before it counts as "listened". */
const LISTEN_WINDOW = 3;

export function CaseView({
  incident,
  trip,
  people,
  loadAudio,
  onDecide,
}: {
  incident: Incident;
  trip: Trip | null;
  /** users/{uid} for the rider and the driver (name and phone), keyed by uid. */
  people: Record<string, Person>;
  /** Fetches a playable URL. Called only when the agent chooses to listen (it's audit-logged). */
  loadAudio: (phone: Phone) => Promise<string>;
  onDecide: (decision: Decision) => Promise<unknown>;
}) {
  // Each phone uploads its own recording; the agent picks which one to hear.
  const phones = (["rider", "driver"] as const).filter((p) => (trip?.recordings?.[p]?.pieces ?? 0) > 0);
  const [picked, setPicked] = useState<Phone>();
  const phone = picked && phones.includes(picked) ? picked : phones[0];
  const rec: Recording | null = phone ? trip!.recordings![phone]! : null;
  const review = rec?.review;
  const audio = useRef<HTMLAudioElement>(null);
  const transcriptList = useRef<HTMLOListElement>(null);
  const [src, setSrc] = useState<string>();
  const [audioError, setAudioError] = useState<string>();
  const [now, setNow] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [listened, setListened] = useState(false);
  const [readReport, setReadReport] = useState(false);
  const [customer, setCustomer] = useState<Decision["customer"]>();
  const [driver, setDriver] = useState<Decision["driver"]>();
  const [customerNote, setCustomerNote] = useState("");
  const [driverNote, setDriverNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  const flagTimes = [...(rec?.markers ?? []).map((m) => m.at), ...(review?.moments ?? []).map((m) => m.at)];
  const phoneFlag = strongest(rec?.markers ?? []);
  const closed = incident.status === "closed";
  // If this browser can't play the recording, the agent confirms they read the report and transcript instead.
  const mustListen = !!rec && !audioError;
  const canDecide = mustListen ? listened : readReport;

  async function playAt(sec: number) {
    try {
      const url = src ?? (await loadAudio(phone!));
      setSrc(url);
      const el = audio.current!;
      if (el.src !== url) {
        const ready = new Promise((ok, fail) => {
          el.addEventListener("loadedmetadata", ok, { once: true });
          el.addEventListener("error", () => fail(el.error?.message || "the browser couldn't reach or play the file"), { once: true });
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

  // timeupdate fires only ~4 times a second; follow the audio every frame while it plays so the waveform moves smoothly.
  useEffect(() => {
    if (!playing) return;
    let frame = 0;
    const tick = () => {
      setNow(audio.current?.currentTime ?? 0);
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [playing]);

  // The line being played, kept in view inside the transcript list (the page itself doesn't scroll).
  const lines = rec?.transcript ?? [];
  const activeLine = src ? lines.findIndex((l, i) => now >= l.at && now < (lines[i + 1]?.at ?? Infinity)) : -1;
  useEffect(() => {
    const box = transcriptList.current;
    const el = box?.children[activeLine] as HTMLElement | undefined;
    if (box && el) box.scrollTo({ top: el.offsetTop - box.clientHeight / 2 + el.clientHeight / 2, behavior: "smooth" });
  }, [activeLine]);

  // Live: new pieces arrive every ~10 s. Reload the joined audio and keep the agent's place.
  const pieces = rec?.pieces;
  useEffect(() => {
    const el = audio.current;
    if (!src || !el || !phone || !rec?.live) return;
    const at = el.currentTime;
    const wasPlaying = !el.paused;
    loadAudio(phone)
      .then((url) => {
        setSrc(url);
        el.src = url;
        el.load();
        el.addEventListener("loadedmetadata", () => {
          el.currentTime = at;
          if (wasPlaying) void el.play();
        }, { once: true });
      })
      .catch(() => {}); // the next piece tries again
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pieces]);

  function pick(p: Phone) {
    setPicked(p);
    setSrc(undefined);
    audio.current?.pause();
  }

  function toggle() {
    const el = audio.current;
    if (!src || !el) return void playAt(rec?.markers[0]?.at ?? 0);
    if (el.paused) el.play().catch((e: Error) => setAudioError(`Could not play the recording: ${e.message}`));
    else el.pause();
  }

  function onTime() {
    const t = audio.current?.currentTime ?? 0;
    setNow(t);
    if (!audio.current?.paused && flagTimes.some((at) => t >= at && t <= at + LISTEN_WINDOW)) setListened(true);
  }

  // Why "Record decision" is still off, said next to the button instead of a silent grey button.
  // OR, not AND: one side is enough; the side left open means no action for that person.
  const chosen = !!customer || !!driver;
  const dismiss = chosen && (customer ?? "none") === "none" && (driver ?? "none") === "none";
  const driverEmail = !!driver && driver !== "none";
  const missing =
    !chosen ? "Choose a decision for the customer or the driver."
    : !canDecide ? (mustListen ? "Listen to a flagged moment first." : "Tick that you read the report.")
    : "";

  async function submit() {
    if (!chosen) return;
    setBusy(true);
    setError(undefined);
    try {
      await onDecide({ customer: customer ?? "none", driver: driver ?? "none", customerNote, driverNote: driverEmail ? driverNote : "" });
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <main>
      <PageHero
        back
        title={`Ticket ${ticketNo(incident.id)}`}
        sub={`Order ${incident.tripId} · ${raisedBy(incident, trip)} · ${wib.format(incident.createdAt.toDate())} WIB`}
        width="max-w-6xl"
      >
        <span className={`rounded-full px-2.5 py-0.5 text-caption font-semibold ${priorityStyle[priorityOf(incident)].badge}`}>
          {priorityStyle[priorityOf(incident)].text}
        </span>
        <span className="rounded-full bg-canvas px-2.5 py-0.5 text-caption font-semibold text-fg">{triggerText[incident.trigger]}</span>
        <StatusPill status={incident.status} />
        {incident.live && <span className="animate-pulse rounded-full bg-sos px-2.5 py-0.5 text-caption font-semibold text-white">● LIVE: the phone is streaming</span>}
      </PageHero>

      <div className="mx-auto -mt-12 grid w-full max-w-6xl gap-6 px-6 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)]">
        <div className="flex min-w-0 flex-col gap-6">
          <Card title="Ride recording">
            {rec ? (
              <>
                {phones.length > 1 && (
                  <div className="mb-3 flex gap-2" role="tablist" aria-label="Whose phone">
                    {phones.map((p) => (
                      <button
                        key={p}
                        role="tab"
                        aria-selected={p === phone}
                        onClick={() => pick(p)}
                        className={`h-8 rounded-full border px-3 text-caption font-semibold transition-colors duration-200 ${p === phone ? "border-transparent bg-brand-tint text-brand-deep dark:text-brand" : "border-line text-muted hover:border-brand"}`}
                      >
                        {p === "rider" ? "Rider's phone" : "Driver's phone"}
                      </button>
                    ))}
                  </div>
                )}
                <p className="mb-3 text-body-small text-muted">
                  Jump straight to a flag; you don&apos;t need to hear the whole ride. Playback is logged.
                </p>
                <RecordingPlayer rec={rec} src={src} now={now} playing={playing} onSeek={playAt} onToggle={toggle} />
                <audio
                  ref={audio}
                  preload="none"
                  onTimeUpdate={onTime}
                  onPlay={() => setPlaying(true)}
                  onPause={() => setPlaying(false)}
                  className="hidden"
                />
                {audioError && <p role="alert" className="mt-2 text-body-small text-high">{audioError}</p>}
              </>
            ) : (
              <p className="text-body-small text-muted">
                {trip?.recordings
                  ? "The phone is still uploading the ride."
                  : "No recording yet: a reported or high-flag ride uploads when it ends; an SOS streams it live."}
              </p>
            )}
          </Card>

          <Card title="Transcript" className="flex-1">
            {rec ? (
              <ol ref={transcriptList} className="relative flex max-h-[32rem] flex-col gap-1 overflow-y-auto p-1">
                {rec.transcript.map((line, i) => {
                  const marker = rec.markers.find((m) => Math.abs(m.at - line.at) < 0.5);
                  const end = rec.transcript[i + 1]?.at ?? line.end ?? rec.durationSec;
                  const active = i === activeLine;
                  const heard = src && activeLine > i;
                  return (
                    <li key={line.at}>
                      <button
                        onClick={() => playAt(line.at)}
                        className={`relative flex w-full gap-3 overflow-hidden rounded-chip border-l-4 px-3 py-2.5 text-left text-body-small transition-colors duration-200 ${
                          marker ? kindStyle[marker.kind].line : active ? "border-brand bg-brand-tint" : "border-transparent hover:bg-surface"
                        } ${active ? "animate-line-pop font-semibold shadow-low" : ""} ${heard && !marker ? "text-muted" : ""}`}
                      >
                        {active && (
                          <span
                            aria-hidden
                            className="absolute bottom-0 left-0 h-0.5 bg-brand"
                            style={{ width: `${Math.min(100, ((now - line.at) / Math.max(end - line.at, 0.1)) * 100)}%` }}
                          />
                        )}
                        <span className="text-muted tabular-nums">{mmss(line.at)}</span>
                        <span className="flex-1">{line.text}</span>
                        {marker && <span className={`shrink-0 rounded-chip px-2 text-caption font-semibold ${kindStyle[marker.kind].chip}`}>{kindStyle[marker.kind].text}</span>}
                      </button>
                    </li>
                  );
                })}
              </ol>
            ) : (
              <ol className="flex flex-col gap-1 text-body-small">
                {incident.transcript.map((t) => (
                  <li key={t.start} className={`rounded-chip border-l-4 px-3 py-1.5 ${t.flagged ? kindStyle.high.line : "border-transparent"}`}>
                    <span className="mr-3 text-muted tabular-nums">{mmss(t.start)}</span>
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
              <div className="flex flex-col gap-3 text-body-small">
                <Verdict
                  phone={phoneFlag ? `${kindStyle[phoneFlag.kind].text}${phoneFlag.label ? ` · ${labelText[phoneFlag.label]}` : ""}` : incident.label ? labelText[incident.label] : "None"}
                  ai={labelText[review.label]}
                  confidence={review.confidence}
                  agree={isHarmful(review.label) === isHarmful(phoneFlag?.label ?? incident.label)}
                />
                <p>{review.summary}</p>
                {review.moments.length > 0 && (
                  <div>
                    <h3 className="mb-1 font-semibold">Why (click to listen)</h3>
                    <ul className="flex flex-col gap-1">
                      {review.moments.map((m) => (
                        <li key={m.at} className="flex gap-2">
                          <button onClick={() => playAt(m.at)} className="font-semibold text-brand-deep underline tabular-nums dark:text-brand">
                            {mmss(m.at)}
                          </button>
                          <span>
                            <span className="font-semibold">{labelText[m.label]}:</span> {m.reason}
                          </span>
                        </li>
                      ))}
                    </ul>
                  </div>
                )}
                {review.note && <p className="text-caption text-muted">{review.note}</p>}
                <p className="rounded-chip bg-surface p-3 text-caption">
                  AI can be wrong. Listen to the flagged moments yourself before deciding.
                </p>
              </div>
            ) : (
              <p className="text-body-small text-muted">
                {rec ? "Reviewing the ride…" : "Appears once the full recording has been uploaded."}
              </p>
            )}
          </Card>

          <PhoneReport who="Rider's phone" role="Customer" person={trip ? people[trip.riderId] : undefined} reports={byPhone(incident, trip?.riderId)} />
          <PhoneReport who="Driver's phone" role="Driver" person={trip ? people[trip.driverId] : undefined} reports={byPhone(incident, trip?.driverId)} />
        </div>
      </div>

      <div className="mx-auto w-full max-w-6xl px-6 pt-6 pb-48">
        <Card title="Decision">
          {closed ? (
            <p className="text-body-small">This case is closed.</p>
          ) : (
            <>
              <div className="grid items-stretch gap-x-8 gap-y-6 lg:grid-cols-2">
                <div className="flex flex-col gap-4 rounded-card border border-line bg-surface p-5">
                  <Choices legend="Customer" name="customer" options={CUSTOMER} value={customer} onChange={setCustomer} />
                  <Message label="Message to the customer" hint="Optional. Goes into the customer's email." value={customerNote} onChange={setCustomerNote} grow />
                </div>
                <div className="flex flex-col gap-4 rounded-card border border-line bg-surface p-5">
                  <Choices legend="Driver" name="driver" options={DRIVER} value={driver} onChange={setDriver} />
                  <Message
                    label="Message to the driver"
                    hint={driverEmail ? "Optional. Goes into the driver's email." : "No email goes to the driver unless you pick an action for them."}
                    value={driverEmail ? driverNote : ""}
                    onChange={setDriverNote}
                    disabled={!driverEmail}
                  />
                </div>
              </div>
              <div className="mt-6 flex flex-wrap items-center gap-x-6 gap-y-3 border-t border-line pt-5">
                {mustListen ? (
                  <p className={`text-body-small ${listened ? "text-brand-deep dark:text-brand" : "text-muted"}`}>
                    {listened ? "✓ You listened to a flagged moment." : "Listen to at least one flagged moment to decide."}
                  </p>
                ) : (
                  <label className="flex gap-2 text-body-small">
                    <input type="checkbox" checked={readReport} onChange={(e) => setReadReport(e.target.checked)} />
                    {audioError ? "The recording won't play in this browser. I read the phone's report and transcript." : "I read the phone's report and transcript."}
                  </label>
                )}
                <p className="text-body-small text-muted">
                  {driverEmail
                    ? "The customer and the driver each get an email."
                    : dismiss
                      ? "Dismiss: the customer is told we reviewed it and nothing needs further action. The driver gets nothing."
                      : "Only the customer gets an email."}
                </p>
                {error && <p role="alert" className="text-body-small text-high">{error}</p>}
                {missing && <p className="text-body-small font-semibold text-warn sm:ml-auto">{missing}</p>}
                <button
                  disabled={!chosen || !canDecide || busy}
                  onClick={submit}
                  className={`h-10 rounded-full px-6 text-title-tiny font-semibold text-white disabled:opacity-40 ${missing ? "" : "sm:ml-auto"} ${
                    driver === "suspend" ? "bg-danger hover:bg-sos" : "bg-brand-strong hover:bg-brand-deep"
                  }`}
                >
                  {busy ? "Saving…" : driver === "suspend" ? "Record decision and suspend driver" : dismiss ? "Dismiss case" : "Record decision"}
                </button>
              </div>
            </>
          )}
        </Card>
      </div>
    </main>
  );
}

function strongest(markers: Marker[]): Marker | undefined {
  const rank = { sos: 3, high: 2, manual_unsafe: 1, warning: 0 } as const;
  return [...markers].sort((a, b) => rank[b.kind] - rank[a.kind])[0];
}

/** How this ticket was raised: automatically by a phone's flag, or by a person pressing a button. */
function raisedBy(incident: Incident, trip: Trip | null): string {
  const who = incident.reportedBy === trip?.riderId ? "rider" : incident.reportedBy === trip?.driverId ? "driver" : "phone";
  if (incident.trigger === "auto") return `Raised automatically: the ${who}'s phone flagged this ride`;
  if (incident.trigger === "sos") return `Raised by the ${who} with SOS (they get a ticket email)`;
  return `Raised by the ${who} with "I feel unsafe"`;
}

type Report = NonNullable<Incident["reports"]>[number];

/** The reports one phone made on this ride (one case per ride; older cases have only `reportedBy`). */
function byPhone(incident: Incident, uid: string | undefined): Report[] {
  const all = incident.reports ?? [{ trigger: incident.trigger, by: incident.reportedBy, label: incident.label, score: incident.score, at: incident.createdAt }];
  return uid ? all.filter((r) => r.by === uid) : [];
}

function PhoneReport({ who, role, person, reports }: { who: string; role: string; person?: Person; reports: Report[] }) {
  const name = person?.displayName?.replace(/\s*\(.*\)$/, ""); // seed names read "Rina (rider)"; a real phone user may have no name yet
  return (
    <Card title={who} aside={<span className="rounded-full bg-surface px-2.5 py-0.5 text-caption font-semibold">{role}</span>}>
      <div className="-mt-1 flex items-center gap-3 rounded-chip bg-surface px-3 py-2">
        <span aria-hidden className="flex size-10 shrink-0 items-center justify-center rounded-full bg-brand-tint text-brand-deep dark:text-brand">
          <svg viewBox="0 0 24 24" className="size-5 fill-current">
            <path d="M6.6 10.8a15.1 15.1 0 0 0 6.6 6.6l2.2-2.2c.3-.3.7-.4 1-.2 1.1.4 2.3.6 3.6.6.6 0 1 .4 1 1V20c0 .6-.4 1-1 1A17 17 0 0 1 3 4c0-.6.4-1 1-1h3.5c.6 0 1 .4 1 1 0 1.3.2 2.5.6 3.6.1.3 0 .7-.2 1l-2.3 2.2Z" />
          </svg>
        </span>
        <div className="min-w-0">
          <p className="text-body-small text-muted">{name ?? "Name not available"}</p>
          {person?.phone ? (
            <a href={`tel:${person.phone.replace(/[^+\d]/g, "")}`} className="text-title-small font-semibold tabular-nums hover:underline">
              {person.phone}
            </a>
          ) : (
            <p className="text-title-tiny font-semibold text-muted">No phone number</p>
          )}
        </div>
      </div>
      <div className="mt-3 text-body-small">
        {reports.length === 0 ? (
          <p className="text-muted">No report from this phone on this ride.</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {reports.map((r, i) => (
              <li key={i} className="flex flex-wrap items-center gap-2">
                <span className="rounded-full bg-surface px-2 py-0.5 text-caption font-semibold">{triggerText[r.trigger]}</span>
                {r.at && <span className="text-caption text-muted tabular-nums">{wib.format(r.at.toDate())} WIB</span>}
                {r.label && <span className="text-caption text-muted">· {labelText[r.label]}{r.score != null ? ` ${Math.round(r.score * 100)}%` : ""}</span>}
              </li>
            ))}
          </ul>
        )}
      </div>
    </Card>
  );
}

function Choices<T extends string>({ legend, name, options, value, onChange }: {
  legend: string;
  name: string;
  options: { value: T; text: string; hint: string }[];
  value: T | undefined;
  /** `undefined` when the agent clicks the picked option again to clear it (no decision for this side). */
  onChange: (v: T | undefined) => void;
}) {
  return (
    <fieldset className="grid gap-2 sm:grid-cols-2">
      <legend className="mb-3 flex w-full items-center gap-2 border-b border-line pb-3 text-title-small font-semibold">
        <span aria-hidden className="h-5 w-1 rounded-full bg-brand" />
        {legend}
        {value && <span className="ml-auto text-caption font-normal text-muted">Click again to clear</span>}
      </legend>
      {options.map((o) => (
        <label key={o.value} className="flex cursor-pointer gap-2 rounded-card border border-line bg-canvas p-3 text-body-small hover:border-brand has-[:checked]:border-brand has-[:checked]:bg-brand-tint">
          <input
            type="radio"
            name={name}
            value={o.value}
            checked={value === o.value}
            onChange={() => onChange(o.value)}
            onClick={() => value === o.value && onChange(undefined)} // a radio can't be unchecked by itself
          />
          <span>
            <span className="font-semibold">{o.text}</span>
            <span className="block text-muted">{o.hint}</span>
          </span>
        </label>
      ))}
    </fieldset>
  );
}

function Message({ label, hint, value, onChange, disabled = false, grow = false }: {
  label: string;
  hint: string;
  value: string;
  onChange: (v: string) => void;
  disabled?: boolean;
  /** Fill the rest of the block, so side-by-side blocks end level. */
  grow?: boolean;
}) {
  return (
    <label className={`flex flex-col gap-1 text-body-small font-semibold ${disabled ? "opacity-50" : ""} ${grow ? "flex-1" : ""}`}>
      {label}
      <textarea
        value={value}
        onChange={(e) => onChange(e.target.value)}
        maxLength={2000}
        disabled={disabled}
        className={`min-h-24 rounded-chip border border-line bg-canvas p-3 font-normal ${grow ? "flex-1" : ""}`}
      />
      <span className="text-caption font-normal text-muted">{hint}</span>
    </label>
  );
}

function Verdict({ phone, ai, confidence, agree }: { phone: string; ai: string; confidence: number; agree: boolean }) {
  return (
    <div className="grid grid-cols-2 gap-2">
      <div className="rounded-chip border border-line p-3">
        <div className="text-caption text-muted">Phone flagged</div>
        <div className="font-semibold">{phone}</div>
      </div>
      <div className="rounded-chip border border-line p-3">
        <div className="text-caption text-muted">AI reads it as</div>
        <div className="font-semibold">{ai}</div>
        <div className="mt-1 h-1.5 rounded-full bg-line">
          <div className="h-1.5 rounded-full bg-brand" style={{ width: `${Math.round(confidence * 100)}%` }} />
        </div>
        <div className="text-caption text-muted">{Math.round(confidence * 100)}% confident</div>
      </div>
      <div className={`col-span-2 rounded-full px-3 py-1 text-caption font-semibold ${agree ? "bg-brand-tint text-fg" : "bg-warn-tint text-fg"}`}>
        {agree ? "The AI agrees with the phone's flag." : "The AI reads this differently from the phone. Listen carefully."}
      </div>
    </div>
  );
}

function SourceBadge({ review }: { review: Review }) {
  const text = { "sahabat-ai": "Sahabat-AI", gemini: "Gemini", rules: "Rule-based" }[review.source];
  return <span className="rounded-chip bg-surface px-2 py-0.5 text-caption font-semibold">{text}</span>;
}

function Card({ title, aside, className = "", children }: { title: string; aside?: React.ReactNode; className?: string; children: React.ReactNode }) {
  return (
    <section className={`rounded-card border border-line bg-canvas p-5 shadow-low ${className}`}>
      <div className="mb-3 flex items-center gap-2">
        <h2 className="text-title-small font-semibold">{title}</h2>
        <span className="ml-auto">{aside}</span>
      </div>
      {children}
    </section>
  );
}
