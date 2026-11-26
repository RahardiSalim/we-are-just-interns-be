# Handoff: where the STT work stands

Written 2026-11-26 so someone else can continue without the author. Everything below is either in this branch or can be recreated from public sources with the commands given. The one thing that cannot is the classifier model (see "Only on Akmal's laptop").

## Start here (10 minutes)

```bash
git fetch origin && git switch feat/stt-module
cd stt
pip install numpy scipy soundfile pytest   # enough for the tests
python -m pytest -q                         # 44 tests, about 1 s, no model needed
```

Read in this order: [README.md](README.md) (layout and commands) → [LLM_INTEGRATION.md](LLM_INTEGRATION.md) (what the output means and how an LLM should read it) → [models/README.md](models/README.md) (which model, with all measured numbers) → [../contracts/stt-window.md](../contracts/stt-window.md) (the JSON contract).

The branch is PR #1 (opened without a description). It adds only `stt/`, `contracts/stt-window.md` and one row in the root `CLAUDE.md`. Nothing in `backend/`, `mobile/` or `dashboard/` is touched. `main` keeps moving (three commits since this branch started, the newest `31a1cbd`); the root `CLAUDE.md` is the only file both sides touched, and a test merge with `31a1cbd` had no conflicts. Check again before merging: `git merge-tree --write-tree origin/main HEAD`.

## What exists

- A pipeline: audio → Silero VAD → speech-to-text per segment → filters → PII masking → one JSON window (`gosafe.stt.window.v1`) → text views for an LLM and a classifier. Backends: `dummy`, `hf`, `faster`, `whispercpp`.
- A benchmark (WER, latency, keyword recall per model, noise level and phone position) and a noisy-test-set maker.
- Model candidates pinned by revision and SHA-256, with one comparison table. **No model file is in git.**
- A guide for LLM consumers, and a JSON contract.
- `tools/`: scripts to run the pipeline on the DataHive real conversations and analyse the result.

## Decisions already made, and why

| Decision | Why |
|---|---|
| STT lives in its own `stt/` folder, not wired into the app | The architecture puts STT on the phones and bans ML libraries in `backend/` |
| Best candidate so far: `maleo-ai/whisper-small-id` as ggml q8_0, 264.5 MB | Keeps its accuracy (ride-sentence WER 0.129 against 0.120, keyword recall 0.93 against 0.94). Stock tiny and base are not usable (keyword recall 0.40 and 0.57) |
| No model or audio in git | GitHub rejects files over 100 MB, history is permanent, and recordings need consent |
| Conventional Commits | Asked for by the author. `main` uses plain sentences |

## Measured on real conversations (DataHive sample, 4 of 11 conversations, 31 minutes, 652 segments)

No reference transcript exists, so no WER. All of this is one model (maleo ggml), one channel at a time, which is **easier** than one phone on a motorbike.

- **Whisper hallucinates web-video phrases on real calls** ("selamat datang di video ini", "jangan lupa like dan subscribe"). Each of the 4 conversations had 5 to 8 lines with web-video wording. The old filter list caught 10 lines; the extended list in this branch catches 23, with 0 false matches on 1,384 FLEURS and ride texts. Trade-off: a person who really says "subscribe" loses that segment. Whether all 23 are hallucinations needs a listening check; two conversations open with "selamat datang di video ini" in the first seconds.
- **Speaker changes are fast:** 26 to 48% happen with a gap under 0.5 s, so on one microphone the current VAD setting (merge gaps under 0.5 s) would join them into one segment. 21 to 42% are real interruptions. One microphone cannot separate those.
- **The text classifier raised alarms on ordinary friendly talk:** 11.2% of segments at probability 0.8 or more, 6.6% at 0.9, 3.0% at 0.95, none at 0.99. The sample looks like greetings and small talk ("halo", "ini oke banget"). This is Akmal's reading, not a human label.

## Decisions still open

