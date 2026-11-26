"""Laptop stand-in for the phone's on-device models, so the app can be tested with a real voice.

POST /listen?offset=<seconds>   body: WAV (16 kHz mono PCM16) -> {"lines": [{"start", "end", "text"}]}
POST /classify                  body: {"lines": ["..."]}       -> {"results": [{"label", "score"}]}

Speech-to-text is this module's pipeline (Silero VAD -> Whisper -> hallucination filter), so the app
gets exactly what `process_window` would give. The classifier is the team's DistilBERT (11 labels);
the app maps those labels onto its own 4.

shortcut: development only. The architecture puts both models on the phones; this lets the app be
tested end to end before they're ported (sherpa-onnx / ONNX Runtime).

Run from stt/:
  uv run --no-project --python 3.12 --with numpy --with scipy --with soundfile --with pywhispercpp \
    --with torch --with transformers --with silero-vad python dev_server.py \
    --whisper models/maleo-small-id-q8_0/ggml-small-id-q8_0.bin --classifier <unzipped best_model folder>
"""

import argparse
import io
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

import soundfile as sf

from stt_service import HALLUCINATION_PHRASES, SileroVAD, WhisperCppBackend, process_window

lock = threading.Lock()  # one model call at a time: neither model is thread-safe
stt = vad = clf = tok = None
save_dir = None  # --save-dir: keep every received piece, to replay what went missing
pieces = 0


# How the invented YouTube outro usually starts, so it's cut from its first word.
LEAD_INS = ("lupa like", "like share", "jangan lupa like")


def keep_real_speech(text: str) -> str:
    """Whisper invents YouTube phrases ("like share dan subscribe") in a segment's silent tail. The module's
    filter drops the whole segment for that, which also drops the real speech before it. Keep what comes
    before the first invented phrase."""
    low = text.lower()
    cut = min((low.find(p) for p in (*HALLUCINATION_PHRASES, *LEAD_INS) if p in low), default=len(text))
    return text[:cut].strip(" ,.")


def transcribe(wav: bytes, offset: float) -> list[dict]:
    audio, sr = sf.read(io.BytesIO(wav), dtype="float32")
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    assert sr == 16000, f"expected 16 kHz audio, got {sr}"
    global pieces
    if save_dir:
        pieces += 1
        (save_dir / f"{pieces:04d}_at_{offset:07.1f}s.wav").write_bytes(wav)
    with lock:
        win = process_window(audio, stt, vad, offset_s=offset)
    if not win["segments"]:
        print(f"  {len(audio) / sr:4.1f}s audio at {offset:.0f}s -> no speech found", flush=True)
    lines = []
    for seg in win["segments"]:  # what Whisper heard, kept or dropped, so a test can be checked
        text, flags = seg["text_raw"], set(seg["flags"])
        if "hallucination_lexicon_match" in flags:
            text = keep_real_speech(text)
            flags -= {"hallucination_lexicon_match", "repetition_suspect", "excluded_from_classifier"}
        kept = bool(text) and not ({"excluded_from_classifier", "empty", "likely_no_speech", "repetition_suspect"} & flags)
        print(f"  {len(audio) / sr:4.1f}s audio at {offset:.0f}s -> {'KEPT ' if kept else 'DROP '}{seg['text_raw']!r}"
              f"{' => ' + repr(text) if kept and text != seg['text_raw'] else ''} {sorted(seg['flags']) or ''}", flush=True)
        if kept:
            lines.append({"start": seg["start_s"], "end": seg["end_s"], "text": text})
    return lines


def classify(lines: list[str]) -> list[dict]:
    import torch

    if not lines:
        return []
    with lock, torch.no_grad():
        probs = clf(**tok(lines, return_tensors="pt", padding=True, truncation=True)).logits.softmax(-1)
    return [{"label": clf.config.id2label[int(p.argmax())], "score": round(float(p.max()), 3)} for p in probs]


class Handler(BaseHTTPRequestHandler):
    def _send(self, code: int, body: dict) -> None:
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")  # the web app runs on another port
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_POST(self) -> None:
        url = urlparse(self.path)
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        try:
            if url.path == "/listen":
                offset = float(parse_qs(url.query).get("offset", ["0"])[0])
                self._send(200, {"lines": transcribe(body, offset)})
            elif url.path == "/classify":
                self._send(200, {"results": classify(json.loads(body)["lines"])})
            else:
                self._send(404, {"error": "unknown path"})
        except Exception as e:  # report, don't crash the server
            self._send(400, {"error": f"{type(e).__name__}: {e}"})

    def log_message(self, fmt, *args) -> None:
        print(f"{self.address_string()} {fmt % args}", flush=True)


def main() -> None:
    global stt, vad, clf, tok, save_dir
    ap = argparse.ArgumentParser()
    ap.add_argument("--whisper", required=True, help="ggml model file (models/README.md)")
    ap.add_argument("--classifier", required=True, help="Hugging Face model folder (config.json, model.safetensors, tokenizer)")
    ap.add_argument("--port", type=int, default=7088)
    ap.add_argument("--save-dir", help="save every received audio piece here (never inside the repo)")
    args = ap.parse_args()
    if args.save_dir:
        from pathlib import Path

        save_dir = Path(args.save_dir)
        save_dir.mkdir(parents=True, exist_ok=True)

    from transformers import AutoModelForSequenceClassification, AutoTokenizer

    # Silero, not the energy VAD: on continuous talk the energy threshold rises to the voice and drops it.
    stt, vad = WhisperCppBackend(args.whisper), SileroVAD()
    tok = AutoTokenizer.from_pretrained(args.classifier)
    clf = AutoModelForSequenceClassification.from_pretrained(args.classifier).eval()
    print(f"GoSafe dev models on http://localhost:{args.port} (listen, classify)", flush=True)
    ThreadingHTTPServer(("0.0.0.0", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
