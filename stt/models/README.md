# Model candidates for the phone

Model files are **not committed**, with one exception: the 5-label IndoBERT-lite text classifier in [`clf-lite-5x/`](clf-lite-5x/README.md) (46.8 MB, under GitHub's 100 MB limit), so the team can pull and use it. They are large binaries, GitHub rejects files over 100 MB, and anything committed stays in the history for everyone who clones. Instead each model is pinned here by source, revision and SHA-256, and downloaded when needed. Downloaded files are git-ignored (`stt/.gitignore`).

[contracts/ARCHITECTURE.md](../../contracts/ARCHITECTURE.md) ("On-device listening") plans `sherpa_onnx` (ONNX int8) on the phone. This page measures what is available in that format **and** in whisper.cpp's ggml format, because one of them turned out to be much easier to get.

## What we measured (2026-11-26)

All numbers: same clips, same WER normalisation as `benchmark_stt.py` (default slang map), laptop CPU, one run per model. **The ride-sentence set is the one to trust**: no model was trained on it. FLEURS is not held out for maleo and cahya (see "Read this before comparing"). None of this is phone speed.

**Ride sentences** from `dialog_script.csv` (Edge TTS, 2 synthetic voices) with synthetic motorbike noise, 192 clips, 152 keyword occurrences from `keywords.txt`:

| Model | Files | WER all | Keyword recall all | at SNR 5 | at SNR 0 | s per clip |
|---|---|---|---|---|---|---|
| **maleo small, whisper.cpp ggml q8_0** | **264.5 MB** | 0.129 | 0.93 (141/152) | 0.87 (33/38) | 0.84 (32/38) | 0.41 |
| maleo small, PyTorch | 483.5 MB (fp16) | 0.120 | 0.94 | 0.92 | 0.84 | 0.70 |
| base int8, stock multilingual | 160.6 MB | 0.411 | 0.57 | 0.47 | 0.24 | 0.35 |
| tiny int8, stock multilingual | 103.6 MB | 0.560 | 0.40 | 0.24 | 0.18 | 0.18 |
| tiny fp32, stock multilingual | 153.0 MB | 0.561 | 0.41 | 0.24 | 0.11 | 0.24 |

**FLEURS `id_id` dev** (real read speech) with synthetic motorbike noise, WER, 320 clips:

| Model | SNR 20 | SNR 10 | SNR 5 | SNR 0 | All | s per clip |
|---|---|---|---|---|---|---|
| maleo ggml q8_0 | 0.053 | 0.124 | 0.224 | 0.472 | 0.218 | 0.53 |
| maleo PyTorch | 0.047 | 0.125 | 0.225 | 0.456 | 0.213 | 1.13 |
| cahya small PyTorch | 0.012 | 0.096 | 0.244 | 0.513 | 0.216 | 5.28 |
| base int8, stock | 0.464 | 0.631 | 0.872 | 1.020 | 0.747 | 0.84 |
| tiny int8, stock | 0.686 | 0.803 | 1.039 | 1.244 | 0.943 | 0.52 |
| tiny fp32, stock | 0.627 | 0.827 | 1.078 | 1.242 | 0.943 | 0.64 |

FLEURS clean, no added noise, 40 clips: maleo ggml 0.037, base int8 0.400, tiny fp32 0.605, tiny int8 0.593.

**Memory** of the whole Python process on the laptop (after loading, then peak): maleo ggml 444 to 518 MB and 509 to 536 MB; tiny int8 328 to 342 MB and 493 to 650 MB; base int8 522 to 527 MB and 747 to 953 MB.

### Reading these numbers

- **maleo as ggml q8_0 keeps its accuracy.** Ride-sentence WER goes from 0.120 to 0.129 and keyword recall from 0.94 to 0.93, for about 55% of the file size of the fp16 model. At 5 dB the recall is a little lower (0.87 against 0.92, on 38 occurrences). It is the best candidate so far and needs no ONNX conversion.
- **int8 is not the problem.** Stock tiny int8 and fp32 give the same WER and recall. What fails is the stock multilingual tiny and base: not enough for Indonesian, with or without quantisation.
- **Under 100 MB is not reached with a good model yet.** Whisper small has 241 million parameters, so even 4 bits is about 121 MB. The candidates below are the open leads.

### Read this before comparing

- The model cards say **maleo and cahya were fine-tuned on FLEURS** (maleo: Common Voice 17, FLEURS `id_id`, YODAS2; cahya: Common Voice 11, magic_data, titml, FLEURS). FLEURS is therefore not a held-out set for them, and we do not know whether our `dev` clips were in their training data. Their FLEURS numbers are probably optimistic, and comparing them with stock tiny or base on FLEURS is not fair. The ride-sentence table is not affected.
- The ride sentences are synthetic voices with synthetic noise. FLEURS is read Wikipedia-style speech, all labelled MALE, with no slang. No recording of a real ride exists yet.
- Times and memory are for a laptop CPU, not for a phone. The phone speed, memory and battery of every model here are **not measured**.
- ggml and ONNX are different runtimes. The architecture plans sherpa-onnx; there are Flutter packages for whisper.cpp too (`whisper_ggml`, `whisper_cpp_flutter_plus`), but switching is a decision for the mobile team and has not been tried in the app.

## Best candidate so far: maleo small, ggml q8_0

| | |
|---|---|
| Source | https://huggingface.co/maleo-ai/whisper-small-id |
| Revision | `37a5b9a0fa5739e8e859984dabca44337a45fa55` |
| File | `ggml-small-id-q8_0.bin`, 264,464,624 bytes (264.5 MB, 252.2 MiB) |
| SHA-256 | `4f976a9aeae18e30d2043887302fe35ba45e8f8cb0a9f9f727d56d32cdef33c9` (same as the Hugging Face LFS hash) |
| What it is | OpenAI Whisper small fine-tuned for Indonesian, quantised to 8 bits for whisper.cpp |
| Runtime | whisper.cpp. Python package `pywhispercpp` 1.5.1 was used here |
| Licence | Apache-2.0 (model card) |

Same repository, other builds, not measured: `ct2-int8/model.bin` (244.6 MB, CTranslate2) and `model.safetensors` (483.5 MB, fp16).

Download and verify (from `stt/models/`):

```bash
mkdir -p maleo-small-id-q8_0 && cd maleo-small-id-q8_0
REV=37a5b9a0fa5739e8e859984dabca44337a45fa55
curl -L --fail -o ggml-small-id-q8_0.bin "https://huggingface.co/maleo-ai/whisper-small-id/resolve/$REV/ggml-small-id-q8_0.bin"
shasum -a 256 -c ../maleo-small-id-q8_0.sha256
```

Run the pipeline with it (needs `pip install pywhispercpp`, which is not a dependency of this folder):

```bash
python stt_service.py --audio ride.wav --backend whispercpp --model models/maleo-small-id-q8_0/ggml-small-id-q8_0.bin --view llm
```

## Whisper tiny, int8 (sherpa-onnx)

Measured above: **not usable** for this job. Kept because it is the ready-made ONNX file for the sherpa-onnx runtime.

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

```bash
mkdir -p whisper-tiny-int8 && cd whisper-tiny-int8
REV=65176e2deb88badc814a94058666cadccc29b61c
for f in tiny-encoder.int8.onnx tiny-decoder.int8.onnx tiny-tokens.txt; do
  curl -L --fail -o "$f" "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/$REV/$f"
done
shasum -a 256 -c ../whisper-tiny-int8.sha256
```

Sizes of the stock sherpa-onnx int8 models (Hugging Face file metadata): tiny about 103 MB, base about 160 MB (29.1 + 130.7), small about 375 MB (112.4 + 262.2). Base int8 and tiny fp32 were evaluated from `csukuangfj/sherpa-onnx-whisper-base` (revision `bb53ee204431c90d314c1cc08d28d23e5b7927cc`) and the `tiny-*.onnx` files of the tiny repo above.

## Open leads for under 100 MB (not measured)

Indonesian fine-tunes of Whisper tiny and base already exist on Hugging Face (all Apache-2.0). The reported WER is on the authors' own sets, not ours:

| Model | fp32 weights | WER on its card |
|---|---|---|
| `cahya/whisper-tiny-id` | 151 MB | 18.3 |
| `Bagus/whisper-tiny-common_voice_17_0-id` | 151 MB | 18.1 |
| `Bagus/whisper-base-common_voice_17_0-id` | 290 MB | 11.8 |

By parameter count (tiny 39 million, base 74 million) an 8-bit build should be roughly 40 to 55 MB for tiny and 75 to 100 MB for base. **That is an estimate, not a measurement.** The next step is to run them through `benchmark_stt.py` on the ride-sentence set and compare them with the table above.

Other leads: a streaming Zipformer RNN-T for Indonesian from k2 (runs on sherpa-ncnn; the sherpa-onnx row says "TBA"; size, accuracy and licence unknown), and a base model with a pruned vocabulary (`alphaedge-ai/whisper-base-ind-16384`, 109 MB fp16, no ASR accuracy on its card).
