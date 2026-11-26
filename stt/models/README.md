# Model candidates for the phone

Model files are **not committed**. They are large binaries, GitHub rejects files over 100 MB, and anything committed stays in the history for everyone who clones. Instead each model is pinned here by source, revision and SHA-256, and downloaded when needed. Downloaded files are git-ignored (`stt/.gitignore`).

The app runs speech-to-text on the phone with `sherpa_onnx` (see [contracts/ARCHITECTURE.md](../../contracts/ARCHITECTURE.md), "On-device listening"), so the format that matters is ONNX int8 for sherpa-onnx.

## Whisper tiny, int8

| | |
|---|---|
| Source | https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny |
| Revision | `65176e2deb88badc814a94058666cadccc29b61c` |
| What it is | OpenAI Whisper tiny, multilingual, exported to ONNX by the sherpa-onnx project. **Not** fine-tuned for Indonesian |
| Runtime | sherpa-onnx (Flutter package `sherpa_onnx`, Python package `sherpa-onnx`) |
| Licence | The Hugging Face card of this repo states none. The upstream `openai/whisper-tiny` card lists Apache-2.0. Confirm before redistributing |

| File | Bytes |
|---|---|
| `tiny-encoder.int8.onnx` | 12,937,772 |
| `tiny-decoder.int8.onnx` | 89,855,401 |
| `tiny-tokens.txt` | 816,730 |
| **Total** | **103,609,903** (103.6 MB, 98.8 MiB) |

Download and verify (from `stt/models/`):

```bash
mkdir -p whisper-tiny-int8 && cd whisper-tiny-int8
REV=65176e2deb88badc814a94058666cadccc29b61c
for f in tiny-encoder.int8.onnx tiny-decoder.int8.onnx tiny-tokens.txt; do
  curl -L --fail -o "$f" "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/$REV/$f"
done
shasum -a 256 -c ../whisper-tiny-int8.sha256
```

Run it from Python with `sherpa_onnx.OfflineRecognizer.from_whisper(encoder=..., decoder=..., tokens=..., language="id", task="transcribe")`.

## Sizes of the stock sherpa-onnx int8 models (from Hugging Face file metadata)

| Model | Encoder | Decoder | Total |
|---|---|---|---|
| tiny | 12.9 MB | 89.9 MB | about 103 MB |
| base | 29.1 MB | 130.7 MB | about 160 MB |
| small | 112.4 MB | 262.2 MB | about 375 MB |

The Indonesian fine-tunes we benchmarked (`maleo-ai/whisper-small-id`, `cahya/whisper-small-id`) are "small". An ONNX int8 export of them does not exist yet, so about 375 MB is an estimate from the stock small model, not a measurement.

## Accuracy of Whisper tiny int8 on our test sets (measured 2026-11-26)

Same clips and same WER normalisation as `benchmark_stt.py` (default slang map), so the rows can be compared with the maleo and cahya results in [../README.md](../README.md). tiny int8 ran in sherpa-onnx (Python package 2.0.3), `language="id"`, greedy decoding, whole clip, no VAD, 4 threads, one run. maleo and cahya are the PyTorch models from the benchmark.

**FLEURS `id_id` dev (real read speech) with synthetic motorbike noise, WER, 320 clips**

| Model | SNR 20 | SNR 10 | SNR 5 | SNR 0 | All |
|---|---|---|---|---|---|
| tiny int8 | 0.686 | 0.803 | 1.039 | 1.244 | **0.943** |
| maleo (small, fine-tuned) | 0.047 | 0.125 | 0.225 | 0.456 | 0.213 |
| cahya (small, fine-tuned) | 0.012 | 0.096 | 0.244 | 0.513 | 0.216 |

**Ride sentences from `dialog_script.csv` (Edge TTS, 2 synthetic voices) with synthetic noise, 192 clips**

| Model | WER SNR 20 | SNR 10 | SNR 5 | SNR 0 | WER all | Keyword recall all | at SNR 5 | at SNR 0 |
|---|---|---|---|---|---|---|---|---|
| tiny int8 | 0.362 | 0.465 | 0.593 | 0.819 | **0.560** | **0.40** | 0.24 | 0.18 |
| maleo | 0.063 | 0.071 | 0.116 | 0.230 | 0.120 | 0.94 | 0.92 | 0.84 |

Keyword recall counts 152 keyword occurrences from `keywords.txt`. cahya was not run on this set.

**FLEURS clean, no added noise, 40 clips:** tiny int8 WER 0.593. maleo got 0.054 through the full pipeline (Silero VAD + STT), so the method is not identical.

**Cost on the laptop CPU** (not phone numbers): model load 0.2 s. Memory of the whole Python process: 328 to 342 MB after loading, 493 to 650 MB at peak, over three separate runs. About 0.52 s per FLEURS clip (6 to 18 s of audio) and 0.18 s per ride-sentence clip (3 to 6 s).

**Reading:** tiny int8 is not usable for this job. It catches 40% of the keywords, 24% at 5 dB, and WER above 1 at 5 and 0 dB means it adds many wrong words. Examples: "badan mbak bagus sekali" became "baiknya buat buat disbanget", and "bus coaster jepang" became "pus kwaster cepang".

**Limits:**
- This is the stock multilingual tiny, not fine-tuned for Indonesian.
- How much of the loss comes from int8 and how much from the tiny size is **not separated**: there was no run with fp32 tiny (`tiny-*.onnx` without `.int8`, about 152 MB).
- One real-voice set (read sentences, no slang, all labelled MALE). The ride sentences are synthetic voices and the noise is synthetic. No recording of a real ride.
- Whisper base (about 160 MB) has not been measured.
- The evaluation script is not committed: it needs the `sherpa-onnx` package, which is not a dependency of this folder.
