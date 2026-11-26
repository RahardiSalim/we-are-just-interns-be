"""Pretend to be the rider's phone: audio file -> STT -> classifier -> the GoSafe API.

    audio -> VAD + STT (stt_service.py) -> classifier per line -> markers -> trip, incident, recording upload

Same calls as the real app (POST /trips, POST /incidents, finalize, PUT recording, pieces), so the result
shows up on the dashboard. Nothing is sent when no line reaches the "high" threshold, like the real phone.

    SEED_PASSWORD=... FIREBASE_WEB_API_KEY=... python tools/simulate_ride.py --audio ride.m4a \
        --classifier <classifier folder> --stt-model <ggml-small-id-q8_0.bin>

Needs: the stt/ dependencies (torch, transformers, silero-vad, soundfile), `pip install pywhispercpp`, and on
macOS `afconvert` (built in) or `ffmpeg` to read .m4a. It signs in as a seeded rider and writes REAL data and
audio into the project the API points at, so use test recordings only. `--dry-run` sends nothing.

The mapping from the classifier's 11 labels to the app's 4 is an ASSUMPTION (see LABEL_MAP). Ask the person
who trained the classifier. Thresholds 0.6 (warning) and 0.8 (high) and the rule that only threat and sexual_harassment can be high
come from mobile/lib/engine/safety_engine.dart. The real phone classifies a sliding window; this script judges line by line.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

DEFAULT_API = os.environ.get("GOSAFE_API_URL", "https://gosafe-api-1izo.onrender.com")
WARNING, HIGH = 0.6, 0.8
SEVERITY = {"normal": 0, "uncomfortable": 1, "sexual_harassment": 2, "threat": 3}
# ASSUMPTION: classifier label -> app label. Not confirmed by whoever trained the model.
LABEL_MAP = {
    "LOGISTICS": "normal", "SERVICE_CONFLICT": "normal", "NON_PARTICIPANT": "normal",
    "REFUSAL": "normal", "DISTRESS": "normal",
    "PERSONAL_PROBING": "uncomfortable", "CONTACT_SOLICIT": "uncomfortable", "INSULT_DEGRADING": "uncomfortable",
    "APPEARANCE_SEXUAL": "sexual_harassment", "SEXUAL_EXPLICIT": "sexual_harassment",
    "INTIMIDATION": "threat",
}
CONTENT_TYPES = {".wav": "audio/wav", ".m4a": "audio/mp4", ".aac": "audio/aac", ".ogg": "audio/ogg"}


def call(method, url, body=None, token=None, raw=None, ctype=None):
    headers = {}
    if token:
        headers["Authorization"] = "Bearer " + token
    data = raw
    if body is not None:
        data, headers["Content-Type"] = json.dumps(body).encode(), "application/json"
    if ctype:
        headers["Content-Type"] = ctype
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            text = r.read()
            return r.status, (json.loads(text) if text and r.headers.get_content_type() == "application/json" else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read()[:300].decode()


def must(step, result):
    status, data = result
    print(f"  {step:<34} {status}")
    if status >= 300:
        sys.exit(f"stopped: {step} failed: {data}")
    return data


def run_stt(args) -> dict:
    out = Path(tempfile.mkdtemp()) / "window.json"
    cmd = [sys.executable, "-I", args.stt_service, "--audio", args.wav, "--backend", "whispercpp",
           "--model", args.stt_model, "--vad", "silero", "--speaker", "passenger", "--view", "none", "--out", str(out)]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return json.loads(out.read_text())


def classify(lines: list[str], folder: str) -> list[tuple[str, str, float]]:
    """(classifier label, app label, probability of that label) for each line."""
    import torch
    from transformers import AutoModelForSequenceClassification, AutoTokenizer

    tok = AutoTokenizer.from_pretrained(folder, local_files_only=True)
    model = AutoModelForSequenceClassification.from_pretrained(folder, local_files_only=True).eval()
    out = []
    for text in lines:
        with torch.no_grad():
            p = model(**tok(text, return_tensors="pt", truncation=True, max_length=128)).logits.softmax(-1)[0]
        i = int(p.argmax())
        name = model.config.id2label[i]
        out.append((name, LABEL_MAP[name], float(p[i])))
    return out


def ensure_wav(path: str) -> str:
    """The STT pipeline reads WAV. Other formats (Voice Memos .m4a) are converted to 16 kHz mono."""
    if path.lower().endswith(".wav"):
        return path
    wav = Path(tempfile.mkdtemp()) / "audio.wav"
    if shutil.which("afconvert"):
        cmd = ["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", path, str(wav)]
    elif shutil.which("ffmpeg"):
        cmd = ["ffmpeg", "-loglevel", "error", "-i", path, "-ar", "16000", "-ac", "1", str(wav)]
    else:
        sys.exit("Cannot read this format: install ffmpeg or pass a .wav file")
    subprocess.run(cmd, check=True)
    return str(wav)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--audio", required=True)
    ap.add_argument("--classifier", required=True, help="folder with the classifier (config, tokenizer, safetensors)")
    ap.add_argument("--stt-model", required=True, help="whisper.cpp ggml model file, see stt/models/README.md")
    ap.add_argument("--stt-service", default=str(Path(__file__).resolve().parents[1] / "stt_service.py"))
    ap.add_argument("--api", default=DEFAULT_API, help="backend base URL (env GOSAFE_API_URL)")
    ap.add_argument("--email", default="rider1@gosafe.test")
    ap.add_argument("--dry-run", action="store_true", help="STT and classifier only, send nothing")
    args = ap.parse_args()
    args.wav = ensure_wav(args.audio)

    print("1. Speech to text")
    window = run_stt(args)
    segs = [s for s in window["segments"] if s["text_masked"].strip()]
    for s in segs:
        print(f"   {s['start_s']:6.2f}-{s['end_s']:6.2f}  {s['text_masked']}")

    print("2. Classifier (per line)")
    verdicts = classify([s["text_masked"] for s in segs], args.classifier)
    markers, worst = [], None
    for s, (name, label, p) in zip(segs, verdicts):
        # Same rule as mobile/lib/engine/safety_engine.dart: only threat and sexual_harassment can be "high".
        harmful = label in ("threat", "sexual_harassment")
        kind = None if label == "normal" or p < WARNING else ("high" if harmful and p >= HIGH else "warning")
        print(f"   {s['start_s']:6.2f}  {name:<18} -> {label:<17} {p:.2f}  {kind or '-'}")
        if kind:
            markers.append({"at": s["start_s"], "kind": kind, "label": label, "score": round(p, 3), "text": s["text_masked"]})
            if kind == "high" and (worst is None or (SEVERITY[label], p) > (SEVERITY[worst[0]], worst[1])):
                worst = (label, p)
    if not any(m["kind"] == "high" for m in markers):
        print("3. No line reached the high threshold: nothing would leave the phone. Stopping.")
        return
    if args.dry_run:
        print("3. Dry run: would send an auto incident", worst, "- stopping.")
        return

    print("3. Sending as", args.email)
    token = must("sign in", call("POST", "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key="
                                 + os.environ["FIREBASE_WEB_API_KEY"],
                                 {"email": args.email, "password": os.environ["SEED_PASSWORD"], "returnSecureToken": True}))["idToken"]
    order = "GR-SIM-" + time.strftime("%H%M%S")
    must("POST /trips", call("POST", f"{args.api}/trips", {"orderId": order, "riderConsent": True}, token))
    end = float(window["window"]["end_s"])
    now = datetime.now(timezone.utc)
    inc = must("POST /incidents (auto)", call("POST", f"{args.api}/incidents", {
        "tripId": order, "trigger": "auto",
        "windowStart": (now - timedelta(seconds=end)).isoformat(), "windowEnd": now.isoformat(),
        "deviceTranscript": [{"start": s["start_s"], "end": s["end_s"], "text": s["text_masked"]} for s in segs],
        "deviceLabel": worst[0], "deviceScore": round(worst[1], 3)}, token))
    clip = Path(args.wav).read_bytes()
    must("upload clip to R2", call(inc["uploadMethod"], inc["uploadUrl"], raw=clip, ctype="audio/wav"))
    must("finalize", call("POST", f"{args.api}/incidents/{inc['incidentId']}/finalize", {}, token))
    ctype = CONTENT_TYPES[Path(args.audio).suffix.lower()]
    rec = {"durationSec": end, "contentType": ctype, "markers": markers, "pieces": 0,
           "transcript": [{"at": s["start_s"], "end": s["end_s"], "text": s["text_masked"]} for s in segs]}
    must("PUT recording (details)", call("PUT", f"{args.api}/trips/{order}/recording", rec, token))
    piece = must("piece 0 upload URL", call("POST", f"{args.api}/trips/{order}/recording/pieces/0", {}, token))
    must("upload piece 0 to R2", call(piece["uploadMethod"], piece["uploadUrl"], raw=Path(args.audio).read_bytes(), ctype=ctype))
    must("PUT recording (done)", call("PUT", f"{args.api}/trips/{order}/recording", {**rec, "pieces": 1, "done": True}, token))
    must("end trip", call("POST", f"{args.api}/trips/{order}/end", {}, token))
    print(f"\nDone. Order {order}, incident {inc['incidentId']}. Open the dashboard and look for this order.")


if __name__ == "__main__":
    main()