1. **The classifier** (a DistilBERT with 11 labels): what data trained it, how it was evaluated, what input it expects (one utterance or a window with speaker tags), how its labels map to the app rules (threat, sexual harassment, uncomfortable) and thresholds 0.6 and 0.8. Its tokenizer has an **English** vocabulary (1 of 20 common Indonesian words is one token), so it is not the IndoBERT planned in `ARCHITECTURE.md`. On the 24 script sentences it labelled 18 as LOGISTICS and caught 4 of 9 harassing lines. Owner: whoever trained it.
2. **Phone runtime:** `ARCHITECTURE.md` plans sherpa-onnx. The maleo ggml build exists and runs on whisper.cpp (Flutter packages exist). No ONNX export of maleo exists, and nothing was measured on a phone (speed, memory, battery). Owner: mobile team.
3. **VAD merge setting (0.5 s)** against the turn-taking numbers above, and whether one phone or two will record.
4. **Under 100 MB:** Indonesian fine-tunes of tiny and base exist (Apache-2.0) and are not measured: `cahya/whisper-tiny-id`, `Bagus/whisper-tiny-common_voice_17_0-id`, `Bagus/whisper-base-common_voice_17_0-id`. Estimated 8-bit size is 40 to 55 MB (tiny) and 75 to 100 MB (base): an estimate.
5. **Telling people apart** (not who is the driver): sherpa-onnx has speaker diarization. Rule 6 in `CLAUDE.md` says no speaker recognition in this module, and voice prints are biometric data. Not started. A two-phone loudness idea was only simulated, on synthetic audio.
6. **New dependencies:** `stt/pyproject.toml` lists torch, transformers, silero-vad and others; the whisper.cpp backend needs `pywhispercpp`. The repo rule is to ask before adding dependencies, so a reviewer should approve.

## Next steps, in order

1. Give PR #1 a description and get a review.
2. Listen to the real conversations and judge the hallucination lines and the classifier alarms. Outputs are `convo_out/<file>/dialog.txt` after running the tools (below).
3. Run the DataHive tools on all 11 conversations (only 4 were analysed).
4. Measure the Indonesian tiny and base fine-tunes on the ride-sentence set with `benchmark_stt.py`, then convert the promising one (ggml q8_0 or ONNX int8) and measure again.
5. Get a recording of a real ride (with consent). Every accuracy number here comes from synthetic voices, read speech or friendly phone calls.
6. Measure speed, memory and battery on a mid-range phone.

## Commands

```bash
# tests (no model, no torch)
python -m pytest -q

# the model: pinned by hash, see models/README.md for the download commands

# pipeline on one file
python stt_service.py --audio ride.wav --backend whispercpp \
    --model models/maleo-small-id-q8_0/ggml-small-id-q8_0.bin --view llm

# benchmark
python benchmark_stt.py --manifest noisy/manifest.csv --audio_dir noisy \
    --model maleo-ai/whisper-small-id --keywords keywords.txt --out results.csv

# DataHive real conversations (dataset: huggingface.co/datasets/datahiveai/indonesian-conversations-sample, CC BY 4.0)
python tools/datahive_run.py --data_dir <folder with the mp3 and metadata.jsonl> \
    --model models/maleo-small-id-q8_0/ggml-small-id-q8_0.bin --out_dir convo_out
python tools/datahive_analyze.py --out_dir convo_out [--classifier <folder>]
```

The DataHive run needs `pywhispercpp`, `torch`, `silero-vad`, `scipy` and `soundfile`. On a laptop CPU, with other work running, it took 0.5 to 0.7 seconds per second of audio (measured on 4 files).

## Only on Akmal's laptop (not in git)

| Item | What it is | How to get it again |
|---|---|---|
| The classifier model | A `temp/` folder in Akmal's clone of this repo: `model.safetensors` (268 MB) plus tokenizer and config. It is untracked and excluded locally. Its `training_args.bin` is a pickle and was never opened | **Cannot be recreated. Ask Akmal for a copy through shared storage, never git** |
| A local playground | A small web page and server to type sentences, hear TTS, compare models and see classifier labels, plus a sherpa-onnx backend. Not in this branch | Ask Akmal to push it as a follow-up; it needs `sherpa-onnx` and `edge-tts` |
| Model files, DataHive audio, result CSVs | maleo ggml, stock tiny, base, tiny fp32 for sherpa-onnx, the dataset, `results_*.csv` | The download and run commands above and in `models/README.md` |
| TTS tools, a notebook, a two-phone simulation | Used to make synthetic test voices and to test an idea for telling driver and passenger apart | Not pushed. Results are summarised in this folder's docs |

## Things that will surprise you

- **Importing `silero_vad` sets PyTorch to 1 thread for the whole process** and makes a later Whisper call 2 to 3 times slower. `SileroVAD` restores the count. Create the STT backend first, then the VAD.
- **The maleo and cahya model cards say both were fine-tuned on FLEURS.** FLEURS is not held out for them, so their FLEURS numbers are optimistic. Compare models on the ride-sentence set.
- **Company security hooks run on every commit and push** (secrets and dependency scans). They passed on every commit here. Do not bypass them.
- `pipeline.mask` in the backend only masks phone numbers; this module also masks plates and emails.
- The Vercel bot on the PR shows a failed preview deploy because the author is not in that Vercel team. It is not caused by this code.
