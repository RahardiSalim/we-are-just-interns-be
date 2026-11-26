"""Score the whole listening pipeline on recorded rides (see README.md and ride_script.csv).

Three steps, so the decisions come from the app's own code, not a copy of it:
  1. python eval/score.py transcribe ...   audio -> Silero VAD -> Whisper -> clean -> classifier  (out/asr.json)
  2. EVAL_ASR=... EVAL_ACTIONS=... flutter test test/eval_replay_test.dart   (in mobile/: the app's keywords,
     combined classifier, safe phrase and rules decide each line; out/actions.json)
  3. python eval/score.py report ...       compare with ride_script.csv                   (out/report.md)
eval/run.sh does all three.

Run from stt/ with the dev_server.py environment (numpy scipy soundfile pywhispercpp torch transformers silero-vad).
Recordings are named <scenario>_<setting>_<initials>.<ext>, e.g. D_harassment_quiet_rs.m4a; files starting
with I_ are no-speech clips. Audio that isn't 16 kHz WAV is converted with macOS afconvert.
"""

import argparse
import csv
import json
from collections import Counter
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))  # stt/ for stt_service and dev_server

AUDIO = {".wav", ".m4a", ".mp3", ".aac", ".flac", ".ogg", ".caf"}


def words(text: str) -> list[str]:
    return re.sub(r"[^a-z0-9]+", " ", text.lower()).split()


def close(a: str, b: str) -> bool:
    """Same word, or one letter off for words of 4+ letters (speech-to-text slips)."""
    if a == b:
        return True
    if min(len(a), len(b)) <= 3 or abs(len(a) - len(b)) > 1:  # short words ("tol", "lo") must match exactly
        return False
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1] <= 1


def coverage(script: list[str], heard: list[str], weight=None) -> float:
    """Share of the script line's words found, in order, in what was heard. With `weight`, rare words count
    more than common ones ("pak", "aja", "ya"), so lines that only share filler don't look alike."""
    if not script:
        return 0.0
    w = weight or {}
    prev = [0.0] * (len(heard) + 1)
    for s in script:
        cur = [0.0]
        for j, h in enumerate(heard, 1):
            cur.append(prev[j - 1] + w.get(s, 1.0) if close(s, h) else max(prev[j], cur[j - 1]))
        prev = cur
    return prev[-1] / sum(w.get(s, 1.0) for s in script)


def wer(ref: list[str], hyp: list[str]) -> float:
    prev = list(range(len(hyp) + 1))
    for i, r in enumerate(ref, 1):
        cur = [i]
        for j, h in enumerate(hyp, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (r != h)))
        prev = cur
    return prev[-1] / max(1, len(ref))


def scenario_of(name: str, scenarios: list[str]) -> str | None:
    if name.startswith("I_"):
        return "I_no_speech"
    return next((s for s in sorted(scenarios, key=len, reverse=True) if name.startswith(s)), None)


def load_16k(path: Path):
    import soundfile as sf

    if path.suffix.lower() != ".wav" or sf.info(str(path)).samplerate != 16000 or sf.info(str(path)).channels != 1:
        tmp = Path(tempfile.mkdtemp()) / "a.wav"
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(path), str(tmp)], check=True)
        path = tmp
    audio, _ = sf.read(str(path), dtype="float32")
    return audio


