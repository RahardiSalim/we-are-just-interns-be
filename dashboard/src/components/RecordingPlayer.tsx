"use client";

import { useEffect, useState, type KeyboardEvent, type MouseEvent } from "react";
import { kindStyle, labelText, mmss } from "@/lib/labels";
import type { Recording } from "@/types/firestore";

const BARS = 48;
/** Seconds after a flag drawn in the flag's colour (same as the "listened" window in CaseView). */
const FLAG_SPAN = 3;

/** Loudness per bar (0–1), decoded in the browser with Web Audio. Null until the agent loads the audio. */
function usePeaks(src: string | undefined) {
  const [peaks, setPeaks] = useState<number[] | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    if (!src) return;
    let off = false;
    (async () => {
      try {
        const ctx = new AudioContext();
        const ch = (await ctx.decodeAudioData(await (await fetch(src)).arrayBuffer())).getChannelData(0);
        void ctx.close();
        const step = Math.max(1, Math.floor(ch.length / BARS));
        const rms = Array.from({ length: BARS }, (_, i) => {
          let sum = 0;
          for (let j = i * step; j < Math.min(ch.length, (i + 1) * step); j++) sum += ch[j] * ch[j];
          return Math.sqrt(sum / step);
        });
        const max = Math.max(...rms, 1e-6);
        if (!off) setPeaks(rms.map((v) => Math.max(0.12, v / max)));
      } catch {
        if (!off) setFailed(true); // e.g. the storage host sends no CORS header; playback still works
      }
    })();
    return () => {
      off = true;
    };
  }, [src]);

  return { peaks, failed };
}

/**
 * The ride as a waveform of rounded bars: unplayed grey, played green (filled smoothly as the playhead
 * passes), flagged moments in their flag colour. Click, hover or use the arrow keys to seek.
 */
