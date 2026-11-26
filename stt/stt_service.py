"""GoSafe STT service.

audio file -> VAD segments -> STT per segment -> filters -> window JSON.

The JSON follows the contract "gosafe.stt.window.v1". Two text views are made
from it: one for the classifier/LLM (render_llm_view) and a compact one for a
small classifier (render_classifier_view).

Examples
  # test the logic without any model
  python stt_service.py --audio ride.wav --trip_id T1 --backend dummy \
      --dummy_texts texts.json --speaker driver --view llm

  # real model on Colab (GPU). Backend "hf" needs: pip install transformers torch
  python stt_service.py --audio ride.wav --trip_id T1 --backend hf \
      --model maleo-ai/whisper-small-id --speaker passenger --view llm

  # backend "faster" gives avg_logprob and no_speech_prob (needs a CTranslate2
  # model folder and: pip install faster-whisper)
  python stt_service.py --audio ride.wav --backend faster --model ./whisper-id-ct2

  # backend "whispercpp" runs a ggml build, for example the 264 MB q8_0 of maleo
  # (needs: pip install pywhispercpp; file and hash are pinned in models/README.md)
  python stt_service.py --audio ride.wav --backend whispercpp --model ./ggml-small-id-q8_0.bin

Notes
- Segment confidence is a simple heuristic, not a calibrated probability.
- The speaker tag is only a hint given by --speaker (for example the phone that
  recorded the file). It is NOT speaker recognition.
- PII masking here is basic (phone numbers, plates with a region code, emails). Names
  and addresses need an NER step in the backend.
"""
import argparse
import json
import math
import re
import time
import zlib
from datetime import datetime, timezone

import numpy as np
import soundfile as sf
from scipy import signal

SR = 16000
SCHEMA = "gosafe.stt.window.v1"

DEFAULT_SLANG = {
    "gak": "tidak", "ga": "tidak", "nggak": "tidak", "enggak": "tidak", "engga": "tidak",
    "udah": "sudah", "udh": "sudah", "dah": "sudah", "sdh": "sudah",
    "banget": "sekali", "bgt": "sekali", "aja": "saja", "doang": "saja",
    "gimana": "bagaimana", "gmn": "bagaimana", "kayak": "seperti", "kaya": "seperti",
    "emang": "memang", "yg": "yang", "dgn": "dengan", "krn": "karena", "tp": "tapi",
    "lu": "kamu", "lo": "kamu", "elu": "kamu", "gue": "saya", "gw": "saya",
}
# Do not add harassment or insult words to the slang map. Keep them as spoken.

HALLUCINATION_PHRASES = [
    "terima kasih telah menonton", "terima kasih sudah menonton",
    "jangan lupa subscribe", "like dan subscribe", "sampai jumpa di video berikutnya",
    "subtitle by", "amara.org",
]

EXCLUDE_FLAGS = {"empty", "hallucination_lexicon_match", "likely_no_speech", "repetition_suspect"}


