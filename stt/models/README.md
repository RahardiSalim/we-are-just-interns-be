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

Accuracy of these candidates on our test sets is not recorded here yet.