export function RecordingPlayer({ rec, src, now, playing, onSeek, onToggle }: {
  rec: Recording;
  src: string | undefined;
  now: number;
  playing: boolean;
  onSeek: (sec: number) => void;
  onToggle: () => void;
}) {
  const { peaks, failed } = usePeaks(src);
  const [hover, setHover] = useState<number | null>(null);
  const dur = Math.max(rec.durationSec, 1);
  const pct = (sec: number) => Math.min(100, (sec / dur) * 100);
  const nowBar = Math.floor((now / dur) * BARS);
  const bars = Array.from({ length: BARS }, (_, i) => {
    const sec = ((i + 0.5) / BARS) * dur;
    return { h: peaks?.[i] ?? 0.12, flag: rec.markers.find((m) => sec >= m.at && sec <= m.at + FLAG_SPAN) };
  });

  const secAt = (e: MouseEvent<HTMLDivElement>) => {
    const box = e.currentTarget.getBoundingClientRect();
    return Math.min(dur, Math.max(0, ((e.clientX - box.left) / box.width) * dur));
  };

  function seekFromKey(e: KeyboardEvent<HTMLDivElement>) {
    const jump = { ArrowRight: 5, ArrowLeft: -5, Home: -dur, End: dur }[e.key];
    if (jump == null) return;
    e.preventDefault();
    onSeek(Math.min(dur, Math.max(0, now + jump)));
  }

  /** One row of bars. `played` draws only the green layer, clipped to the playhead by the caller. */
  const row = (played: boolean) => (
    <div aria-hidden className="absolute inset-x-4 inset-y-3 flex items-center justify-between">
      {bars.map((b, i) => (
        <span
          key={i}
          style={{ height: `${b.h * 100}%` }}
          className={`w-[1.1%] min-w-[3px] rounded-full ${
            played ? (b.flag ? "bg-transparent" : "bg-brand") : b.flag ? kindStyle[b.flag.kind].dot : "bg-muted/35"
          } ${playing && Math.abs(i - nowBar) <= 1 ? "animate-bar" : ""} transition-[height] duration-300 ease-out`}
        />
      ))}
    </div>
  );

  return (
    <div>
      <div className="flex items-center gap-3">
        <button
          onClick={onToggle}
          aria-label={playing ? "Pause" : src ? "Play" : "Load the recording and play the first flag"}
          className="flex size-11 shrink-0 items-center justify-center rounded-full bg-brand-tint text-brand-deep transition-colors duration-200 hover:bg-brand-strong hover:text-white dark:text-brand"
        >
          <svg aria-hidden viewBox="0 0 24 24" className="size-5 fill-current">
            <path d={playing ? "M6 5h4v14H6V5Zm8 0h4v14h-4V5Z" : "M8 5.1v13.8L19 12 8 5.1Z"} />
          </svg>
        </button>
        <div>
          <p className="text-title-tiny font-semibold">{src ? (playing ? "Playing" : "Paused") : "Load recording"}</p>
          <p className="text-caption text-muted tabular-nums">
            {mmss(now)} / {mmss(rec.durationSec)}
          </p>
        </div>
      </div>

      <div className="relative mt-4 pt-5">
        {rec.markers.map((m) => (
          <button
            key={`pin-${m.kind}-${m.at}`}
            onClick={() => onSeek(m.at)}
            aria-label={`Play ${kindStyle[m.kind].text} at ${mmss(m.at)}`}
            title={`${kindStyle[m.kind].text} at ${mmss(m.at)}`}
            className={`absolute top-0 z-10 size-3.5 -translate-x-1/2 rounded-full ring-2 ring-canvas transition-transform duration-150 hover:scale-125 ${kindStyle[m.kind].dot}`}
            style={{ left: `${pct(m.at)}%` }}
          />
        ))}

        <div
          role="slider"
          tabIndex={0}
          aria-label="Ride recording position"
          aria-valuemin={0}
          aria-valuemax={rec.durationSec}
          aria-valuenow={Math.round(now)}
          aria-valuetext={`${mmss(now)} of ${mmss(rec.durationSec)}`}
          onClick={(e) => onSeek(secAt(e))}
          onMouseMove={(e) => setHover(secAt(e))}
          onMouseLeave={() => setHover(null)}
          onKeyDown={seekFromKey}
          className="relative h-32 cursor-pointer overflow-hidden rounded-card bg-surface"
        >
          {row(false)}
          {/* Green layer, revealed up to the playhead every frame, so bars fill smoothly. */}
          <div className="absolute inset-0" style={{ clipPath: `inset(0 ${100 - pct(now)}% 0 0)` }}>
            {row(true)}
          </div>
          {hover != null && (
            <>
              <span aria-hidden className="pointer-events-none absolute inset-y-0 w-px bg-fg/30" style={{ left: `${pct(hover)}%` }} />
              <span
                className="pointer-events-none absolute top-1 -translate-x-1/2 rounded-chip bg-ink px-1.5 py-0.5 text-caption text-white tabular-nums"
                style={{ left: `${pct(hover)}%` }}
              >
                {mmss(hover)}
              </span>
            </>
          )}
          {src && <span aria-hidden className="pointer-events-none absolute inset-y-0 w-0.5 -translate-x-1/2 bg-fg" style={{ left: `${pct(now)}%` }} />}
        </div>

        <div className="mt-1 flex justify-between text-caption text-muted tabular-nums">
          <span>00:00</span>
          <span>{mmss(rec.durationSec)}</span>
        </div>
        {failed && <p className="mt-1 text-caption text-muted">The waveform couldn&apos;t be drawn for this file; playback still works.</p>}
      </div>

      <div className="mt-3 flex flex-wrap gap-2">
        {rec.markers.map((m) => (
          <button
            key={`chip-${m.kind}-${m.at}`}
            onClick={() => onSeek(m.at)}
            className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-caption font-semibold ${kindStyle[m.kind].chip}`}
          >
            <span aria-hidden className={`size-2 rounded-full ${kindStyle[m.kind].dot}`} />
            <span className="tabular-nums">{mmss(m.at)}</span> {kindStyle[m.kind].text}
            {m.label ? ` · ${labelText[m.label]}` : ""}
            {m.score != null ? ` ${Math.round(m.score * 100)}%` : ""}
          </button>
        ))}
      </div>
    </div>
  );
}