def transcribe(args) -> None:
    import torch
    from transformers import AutoModelForSequenceClassification, AutoTokenizer

    from dev_server import clean
    import time

    from stt_service import HFBackend, SileroVAD, WhisperCppBackend, process_window

    scenarios = sorted({r["scenario"] for r in csv.DictReader(open(HERE / "ride_script.csv"))})
    # A .bin file is a whisper.cpp (ggml) model; a folder is a Hugging Face model run with transformers.
    stt = WhisperCppBackend(args.whisper) if args.whisper.endswith(".bin") else HFBackend(args.whisper)
    vad = SileroVAD()
    tok = AutoTokenizer.from_pretrained(args.classifier)
    clf = AutoModelForSequenceClassification.from_pretrained(args.classifier).eval()
    out = []
    for path in sorted(p for p in Path(args.recordings).iterdir() if p.suffix.lower() in AUDIO):
        scenario = scenario_of(path.name, scenarios)
        if not scenario:
            print(f"skip {path.name}: name doesn't start with a scenario from ride_script.csv")
            continue
        audio = load_16k(path)
        t0 = time.perf_counter()
        win = process_window(audio, stt, vad)
        secs = time.perf_counter() - t0
        dropped = []
        lines = clean(win["segments"], log=lambda seg, kept, _t: None if kept else dropped.append(seg["text_raw"]))
        if lines:
            with torch.no_grad():
                probs = clf(**tok([l["text"] for l in lines], return_tensors="pt", padding=True,
                                  truncation=True)).logits.softmax(-1)
            for line, p in zip(lines, probs):
                line["model"] = [clf.config.id2label[int(p.argmax())], round(float(p.max()), 3)]
        out.append({"file": path.name, "scenario": scenario, "durationSec": round(len(audio) / 16000, 1),
                    "sttSec": round(secs, 2), "stt": stt.name, "lines": lines, "dropped": dropped})
        print(f"{path.name}: {len(lines)} lines, {len(dropped)} dropped", flush=True)
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    Path(args.out).write_text(json.dumps(out, ensure_ascii=False, indent=1))


RANK = {"none": 0, "warning": 1, "high": 2, "sos": 2}
RANK_ALL = {"none": 0, "warning": 1, "high": 2, "sos": 3}


