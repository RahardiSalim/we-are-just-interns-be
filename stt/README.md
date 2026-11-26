# stt

Speech-to-text module for GoSafe: audio file → voice-activity segments → speech-to-text per segment → filters → one JSON window (`gosafe.stt.window.v1`) → text views for the classifier / LLM. Speech is Indonesian (slang, code-mixing), recorded on motorbikes, so noisy.

**Where it fits.** The product runs speech-to-text on the phones (see [contracts/ARCHITECTURE.md](../contracts/ARCHITECTURE.md), "On-device listening"), and the backend has no ML libraries on purpose. So this folder is **not deployed** and nothing in `backend/`, `mobile/` or `dashboard/` imports it. It is the modelling team's reference pipeline and evidence:

- which model to export to ONNX for the phones (benchmark below),
- the filters and PII masking the phones and backend should match,
- the JSON contract: [contracts/stt-window.md](../contracts/stt-window.md),
- `to_transcript_lines()`, the one-function bridge to the backend's `transcript` shape.

## Layout

| File | What it does |
|---|---|
| `stt_service.py` | Pipeline and CLI: VAD (energy or Silero), backends `dummy` / `hf` / `faster`, filters, PII masking, JSON window, text views |
| `benchmark_stt.py` | WER, latency and keyword recall per model, per noise level and phone position |
| `make_noisy_eval.py` | Mixes synthetic motorbike-like noise into clean clips at SNR 20/10/5/0 dB, handlebar or pocket |
| `dialog_script.csv` | 24 test sentences (`label` and `speaker` columns are for later tests) |
| `keywords.txt` | Keywords for the keyword-recall metric |
| `tests/` | Unit tests. They need only numpy, scipy and soundfile (no torch) |
| `models/` | Model candidates for the phone, pinned by revision and hash, with measured accuracy ([models/README.md](models/README.md)) |
| `LLM_INTEGRATION.md` | How an LLM or a service in front of an LLM should use this module: input, how it works, output, how to read it ([LLM_INTEGRATION.md](LLM_INTEGRATION.md)) |

## Setup

From `stt/`, with [uv](https://docs.astral.sh/uv/) like `backend/`:

```bash
uv sync
```

`torch` and `transformers` are large. The tests do not need them; for tests only: `pip install numpy scipy soundfile pytest`.

## Commands

| Task | Command |
|---|---|
| Test | `python -m pytest -q` (30 tests, about 1 s, no model needed) |
| Logic test without a model | `python stt_service.py --audio ride.wav --backend dummy --dummy_texts texts.json --vad energy --view llm` |
| Real run | `python stt_service.py --audio ride.wav --backend hf --model maleo-ai/whisper-small-id --speaker driver --view llm --out out.json` |
| Real run, smaller model (264 MB ggml, needs `pip install pywhispercpp`) | `python stt_service.py --audio ride.wav --backend whispercpp --model models/maleo-small-id-q8_0/ggml-small-id-q8_0.bin --view llm` |
| Noisy test set | `python make_noisy_eval.py --speech_dir clean --out_dir noisy` (needs `clean/manifest.csv` with `file,text`) |
| Benchmark | `python benchmark_stt.py --manifest noisy/manifest.csv --audio_dir noisy --model maleo-ai/whisper-small-id --model cahya/whisper-small-id --keywords keywords.txt --out results.csv` |

Recordings and results are git-ignored (`stt/.gitignore`): never commit audio.

## Rules

See [CLAUDE.md](CLAUDE.md). The short version: no fine-tuning, language forced to `id`, denoisers off, low-confidence or empty text is never "normal", speaker tags are hints, and only measured numbers are reported.

## Benchmark (measured 2026-11-26)

`maleo-ai/whisper-small-id` against `cahya/whisper-small-id`. WER uses the small slang map in `benchmark_stt.py`. Each clip was tested at SNR 20, 10, 5 and 0 dB, handlebar and pocket (8 variants per clip).

| Test set | Clips | maleo WER | cahya WER | maleo s/clip | cahya s/clip |
|---|---|---|---|---|---|
| FLEURS `id_id` dev, real read speech (40 sentences, all labelled MALE) | 320 | 0.213 | 0.216 | 1.1 | 5.3 |
| Synthetic voice, macOS "Damayanti" (24 script sentences) | 192 | 0.153 | 0.218 | 0.64 | 2.3 |
| Synthetic voice, facebook/mms-tts-ind | 192 | 0.240 | 0.310 | 0.87 | 3.0 |

Same 40 FLEURS clips without added noise, maleo only, through the full pipeline (Silero VAD + STT): WER 0.054, and 22 of the 40 clips have no error.

On-device model candidates (Whisper tiny int8 and others, pinned by hash, with their measured accuracy) are in [models/README.md](models/README.md).

**Read these numbers with care:**

- **FLEURS is not held out for either model.** The model cards say maleo and cahya were fine-tuned on FLEURS (maleo: Common Voice 17, FLEURS `id_id`, YODAS2; cahya: Common Voice 11, magic_data, titml, FLEURS). We do not know whether our `dev` clips were in their training data, so their FLEURS numbers are probably optimistic, and comparing them with stock Whisper on FLEURS is not fair. The ride-sentence results in [models/README.md](models/README.md) are not affected, and they also favour maleo.
- On FLEURS the two models are a tie on accuracy; maleo is chosen because it is 4–5× faster, and because it also wins on the ride sentences: on the Damayanti set maleo scored WER 0.153 and keyword recall 0.94, cahya 0.218 and 0.82.
- Only one real-voice set, read Wikipedia-style sentences, no slang, no ride noise. No recording of a real ride exists yet. Synthetic voices are cleaner than people, so their WER is optimistic.
- Noise is synthetic. FLEURS has no speaker IDs, so the number of voices is unknown (40 clips, 40 different sentences).
- Latency is the PyTorch model on one laptop CPU: a single run per model, timed after one warm-up call, with other work running on the laptop at times. It is **not** the on-phone speed: the phones run ONNX, and nothing here measures that or the battery cost.
- The slang map only affects the WER score, not the transcript.

## Limits

- With the `hf` and `whispercpp` backends there is no `avg_logprob`, so `segment_confidence` is a constant 0.70 and the `low_confidence` flag never fires. Wrong words are not marked "unclear". The `faster` backend gives real values (untested here).
- PII masking covers phone numbers, plates with a region code, and emails. A plate spoken in words ("B seribu dua ratus…") and names or addresses are not masked; names need an NER step.
- Speaker tags come from `--speaker` only. There is no speaker recognition.
- Tested on Python 3.14 with: numpy 2.5.5, scipy 1.18.1, soundfile 0.14.0, jiwer 4.0.0, torch 2.15.0, transformers 5.24.1, silero-vad 6.3. The folder asks for Python 3.12 like `backend/`, which was not run here. There is no `uv.lock` yet.
- Importing `silero_vad` sets the PyTorch thread count to 1 for the whole process, which makes a later Whisper call 2–3× slower. `SileroVAD` restores it; keep that when changing the import order.