# ----------------------------------------------------------------- audio / VAD
def load_mono_16k(path):
    x, sr = sf.read(path, dtype="float32", always_2d=False)
    if x.ndim > 1:
        x = x.mean(axis=1)
    if sr != SR:
        g = np.gcd(sr, SR)
        x = signal.resample_poly(x, SR // g, sr // g).astype("float32")
    return x


def mask_to_spans(mask, hop_s):
    padded = np.concatenate([[0], mask.astype(int), [0]])
    d = np.diff(padded)
    starts, ends = np.where(d == 1)[0], np.where(d == -1)[0]
    return [(s * hop_s, e * hop_s) for s, e in zip(starts, ends)]


class EnergyVAD:
    """Simple energy VAD. Good for tests; use SileroVAD for real audio."""
    name = "energy"

    def __init__(self, frame_ms=30, offset_db=10.0, floor_db=-55.0):
        self.frame = int(SR * frame_ms / 1000)
        self.hop_s = frame_ms / 1000
        self.offset_db, self.floor_db = offset_db, floor_db

    def speech_spans(self, audio):
        n = len(audio) // self.frame
        if n == 0:
            return []
        frames = audio[: n * self.frame].reshape(n, self.frame)
        db = 20 * np.log10(np.sqrt((frames ** 2).mean(axis=1)) + 1e-9)
        thr = max(np.percentile(db, 20) + self.offset_db, self.floor_db)
        return mask_to_spans(db > thr, self.hop_s)


class SileroVAD:
    name = "silero"

    def __init__(self, threshold=0.5):
        import torch
        n_threads = torch.get_num_threads()  # importing silero_vad drops this to 1 process-wide,
        from silero_vad import get_speech_timestamps, load_silero_vad
        self.torch, self.fn, self.model, self.threshold = torch, get_speech_timestamps, load_silero_vad(), threshold
        torch.set_num_threads(n_threads)  # which would otherwise also slow down the STT backend afterwards.

    def speech_spans(self, audio):
        ts = self.fn(self.torch.from_numpy(audio), self.model, sampling_rate=SR,
                     threshold=self.threshold, return_seconds=True)
        return [(t["start"], t["end"]) for t in ts]


def build_segments(spans, total_s, min_silence=0.5, pad=0.25, min_dur=0.5, max_len=20.0):
    merged = []
    for s, e in spans:
        if merged and s - merged[-1][1] < min_silence:
            merged[-1] = (merged[-1][0], e)
        else:
            merged.append((s, e))
    out = []
    for s, e in merged:
        if e - s < min_dur:
            continue
        s, e = max(0.0, s - pad), min(total_s, e + pad)
        n = max(1, math.ceil((e - s) / max_len))
        step = (e - s) / n
        out.extend((s + i * step, s + (i + 1) * step) for i in range(n))
    return out


# --------------------------------------------------------------------- backends
class DummyBackend:
    """Returns given texts in order. For tests only."""
    name = "dummy"

    def __init__(self, texts):
        self.texts, self.i = texts, 0

    def transcribe(self, audio):
        item = self.texts[self.i % len(self.texts)] if self.texts else ""
        self.i += 1
        return item if isinstance(item, dict) else {"text": item, "avg_logprob": -0.4, "no_speech_prob": 0.05}


class HFBackend:
    def __init__(self, model_id):
        import torch
        from transformers import pipeline
        self.name = model_id
        dev = 0 if torch.cuda.is_available() else -1
        self.pipe = pipeline("automatic-speech-recognition", model=model_id, device=dev)

    def transcribe(self, audio):
        out = self.pipe({"raw": audio, "sampling_rate": SR},
                        generate_kwargs={"language": "indonesian", "task": "transcribe"})
        return {"text": out["text"].strip(), "avg_logprob": None, "no_speech_prob": None}


class FasterWhisperBackend:
    def __init__(self, model_path):
        from faster_whisper import WhisperModel
        self.name = model_path
        self.model = WhisperModel(model_path, device="auto", compute_type="auto")

    def transcribe(self, audio):
        segs, _ = self.model.transcribe(audio, language="id", beam_size=1, vad_filter=False,
                                        condition_on_previous_text=False)
        segs = list(segs)
        if not segs:
            return {"text": "", "avg_logprob": None, "no_speech_prob": None}
        return {"text": " ".join(s.text.strip() for s in segs),
                "avg_logprob": float(np.mean([s.avg_logprob for s in segs])),
                "no_speech_prob": float(max(s.no_speech_prob for s in segs))}


class WhisperCppBackend:
    """whisper.cpp (ggml) via pywhispercpp (pip: pywhispercpp). model_path is a ggml .bin file,
    for example ggml-small-id-q8_0.bin from maleo-ai/whisper-small-id (see models/README.md).
    Like the hf backend it gives no avg_logprob, so segment_confidence stays at 0.7."""

    def __init__(self, model_path, threads=4):
        from pywhispercpp.model import Model
        self.name = "whisper.cpp " + str(model_path).replace("\\", "/").rsplit("/", 1)[-1]
        self.model = Model(model_path, n_threads=threads, language="id", print_progress=False,
                           print_realtime=False, print_timestamps=False)

    def transcribe(self, audio):
        text = " ".join(s.text.strip() for s in self.model.transcribe(audio)).strip()
        return {"text": text, "avg_logprob": None, "no_speech_prob": None}


# ------------------------------------------------------------- text processing
def normalize(text, slang=DEFAULT_SLANG):
    parts = re.split(r"(\[[A-Z_]+\])", text)  # keep placeholders like [TELEPON]
    out = []
    for p in parts:
        if re.fullmatch(r"\[[A-Z_]+\]", p):
            out.append(p)
        else:
            p = re.sub(r"[^\w\s]", " ", p.lower())
            out.extend(slang.get(w, w) for w in p.split())
    return " ".join(out)


PHONE_RE = re.compile(r"(?:\+62|62|0)\s?8[\d\s\-]{8,13}\d")
# STT often writes plates in lowercase and gets the last letters wrong ("b1234 xc"),
# so match any case. To avoid masking normal words ("di 5 km", "rt 5"), the prefix
# must be a real Indonesian region code. The letter suffix is optional.
PLATE_REGIONS = ("AA AB AD AE AG BA BB BD BE BG BH BK BL BM BN BP DA DB DD DE DG DH DK DL DM DN DR DS DT "
                 "EA EB ED KB KH KT KU PA PB A B D E F G H K L M N P R S T W Z").split()
PLATE_RE = re.compile(r"\b(?:" + "|".join(PLATE_REGIONS) + r")\s?\d{1,4}(?:\s?[A-Z]{1,3})?\b", re.IGNORECASE)
EMAIL_RE = re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+")


def mask_pii(text):
    text = EMAIL_RE.sub("[EMAIL]", text)
    text = PHONE_RE.sub("[TELEPON]", text)
    return PLATE_RE.sub("[PLAT]", text)


def compression_ratio(text):
    b = text.encode("utf-8")
    return round(len(b) / max(1, len(zlib.compress(b))), 2) if b else 0.0


def make_flags(text, dur, res, phrases):
    flags = []
    words = text.split()
    low = text.lower()
    if not words:
        return ["empty"]
    if any(p in low for p in phrases):
        flags.append("hallucination_lexicon_match")
    if compression_ratio(text) > 2.4:
        flags.append("repetition_suspect")
    wps = len(words) / max(dur, 1e-6)
    if wps > 6 or (dur >= 2 and wps < 0.3):
        flags.append("rate_suspect")
    lp, nsp = res.get("avg_logprob"), res.get("no_speech_prob")
    if nsp is not None and lp is not None and nsp > 0.6 and lp < -1.0:
        flags.append("likely_no_speech")
    elif lp is not None and lp < -1.0:
        flags.append("low_confidence")
    return flags


def segment_confidence(res, flags):
    lp, nsp = res.get("avg_logprob"), res.get("no_speech_prob")
    c = math.exp(lp) if lp is not None else 0.7
    if nsp is not None:
        c *= 1 - nsp
    if "hallucination_lexicon_match" in flags or "empty" in flags:
        c = min(c, 0.1)
    if "repetition_suspect" in flags or "rate_suspect" in flags:
        c -= 0.3
    return round(max(0.0, min(1.0, c)), 2)


# -------------------------------------------------------------------- pipeline
def process_window(audio, backend, vad, trip_id="trip", channel="unknown", speaker="unknown",
                   speaker_conf=0.5, offset_s=0.0, phrases=HALLUCINATION_PHRASES, service="goride"):
    t_all = time.perf_counter()
    total = len(audio) / SR
    spans = build_segments(vad.speech_spans(audio), total)
    segments = []
    for i, (s, e) in enumerate(spans):
        t0 = time.perf_counter()
        res = backend.transcribe(audio[int(s * SR):int(e * SR)])
        lat = time.perf_counter() - t0
        raw = res["text"].strip()
        flags = make_flags(raw, e - s, res, phrases)
        if flags and EXCLUDE_FLAGS & set(flags):
            flags.append("excluded_from_classifier")
        segments.append({
            "seg_id": f"s{i:03d}",
            "start_s": round(offset_s + s, 2), "end_s": round(offset_s + e, 2),
            "channel": channel,
            "likely_speaker": speaker, "speaker_confidence": speaker_conf,
            "speaker_method": "provided_hint",
            "text_raw": raw,
            "text_norm": normalize(raw),
            "text_masked": normalize(mask_pii(raw)),
            "lang": "id",
            "avg_logprob": res.get("avg_logprob"), "no_speech_prob": res.get("no_speech_prob"),
            "compression_ratio": compression_ratio(raw),
            "segment_confidence": segment_confidence(res, flags),
            "flags": flags,
            "stt_latency_s": round(lat, 3),
        })
    used = [s for s in segments if "excluded_from_classifier" not in s["flags"]]
    speech_s = sum(s["end_s"] - s["start_s"] for s in segments)
    used_s = sum(s["end_s"] - s["start_s"] for s in used)
    mean_c = round(sum(s["segment_confidence"] for s in used) / len(used), 2) if used else 0.0
    if not segments:
        status = "no_speech"
    elif not used:
        status = "unintelligible"
    else:
        status = "low_confidence" if mean_c < 0.5 else "ok"
    return {
        "schema_version": SCHEMA,
        "window_id": f"{trip_id}_w{int(offset_s)}",
        "trip_id": trip_id, "service": service,
        "window": {"start_s": round(offset_s, 2), "end_s": round(offset_s + total, 2)},
        "provenance": {
            "stt_path": "cloud_or_device_see_backend", "backend": backend.name,
            "vad": {"name": vad.name, "min_silence_s": 0.5, "pad_s": 0.25, "max_len_s": 20},
            "decode": {"language": "id"},
            "normalizer_version": "id-norm-0.1", "pii_masker_version": "pii-id-0.2",
            "processed_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        },
        "segments": segments,
        "window_summary": {
            "n_segments": len(segments), "n_used_for_classifier": len(used),
            "speech_seconds": round(speech_s, 2),
            "coverage_ratio": round(used_s / speech_s, 2) if speech_s else 0.0,
            "mean_segment_confidence": mean_c, "status": status,
            "processing_s": round(time.perf_counter() - t_all, 3),
        },
    }


# ----------------------------------------------------------------------- views
def fmt_t(s):
    s = int(round(s))
    return f"{s // 60:02d}:{s % 60:02d}"


def speaker_tag(seg, with_conf=True):
    role = seg["likely_speaker"]
    name = {"driver": "DRIVER", "passenger": "PENUMPANG"}.get(role, "TIDAK_PASTI")
    if role == "passenger" and seg.get("passenger_index"):
        name = f"PENUMPANG_{seg['passenger_index']}"
    return f"[{name}|{seg['speaker_confidence']:.2f}]" if with_conf else f"[{name}]"


def render_llm_view(win, trip_context=""):
    lines = []
    if trip_context:
        lines += [trip_context, ""]
    lines.append("Transkrip (tag pembicara adalah dugaan, bukan fakta):")
    for s in win["segments"]:
        span = f"[{fmt_t(s['start_s'])}-{fmt_t(s['end_s'])}]"
        if "excluded_from_classifier" in s["flags"]:
            lines.append(f"{span} [TIDAK_PASTI] (tidak jelas)")
            continue
        note = " (kurang jelas)" if "low_confidence" in s["flags"] or "rate_suspect" in s["flags"] else ""
        lines.append(f"{span} {speaker_tag(s)} {s['text_masked']}{note}")
    lines.append(f"Status transkrip: {win['window_summary']['status']}")
    return "\n".join(lines)


def to_transcript_lines(win):
    """Map a window to the backend transcript shape [{start, end, text, flagged}]
    (contracts/firestore-schema.md, `transcript`).

    - start/end are seconds from the window start.
    - Segments flagged `excluded_from_classifier` (empty, hallucination, likely no speech,
      repetition) are dropped, so they never reach the classifier or the dashboard.
    - text is `text_raw`, NOT masked: the backend masks before any LLM sees it.
    - flagged is always False: this module does not decide risk flags.
    """
    t0 = win["window"]["start_s"]
    return [{"start": round(s["start_s"] - t0, 2), "end": round(s["end_s"] - t0, 2),
             "text": s["text_raw"], "flagged": False}
            for s in win["segments"] if "excluded_from_classifier" not in s["flags"]]


def render_classifier_view(win):
    return " [SEP] ".join(
        f"{speaker_tag(s, with_conf=False)} {s['text_masked']}"
        for s in win["segments"] if "excluded_from_classifier" not in s["flags"])


# ------------------------------------------------------------------------- CLI
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--audio", required=True)
    ap.add_argument("--trip_id", default="trip")
    ap.add_argument("--backend", choices=["dummy", "hf", "faster", "whispercpp"], default="dummy")
    ap.add_argument("--model", default="maleo-ai/whisper-small-id")
    ap.add_argument("--dummy_texts", default=None, help="JSON list of texts, for --backend dummy")
    ap.add_argument("--vad", choices=["energy", "silero"], default="silero")
    ap.add_argument("--channel", default="unknown")
    ap.add_argument("--speaker", default="unknown", choices=["driver", "passenger", "unknown"])
    ap.add_argument("--speaker_conf", type=float, default=0.5)
    ap.add_argument("--offset_s", type=float, default=0.0)
    ap.add_argument("--view", choices=["none", "llm", "classifier"], default="none")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()

    if a.backend == "dummy":
        texts = json.load(open(a.dummy_texts, encoding="utf-8")) if a.dummy_texts else []
        backend = DummyBackend(texts)
    elif a.backend == "hf":
        backend = HFBackend(a.model)
    elif a.backend == "whispercpp":
        backend = WhisperCppBackend(a.model)
    else:
        backend = FasterWhisperBackend(a.model)
    vad = SileroVAD() if a.vad == "silero" else EnergyVAD()

    win = process_window(load_mono_16k(a.audio), backend, vad, a.trip_id, a.channel,
                         a.speaker, a.speaker_conf, a.offset_s)
    if a.out:
        json.dump(win, open(a.out, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
        print(f"Saved {a.out}")
    if a.view == "llm":
        print(render_llm_view(win))
    elif a.view == "classifier":
        print(render_classifier_view(win))
    else:
        print(json.dumps(win["window_summary"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