def report(args) -> None:
    script = list(csv.DictReader(open(HERE / "ride_script.csv")))
    asr = {f["file"]: f for f in json.load(open(args.asr))}
    actions = {f["file"]: f["actions"] for f in json.load(open(args.actions))}
    md = ["# GoSafe eval report", ""]
    tot = {"danger": 0, "caught": 0, "benign": 0, "false": 0, "benign_sec": 0.0, "nospeech_sec": 0.0, "halluc": 0,
           "heard": 0, "lines": 0}
    rows_out = []
    for name, f in asr.items():
        acts = actions.get(name, [])
        lines = f["lines"]
        if f["scenario"] == "I_no_speech":
            tot["nospeech_sec"] += f["durationSec"]
            tot["halluc"] += len(lines)
            rows_out.append(f"| {name} | no speech | {f['durationSec']} s | {len(lines)} invented lines kept, "
                            f"{len(f['dropped'])} dropped | {'; '.join(l['text'] for l in lines)[:120]} |")
            continue
        exp = [r for r in script if r["scenario"] == f["scenario"]]
        heard_words = [words(l["text"]) for l in lines]
        ref = [w for r in exp for w in words(r["text"])]
        hyp = [w for h in heard_words for w in h]
        md_lines = [f"### {name}  (WER {wer(ref, hyp):.2f}, {f['durationSec']} s)", "",
                    "| id | expect | heard? | got | script line → what was heard |", "|---|---|---|---|---|"]
        fired_so_far = 0  # the strongest action already raised in this ride (cooldown / once-per-ride)
        import math

        df = Counter(w for r in exp for w in set(words(r["text"])))
        idf = {w: math.log(1 + len(exp) / n) for w, n in df.items()}
        floor = 0  # script lines are in order: a match can't start before the previous one
        benign = all(r["expect"] == "none" for r in exp)
        if benign:
            tot["benign_sec"] += f["durationSec"]
        for r in exp:
            sw = words(r["text"])
            # Speech-to-text can split one script line over up to 3 heard lines, or merge several into one: match
            # the script line against every run of 1-3 neighbouring heard lines and take the best-covering run.
            spans = [(i, j) for i in range(floor, len(lines)) for j in range(i + 1, min(i + 4, len(lines) + 1))]
            span_cov = {sp: coverage(sw, [w for h in heard_words[sp[0]:sp[1]] for w in h], idf) for sp in spans}
            cov = max(span_cov.values(), default=0.0)
            # The shortest run within 0.05 of the best: extra lines only count if they add words.
            span = min((sp for sp, c in span_cov.items() if c >= cov - 0.05), key=lambda sp: sp[1] - sp[0],
                       default=None)
            near = [i for i in range(*span) if i < len(acts)] if span and cov >= 0.5 else []
            if near:
                floor = near[0]
            # The action may sit on any line of the run: take the strongest.
            best = max(near, key=lambda i: RANK_ALL[acts[i]["action"]], default=None)
            got = acts[best]["action"] if best is not None else "none"
            # Anything fired on any heard line up to here counts as already raised, even on a line no script line
            # matched (the cooldown then keeps later lines quiet, as it should).
            upto = near[-1] if near else floor
            fired_so_far = max([fired_so_far] + [3 if a["action"] == "sos" else RANK[a["action"]]
                                                 for a in acts[: upto]])
            tot["lines"] += 1
            tot["heard"] += cov >= 0.6
            want = r["expect"]
            if want == "none":
                tot["benign"] += 1
                ok = got == "none"
                tot["false"] += not ok
            else:
                tot["danger"] += 1
                # A warning or high raised earlier in the ride covers this line (cooldown, once per ride).
                ok = RANK[got] >= RANK[want] or fired_so_far >= RANK[want] or (want == "sos" and got == "sos")
                if want == "sos":
                    ok = got == "sos" or fired_so_far == 3
                tot["caught"] += ok
            fired_so_far = max(fired_so_far, 3 if got == "sos" else RANK[got])
            heard_text = " / ".join(lines[i]["text"] for i in near) if near else "(not heard)"
            md_lines.append(f"| {r['id']} | {want} | {cov:.0%} | {got}{'' if ok else ' ❌'} | "
                            f"{r['text']} → _{heard_text[:90]}_ |")
        md += md_lines + [""]
    hours = tot["benign_sec"] / 3600
    summary = [
        "## Summary", "",
        f"- **Danger lines caught:** {tot['caught']}/{tot['danger']} "
        f"({tot['caught'] / max(1, tot['danger']):.0%}) — warning, high or SOS raised at or before the line",
        f"- **False alarms:** {tot['false']}/{tot['benign']} harmless lines raised something "
        f"({tot['false'] / max(1, tot['benign']):.0%})"
        + (f"; {tot['false'] / hours:.0f} per hour of harmless talk" if hours else ""),
        f"- **Lines heard by speech-to-text (≥60% of words):** {tot['heard']}/{tot['lines']}",
        f"- **Invented lines on no-speech audio:** {tot['halluc']} in {tot['nospeech_sec']:.0f} s",
        f"- **Speed:** {sum(f.get('sttSec', 0) for f in asr.values()):.0f} s to transcribe "
        f"{sum(f['durationSec'] for f in asr.values()):.0f} s of audio on this machine "
        f"(speech-to-text: {next(iter(asr.values())).get('stt', '?')})",
        "",
    ]
    if rows_out:
        summary += ["| file | kind | length | result | text |", "|---|---|---|---|---|", *rows_out, ""]
    text = "\n".join(md[:2] + summary + md[2:])
    Path(args.out).write_text(text)
    print("\n".join(summary))


def main() -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    t = sub.add_parser("transcribe")
    t.add_argument("--recordings", default=str(HERE / "recordings"))
    t.add_argument("--whisper", default="models/maleo-small-id-q8_0/ggml-small-id-q8_0.bin")
    t.add_argument("--classifier", default="models/clf-lite-5x")
    t.add_argument("--out", default=str(HERE / "out" / "asr.json"))
    r = sub.add_parser("report")
    r.add_argument("--asr", default=str(HERE / "out" / "asr.json"))
    r.add_argument("--actions", default=str(HERE / "out" / "actions.json"))
    r.add_argument("--out", default=str(HERE / "out" / "report.md"))
    args = ap.parse_args()
    transcribe(args) if args.cmd == "transcribe" else report(args)


if __name__ == "__main__":
    main()
