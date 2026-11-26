"""Run the STT pipeline on the DataHive Indonesian conversations, one channel at a time.

Dataset: https://huggingface.co/datasets/datahiveai/indonesian-conversations-sample
(CC BY 4.0: credit DataHive). 11 unscripted phone conversations in Indonesian, 3 h 3 min, stereo
48 kHz mp3, caller on the left and callee on the right, recorded separately. No transcripts.
Never commit the audio or the output (stt/.gitignore blocks them).

Each channel is one speaker, so each is transcribed on its own and merged by time. That is easier
than one phone on a motorbike, where both voices share a microphone.

Needs: pywhispercpp, torch, silero-vad, scipy, soundfile (mp3 needs libsndfile 1.1 or newer) and a
ggml model, see ../models/README.md.

Usage (from stt/):
  python tools/datahive_run.py --data_dir <folder with the mp3 and metadata.jsonl> \
      --model models/maleo-small-id-q8_0/ggml-small-id-q8_0.bin --out_dir convo_out \
      [--files id_000006.mp3 ...] [--max_s 90]

Writes <out_dir>/<name>/{kiri,kanan}.json (one window per channel), <name>/dialog.txt (both
channels merged by time, for listening checks) and <out_dir>/summary.csv.
"""
import argparse
import csv
import json
import os
import statistics as st
import sys
import time

import numpy as np
import soundfile as sf
from scipy import signal

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import stt_service as S  # noqa: E402

CHANNELS = [("kiri", "caller"), ("kanan", "callee")]  # left, right


def load_channels_16k(path, max_s=None):
    """Decode in 60 s blocks to keep memory low, then resample 48 kHz to 16 kHz per channel."""
    out = [[], []]
    with sf.SoundFile(path) as f:
        sr, block, total = f.samplerate, 60 * f.samplerate, 0
        while True:
            x = f.read(block, dtype="float32", always_2d=True)
            if len(x) == 0:
                break
            g = np.gcd(sr, S.SR)
            for c in (0, 1):
                out[c].append(signal.resample_poly(x[:, c], S.SR // g, sr // g).astype("float32"))
            total += len(x)
            if max_s and total >= max_s * sr:
                break
    arrs = [np.concatenate(o) for o in out]
    return [a[: int(max_s * S.SR)] for a in arrs] if max_s else arrs


def intersect_seconds(a, b):
    """Total time two sorted lists of (start, end) intervals are both active."""
    i = j = 0
    tot = 0.0
    while i < len(a) and j < len(b):
        tot += max(0.0, min(a[i][1], b[j][1]) - max(a[i][0], b[j][0]))
        if a[i][1] < b[j][1]:
            i += 1
        else:
            j += 1
    return tot


def fmt(s):
    s = int(s)
    return f"{s // 3600:02d}:{s % 3600 // 60:02d}:{s % 60:02d}" if s >= 3600 else f"{s // 60:02d}:{s % 60:02d}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data_dir", required=True, help="folder with the mp3 files and metadata.jsonl")
    ap.add_argument("--model", required=True, help="ggml .bin file for whisper.cpp")
    ap.add_argument("--out_dir", required=True)
    ap.add_argument("--files", nargs="*", default=None, help="mp3 names; default: all, in the order of metadata.jsonl")
    ap.add_argument("--max_s", type=float, default=None, help="only the first N seconds of each file (quick test)")
    a = ap.parse_args()
    os.makedirs(a.out_dir, exist_ok=True)

    backend = S.WhisperCppBackend(a.model)  # backend first, then the VAD (see the SileroVAD thread note)
    vad = S.SileroVAD()
    meta = {r["file_name"]: r for r in map(json.loads, open(os.path.join(a.data_dir, "metadata.jsonl"), encoding="utf-8"))}
    rows = []
    for fn in a.files or list(meta):
        t0 = time.perf_counter()
        name = fn.replace(".mp3", "")
        chans = load_channels_16k(os.path.join(a.data_dir, fn), a.max_s)
        dur = len(chans[0]) / S.SR
        segs, spans, flag_count, status = [], [], {}, {}
        os.makedirs(os.path.join(a.out_dir, name), exist_ok=True)
        for (side, role), audio in zip(CHANNELS, chans):
            win = S.process_window(audio, backend, vad, trip_id=f"{name}_{side}", channel=f"{role}_{side}", speaker="unknown")
            json.dump(win, open(os.path.join(a.out_dir, name, f"{side}.json"), "w", encoding="utf-8"), ensure_ascii=False)
            status[side] = win["window_summary"]["status"]
            for s in win["segments"]:
                segs.append((s["start_s"], side, s))
                for fl in s["flags"]:
                    flag_count[fl] = flag_count.get(fl, 0) + 1
            spans.append([(s["start_s"], s["end_s"]) for s in win["segments"]])
        segs.sort(key=lambda x: x[0])

        with open(os.path.join(a.out_dir, name, "dialog.txt"), "w", encoding="utf-8") as f:
            f.write(f"# {fn}  {fmt(dur)}  topic: {meta[fn]['topic']}  (KIRI = caller, KANAN = callee)\n")
            for s0, side, s in segs:
                tag = "" if "excluded_from_classifier" not in s["flags"] else "  [EXCLUDED: " + ",".join(x for x in s["flags"] if x != "excluded_from_classifier") + "]"
                f.write(f"[{fmt(s0)}-{fmt(s['end_s'])}] {side.upper():5} {s['text_raw']}{tag}\n")

        # Segments are padded by 0.25 s on both sides, so a padded gap below 0 is a raw gap below 0.5 s.
        gaps = [segs[i + 1][0] - segs[i][2]["end_s"] for i in range(len(segs) - 1) if segs[i + 1][1] != segs[i][1]]
        both = intersect_seconds(spans[0], spans[1])
        proc = time.perf_counter() - t0
        rows.append({"file": fn, "minutes": round(dur / 60, 1), "segments_left": len(spans[0]), "segments_right": len(spans[1]),
                     "speech_left_s": round(sum(e - b for b, e in spans[0]), 1), "speech_right_s": round(sum(e - b for b, e in spans[1]), 1),
                     "speaker_changes": len(gaps), "padded_gap_median_ms": round(1000 * st.median(gaps)) if gaps else "",
                     "changes_under_0.5s_%": round(100 * sum(g < 0 for g in gaps) / len(gaps), 1) if gaps else "",
                     "both_speaking_%": round(100 * both / dur, 1), "meta_gap_ms": meta[fn]["turn_taking_gap_ms"],
                     "meta_overlap_%": meta[fn]["overlap_percent"], "status_left": status["kiri"], "status_right": status["kanan"],
                     "flags": json.dumps(flag_count), "seconds": round(proc), "rtf": round(proc / dur, 2)})
        print(f"{fn}: {dur / 60:.1f} min audio, {proc:.0f} s (RTF {proc / dur:.2f}), segments {len(spans[0])}+{len(spans[1])}, flags {flag_count}", flush=True)
        with open(os.path.join(a.out_dir, "summary.csv"), "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)
    print("DONE")


if __name__ == "__main__":
    main()
