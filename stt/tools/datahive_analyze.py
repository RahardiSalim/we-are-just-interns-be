"""Read the output of datahive_run.py: STT quality indicators, how many speaker changes would merge
on one microphone, and (optional) how a text classifier labels real conversation.

There is no reference transcript, so there is no WER. The classifier part has no human labels either:
it shows how often it raises an alarm on ordinary talk and prints a random sample for a person to judge.

Usage (from stt/):
  python tools/datahive_analyze.py --out_dir convo_out [--classifier <folder>] [--seed 1]

--classifier is a folder with a DistilBERT-style sequence classifier (config.json, model.safetensors,
tokenizer files). Only safetensors are read; never point it at a folder you do not trust. The
neutral-label group below is an assumption of ours, not something the model defines.
"""
import argparse
import collections
import csv
import json
import random
import statistics as st

PAD = 0.25  # build_segments pads every segment by 0.25 s on both sides
NEUTRAL = {"LOGISTICS", "SERVICE_CONFLICT", "NON_PARTICIPANT"}  # ASSUMPTION: neutral labels of the temp classifier


def load_segments(out_dir):
    done = [r["file"].replace(".mp3", "") for r in csv.DictReader(open(f"{out_dir}/summary.csv", encoding="utf-8"))]
    per_file = {}
    for name in done:
        segs = []
        for side in ("kiri", "kanan"):
            for s in json.load(open(f"{out_dir}/{name}/{side}.json", encoding="utf-8"))["segments"]:
                segs.append({"file": name, "side": side, **{k: s[k] for k in ("start_s", "end_s", "text_raw", "text_masked", "flags")}})
        per_file[name] = sorted(segs, key=lambda x: x["start_s"])
    return per_file


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out_dir", required=True)
    ap.add_argument("--classifier", default=None)
    ap.add_argument("--seed", type=int, default=1)
    a = ap.parse_args()
    per_file = load_segments(a.out_dir)
    all_segs = [s for segs in per_file.values() for s in segs]

    print("A. STT quality indicators (not WER)")
    print(f"{'file':12} {'segments':>9} {'excluded':>9} {'hallucination':>14} {'repeated':>9} {'odd rate':>9}")
    for name, segs in per_file.items():
        c = collections.Counter(f for s in segs for f in s["flags"])
        print(f"{name:12} {len(segs):9} {c['excluded_from_classifier']:9} {c['hallucination_lexicon_match']:14} {c['repetition_suspect']:9} {c['rate_suspect']:9}")

    print("\nB. Speaker changes: share that would merge into one segment on a single microphone")
    print("   raw gap = gap between segments + 0.5 s (each segment is padded by 0.25 s on both sides)")
    for name, segs in per_file.items():
        raw = [(segs[i + 1]["start_s"] - segs[i]["end_s"]) + 2 * PAD for i in range(len(segs) - 1) if segs[i + 1]["side"] != segs[i]["side"]]
        if raw:
            print(f"{name:12} changes {len(raw):4} | raw gap median {1000 * st.median(raw):5.0f} ms | under 0.5 s: {100 * sum(g < 0.5 for g in raw) / len(raw):4.1f}% | interrupting (under 0 s): {100 * sum(g < 0 for g in raw) / len(raw):4.1f}%")

    if not a.classifier:
        return
    import torch
    from transformers import AutoModelForSequenceClassification, AutoTokenizer
    tok = AutoTokenizer.from_pretrained(a.classifier, local_files_only=True)
    model = AutoModelForSequenceClassification.from_pretrained(a.classifier, local_files_only=True).eval()
    id2 = {int(k): v for k, v in model.config.id2label.items()}
    usable = [s for s in all_segs if "excluded_from_classifier" not in s["flags"] and s["text_masked"].strip()]
    for i in range(0, len(usable), 64):
        enc = tok([s["text_masked"] for s in usable[i:i + 64]], return_tensors="pt", padding=True, truncation=True, max_length=128)
        with torch.no_grad():
            p = torch.softmax(model(**enc).logits, dim=-1)
        for s, row in zip(usable[i:i + 64], p):
            s["lab"], s["p"] = id2[int(row.argmax())], float(row.max())

    print(f"\nC. Classifier on {len(usable)} segments of ordinary conversation (share of segments with a non-neutral label)")
    print("   threshold:  " + "  ".join(f"p>={t}" for t in (0.8, 0.9, 0.95, 0.99)))
    print("   share      :  " + "  ".join(f"{100 * sum(s['lab'] not in NEUTRAL and s['p'] >= t for s in usable) / len(usable):5.1f}%" for t in (0.8, 0.9, 0.95, 0.99)))
    alarms = [s for s in usable if s["lab"] not in NEUTRAL and s["p"] >= 0.8]
    print("   labels of the alarms:", dict(collections.Counter(s["lab"] for s in alarms)))
    random.seed(a.seed)
    print("\n   random sample of alarms, for a person to judge:")
    for s in random.sample(alarms, min(14, len(alarms))):
        print(f"   {s['file']} [{int(s['start_s']) // 60:02d}:{int(s['start_s']) % 60:02d}] {s['side']:5} {s['lab']:17} {s['p']:.2f}  {s['text_raw'][:95]}")


if __name__ == "__main__":
    main()
