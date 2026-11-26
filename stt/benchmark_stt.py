"""Benchmark speech-to-text models on a manifest of audio files.

Usage (on Colab or Kaggle, with a GPU):
  pip install transformers torch jiwer soundfile scipy accelerate
  python benchmark_stt.py --manifest noisy/manifest.csv --audio_dir noisy/ \
      --model cahya/whisper-small-id --model openai/whisper-large-v3-turbo \
      --keywords keywords.txt --out results.csv

manifest.csv columns: file,text  (optional: snr,mode used for grouping)
keywords.txt: one word or phrase per line (lowercase). Used for keyword recall:
  of the references that contain a keyword, how often does the hypothesis
  still contain it? This is closer to what early warning needs than WER.

Test the metric code without any model:  --model dummy
"""
import argparse
import csv
import json
import os
import re
import time
from collections import defaultdict

import jiwer

# Small default slang map. Both reference and hypothesis go through it, so
# spelling variants of the same word do not count as errors. Extend it.
DEFAULT_SLANG = {
    "gak": "tidak", "ga": "tidak", "nggak": "tidak", "enggak": "tidak", "engga": "tidak",
    "udah": "sudah", "udh": "sudah", "dah": "sudah", "sdh": "sudah",
    "banget": "sekali", "bgt": "sekali", "aja": "saja", "doang": "saja",
    "gimana": "bagaimana", "gmn": "bagaimana", "kayak": "seperti", "kaya": "seperti",
    "emang": "memang", "yg": "yang", "dgn": "dengan", "krn": "karena", "tp": "tapi",
    "lu": "kamu", "lo": "kamu", "elu": "kamu", "gue": "saya", "gw": "saya", "aku": "saya",
    "mas": "mas", "bang": "mas", "bro": "mas",
}


def normalize(text, slang):
    text = text.lower()
    text = re.sub(r"[^\w\s]", " ", text)
    words = [slang.get(w, w) for w in text.split()]
    return " ".join(words)


class DummyModel:
    """Returns the reference with every 5th word dropped. Only for testing."""
    name = "dummy"

    def transcribe(self, path, ref):
        words = ref.split()
        return " ".join(w for i, w in enumerate(words) if i % 5 != 4)


class HFWhisper:
    def __init__(self, model_id):
        import torch
        from transformers import pipeline

        self.name = model_id
        device = 0 if torch.cuda.is_available() else -1
        self.pipe = pipeline(
            "automatic-speech-recognition",
            model=model_id,
            device=device,
            torch_dtype=torch.float16 if device == 0 else torch.float32,
        )
        # Some fine-tuned models (e.g. cahya/whisper-small-id) ship no usable
        # generation config, so forcing language="indonesian" fails. Borrow the
        # base model's config (same tokenizer). Assumes a whisper-small model.
        if not getattr(self.pipe.model.generation_config, "lang_to_id", None):
            from transformers import GenerationConfig
            self.pipe.model.generation_config = GenerationConfig.from_pretrained("openai/whisper-small")
            print(f"[info] {model_id}: using openai/whisper-small generation config")

    def transcribe(self, path, ref):
        # Read audio ourselves: passing a path makes transformers call ffmpeg.
        import soundfile as sf
        audio, sr = sf.read(path, dtype="float32", always_2d=False)
        if audio.ndim > 1:
            audio = audio.mean(axis=1)
        out = self.pipe(
            {"raw": audio, "sampling_rate": sr},
            generate_kwargs={"language": "indonesian", "task": "transcribe"},
        )
        return out["text"]


def load_model(name):
    return DummyModel() if name == "dummy" else HFWhisper(name)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--audio_dir", default=None)
    ap.add_argument("--model", action="append", required=True)
    ap.add_argument("--keywords", default=None)
    ap.add_argument("--slang_json", default=None)
    ap.add_argument("--out", default="results.csv")
    args = ap.parse_args()

    slang = dict(DEFAULT_SLANG)
    if args.slang_json:
        slang.update(json.load(open(args.slang_json, encoding="utf-8")))
    keywords = []
    if args.keywords:
        keywords = [normalize(k, slang) for k in open(args.keywords, encoding="utf-8") if k.strip()]

    audio_dir = args.audio_dir or os.path.dirname(args.manifest)
    with open(args.manifest, newline="", encoding="utf-8") as f:
        rows = [r for r in csv.DictReader(f) if r.get("text", "").strip()]
    if not rows:
        raise SystemExit("No rows with reference text in the manifest.")

    results = []
    for model_name in args.model:
        model = load_model(model_name)
        # warm up once so the first clip does not include model load time
        model.transcribe(os.path.join(audio_dir, rows[0]["file"]), rows[0]["text"])
        for r in rows:
            path = os.path.join(audio_dir, r["file"])
            t0 = time.perf_counter()
            hyp = model.transcribe(path, r["text"])
            latency = time.perf_counter() - t0
            ref_n, hyp_n = normalize(r["text"], slang), normalize(hyp, slang)
            wer = jiwer.wer(ref_n, hyp_n)
            hits = [k for k in keywords if k in ref_n]
            kept = [k for k in hits if k in hyp_n]
            results.append({
                "model": model.name, "file": r["file"],
                "snr": r.get("snr", ""), "mode": r.get("mode", ""),
                "wer": round(wer, 4), "latency_s": round(latency, 3),
                "kw_total": len(hits), "kw_kept": len(kept),
                "ref": ref_n, "hyp": hyp_n,
            })

    with open(args.out, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(results[0].keys()))
        w.writeheader()
        w.writerows(results)

    # Summary: mean WER, mean latency, keyword recall per model and group
    groups = defaultdict(list)
    for r in results:
        groups[(r["model"], f"snr={r['snr']} mode={r['mode']}")].append(r)
        groups[(r["model"], "ALL")].append(r)
    print(f"{'model':32} {'group':26} {'n':>4} {'WER':>7} {'lat(s)':>7} {'kwRecall':>9}")
    for (m, g), rs in sorted(groups.items()):
        n = len(rs)
        wer = sum(x["wer"] for x in rs) / n
        lat = sum(x["latency_s"] for x in rs) / n
        kt, kk = sum(x["kw_total"] for x in rs), sum(x["kw_kept"] for x in rs)
        kr = f"{kk / kt:.2f}" if kt else "-"
        print(f"{m:32} {g:26} {n:>4} {wer:>7.3f} {lat:>7.3f} {kr:>9}")
    print(f"\nPer-clip results saved to {args.out}")


if __name__ == "__main__":
    main()
