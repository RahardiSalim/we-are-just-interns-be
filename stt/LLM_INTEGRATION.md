# STT module: guide for LLM integration

For anyone who feeds this module's output to an LLM (the ride review in `backend/app/services/review.py`, a classifier prompt, an agent), and for the engineers wiring it. It says what goes in, how the text is made, what comes out, and **how an LLM should read it**. The JSON contract itself is in [contracts/stt-window.md](../contracts/stt-window.md); this page is the usage guide on top of it.

## At a glance

| | |
|---|---|
| Does | Indonesian audio in, a transcript an LLM can read out. Voice detection, speech-to-text per segment, filters, PII masking |
| Input | An audio file or a mono 16 kHz array, plus an optional speaker hint and the trip ID |
| Output | A JSON window (`gosafe.stt.window.v1`) and three text views: LLM view, classifier view, backend transcript lines |
| Language | Indonesian, forced. Slang and English words in the same sentence are expected |
| Where it runs | **Not deployed.** The phones run STT on-device and the backend has no ML libraries ([ARCHITECTURE.md](../contracts/ARCHITECTURE.md)). This folder is the reference pipeline. The text contract below is what an LLM should get whichever runtime produced it |
| Best model so far | `maleo-ai/whisper-small-id` as ggml q8_0, 264.5 MB ([models/README.md](models/README.md)) |

## Input

**Audio.** Anything `soundfile` reads (wav, flac, ogg/opus, mp3) is converted to 16 kHz mono. `.m4a` (iPhone, AAC) is not guaranteed; convert to wav first. Speech longer than 20 s without a pause is split into 20 s pieces.

**Python**

```python
import stt_service as S

audio = S.load_mono_16k("ride.wav")
backend = S.HFBackend("maleo-ai/whisper-small-id")   # or S.WhisperCppBackend(path) or S.FasterWhisperBackend(path)
vad = S.SileroVAD()                                   # create the backend first, then the VAD
window = S.process_window(audio, backend, vad, trip_id="12345", speaker="unknown")
llm_text = S.render_llm_view(window, trip_context="GoRide, 1 penumpang.")
```

**CLI**

```bash
python stt_service.py --audio ride.wav --trip_id 12345 --backend hf \
    --model maleo-ai/whisper-small-id --speaker unknown --view llm --out window.json
```

| `process_window` argument | Meaning |
|---|---|
| `audio` | float32 mono array at 16 kHz |
| `backend`, `vad` | STT and voice detection objects |
| `trip_id` | Free string. For GoSafe, the GoJek order ID. Appears in `window_id` |
| `speaker` | `driver`, `passenger` or `unknown`. **A hint from the caller** (for example which phone recorded the file), not something the module detects |
| `speaker_conf` | How much you trust that hint, 0 to 1. Default 0.5 |
| `offset_s` | Where this window starts in the ride, in seconds. Added to all times |
| `channel` | Free label, `unknown` by default |

| Backend | Gives `avg_logprob` | Needs |
|---|---|---|
| `dummy` | fixed values | nothing. Tests only |
| `hf` | no | `transformers`, `torch` |
| `whispercpp` | no | `pywhispercpp` and a ggml model file |
| `faster` | yes | `faster-whisper` and a CTranslate2 model (not tested here) |

## How it works

1. **Load** the audio as mono 16 kHz.
2. **Voice detection.** Silero VAD (an energy detector exists for tests). Speech gaps shorter than 0.5 s are merged, each segment gets 0.25 s of padding on both sides, speech shorter than 0.5 s is dropped, and segments longer than 20 s are split.
3. **Speech-to-text per segment**, language forced to Indonesian. Each segment is transcribed on its own, after the voice stops. This is **not streaming**: no partial words while someone is still talking.
4. **Filters.** Each segment gets flags: `empty`, `hallucination_lexicon_match` (Whisper fillers such as "terima kasih telah menonton"), `repetition_suspect`, `rate_suspect` (too many or too few words for the duration), `likely_no_speech` and `low_confidence` (both need `avg_logprob`).
5. **Exclusion.** A segment with `empty`, `hallucination_lexicon_match`, `likely_no_speech` or `repetition_suspect` also gets `excluded_from_classifier`. It stays in the JSON but its text is not shown to the LLM.
6. **Three text forms per segment.** `text_raw` is what the model heard. `text_norm` is lower-case, without punctuation, with slang expanded (gak to tidak, udah to sudah, gue to saya). `text_masked` is `text_raw` with PII masked first (`[TELEPON]`, `[PLAT]`, `[EMAIL]`) and then normalised. The LLM view uses `text_masked`.
7. **Window status** from the used segments: `ok`, `low_confidence`, `unintelligible` or `no_speech`.

`segment_confidence` is a heuristic, not a probability. With the `hf` and `whispercpp` backends it is a constant 0.70.

## Output

### The LLM view (what to put in the prompt)

```
[<mm:ss>-<mm:ss>] [<SPEAKER>|<conf>] <text_masked>[ (kurang jelas)]
[<mm:ss>-<mm:ss>] [TIDAK_PASTI] (tidak jelas)
Status transkrip: <ok | low_confidence | unintelligible | no_speech>
```

`SPEAKER` is `DRIVER`, `PENUMPANG` or `TIDAK_PASTI`. The first line is always "Transkrip (tag pembicara adalah dugaan, bukan fakta):", and an optional trip-context line goes before it. Times are rounded to whole seconds here; the JSON has 0.01 s.

A real run (maleo, Silero VAD, a 31 s synthetic dialogue with motorbike noise, `speaker="unknown"`):

```
Perjalanan GoRide, 1 penumpang. Percakapan sepanjang 30 detik.

Transkrip (tag pembicara adalah dugaan, bukan fakta):
[00:01-00:04] [TIDAK_PASTI|0.50] badan mbak bagus sekali ya seperti model
[00:05-00:10] [TIDAK_PASTI|0.50] pak tolong jangan ngomong seperti gitu saya tidak nyaman
[00:11-00:14] [TIDAK_PASTI|0.50] ah jangan sob jual mahal mbak aku cuma mujikok
[00:16-00:20] [TIDAK_PASTI|0.50] berhenti ngomong begitu saya mau turun sekarang
[00:21-00:25] [TIDAK_PASTI|0.50] duduknya geser dekat sini saja biar tidak dingin
[00:26-00:29] [TIDAK_PASTI|0.50] tidak usah pak saya duduk di sini saja
Status transkrip: ok
```

What was actually said in line three: "Ah jangan sok jual mahal mbak, aku cuma muji kok." The model heard "sob" and "mujikok", so that line has errors in two places. Across our synthetic ride sentences at 10 dB noise the word error rate was about 7% (maleo).

A case with excluded segments (illustrative, from the unit-test setup with scripted texts, not a real transcription):

```
[00:01-00:03] [TIDAK_PASTI|0.50] bang sudah deket belum tidak usah ngebut ya
[00:04-00:07] [TIDAK_PASTI|0.50] nomor saya [TELEPON] plat motornya [PLAT]
[00:07-00:09] [TIDAK_PASTI] (tidak jelas)
[00:10-00:12] [TIDAK_PASTI] (tidak jelas)
Status transkrip: ok
```

### The JSON window

Top level: `schema_version`, `window_id`, `trip_id`, `service`, `window` (`start_s`, `end_s`), `provenance`, `segments`, `window_summary`. All fields, flags and status values are in [contracts/stt-window.md](../contracts/stt-window.md). From the same real run:

```json
{
  "schema_version": "gosafe.stt.window.v1",
  "window_id": "example-order-123_w0",
  "trip_id": "example-order-123",
  "service": "goride",
  "window": { "start_s": 0.0, "end_s": 30.86 },
  "provenance": {
    "stt_path": "cloud_or_device_see_backend", "backend": "maleo-ai/whisper-small-id",
    "vad": { "name": "silero", "min_silence_s": 0.5, "pad_s": 0.25, "max_len_s": 20 },
    "decode": { "language": "id" }, "normalizer_version": "id-norm-0.1",
    "pii_masker_version": "pii-id-0.2", "processed_at": "2026-11-26T13:38:04+00:00"
  },
  "segments": [
    {
      "seg_id": "s002", "start_s": 11.25, "end_s": 14.45, "channel": "unknown",
      "likely_speaker": "unknown", "speaker_confidence": 0.5, "speaker_method": "provided_hint",
      "text_raw": "ah jangan sob jual mahal mbak aku cuma mujikok",
      "text_norm": "ah jangan sob jual mahal mbak aku cuma mujikok",
      "text_masked": "ah jangan sob jual mahal mbak aku cuma mujikok",
      "lang": "id", "avg_logprob": null, "no_speech_prob": null, "compression_ratio": 0.94,
      "segment_confidence": 0.7, "flags": [], "stt_latency_s": 5.282
    }
  ],
  "window_summary": {
    "n_segments": 6, "n_used_for_classifier": 6, "speech_seconds": 21.8, "coverage_ratio": 1.0,
    "mean_segment_confidence": 0.7, "status": "ok", "processing_s": 31.708
  }
}
```

(`segments` is cut to one entry here. `processing_s` and `stt_latency_s` are for an unwarmed PyTorch model on a laptop CPU, not typical speeds.)

### Other views

- **Classifier view**, `render_classifier_view(window)`: one line for a small classifier, segments joined with ` [SEP] `, tags without confidence, excluded segments left out.
- **Backend transcript lines**, `to_transcript_lines(window)`: the `transcript` shape of [firestore-schema.md](../contracts/firestore-schema.md), `[{ "start": 5.15, "end": 9.95, "text": "pak tolong jangan ngomong kayak gitu saya nggak nyaman", "flagged": false }]`. Times are relative to the window start, excluded segments are dropped, and `text` is **unmasked** (the backend masks before any LLM sees it). `flagged` is always `false`.

Give an LLM the **LLM view**. Give it the JSON only if it is a tool that needs the fields.

## How an LLM should read it

1. **Speaker tags are guesses.** `TIDAK_PASTI` is the normal case. The module does not recognise voices. Do not say "the driver said" unless the tag says so, and even then treat it as a hint. The words themselves ("pak", "mbak") are often a better clue than the tag.
2. **`(tidak jelas)` means something was said but cannot be used.** Do not guess its content, and do not count it as silence or as "nothing wrong".
3. **`(kurang jelas)` marks a doubtful segment, but its absence proves nothing.** It comes from `low_confidence` or `rate_suspect`. With the `hf` and `whispercpp` backends there is no `avg_logprob`, so `low_confidence` never fires and only an odd word rate can trigger the marker. A sentence without it can still be wrong, as "mujikok" above shows.
4. **Status decides how much to trust the whole window.**

   | Status | Meaning | What to do |
   |---|---|---|
   | `ok` | Usable text | Judge it, with the caveats here |
   | `low_confidence` | Usable text, mean confidence below 0.5 | Say the transcript is unreliable |
   | `unintelligible` | Speech was found, none of it usable | **Nothing to judge.** Not "safe" |
   | `no_speech` | No speech found | **Nothing to judge.** Not "safe" |

5. **The text is normalised.** Lower-case, no punctuation, slang expanded. Tone and emphasis are gone. If wording matters (a threat versus a joke), use `text_raw` from the JSON.
6. **Placeholders are real masks.** `[TELEPON]`, `[PLAT]`, `[EMAIL]`. Do not try to reconstruct them. **Names, addresses and plates spoken in words ("B seribu dua ratus…") are not masked.**
7. **Expect mishearings.** On our synthetic ride sentences maleo's word error rate was about 7% at 10 dB noise and about 24% at 0 dB. A word may be replaced by a similar-sounding one. Read for the meaning of the whole exchange, not one word.
8. **A missing keyword is not evidence of safety.** On our synthetic ride sentences maleo as ggml q8_0 kept 93% of the keywords overall and 84% at 0 dB (measured: 141 of 152, and 32 of 38). The rest were lost or garbled.
9. **A person decides.** Customer service reviews every case ([ARCHITECTURE.md](../contracts/ARCHITECTURE.md), "Rules"). The output is evidence for a reviewer, never a verdict, and never a reason to ban anyone.
10. **Do not infer who someone is.** No identity, gender, age or voice characteristics come from this module.

### A starting prompt (not tested with an LLM)

```
You read a speech-to-text transcript of a motorbike ride in Indonesian. Rules:
- Speaker tags are guesses. [TIDAK_PASTI] means unknown. Do not attribute words to the driver or
  passenger unless the tag says so, and treat even that as a hint.
- "(tidak jelas)" means a segment could not be used. Do not guess what it said.
- The text can contain wrong words because of road noise. Judge the whole exchange, not one word.
- Placeholders such as [TELEPON] and [PLAT] are masked personal data. Do not guess them.
- If "Status transkrip" is no_speech or unintelligible, answer "tidak ada yang bisa dinilai". That
  is not the same as "aman".
- You give evidence for a human reviewer. You never decide to warn, suspend or ban anyone.
Quote the lines you rely on with their time range, and say how sure you are.
```

## Edge cases

| Situation | What you get | What to do |
|---|---|---|
| Silence or only noise | `segments: []`, status `no_speech`, LLM view with only the header and status | Treat as nothing to judge |
| A model filler ("terima kasih telah menonton") | Segment flagged `hallucination_lexicon_match` and excluded | Nothing: it is hidden from the LLM view except as `(tidak jelas)` |
| Repeated text | `repetition_suspect`, excluded | Same |
| Very long speech without pauses | Split into pieces of at most 20 s | Join by time |
| A phone number in the speech | `[TELEPON]` in the masked text | Keep the placeholder |
| A plate in lower case or with wrong letters (`b1234 xc`) | `[PLAT]` | Same |
| Two people, one phone | One transcript, tags `TIDAK_PASTI` | Do not assume who spoke |
| Two phones recording the same ride | Two windows with the same sentences twice | Merge before the LLM sees them. Not handled here |

## Cost and speed (measured, laptop CPU)

From [models/README.md](models/README.md), on the ride-sentence set:

| Model | Size | Keyword recall | s per 3–6 s clip |
|---|---|---|---|
| maleo ggml q8_0 (whisper.cpp) | 264.5 MB | 0.93 | 0.41 |
| maleo PyTorch | 483.5 MB (fp16) | 0.94 | 0.70 |
| base int8, stock | 160.6 MB | 0.57 | 0.35 |
| tiny int8, stock | 103.6 MB | 0.40 | 0.18 |

The stock base and tiny are not good enough for this job. **None of this is phone speed.**

## Privacy

- Send an LLM only the masked text (the LLM view or `text_masked`), never raw audio, and not `text_raw` unless the backend masked it first. The backend's `pipeline.mask` only covers phone numbers today.
- Phone numbers, plates with a region code and emails are masked here. Names and addresses are not; they need an NER step before a hosted LLM ([ARCHITECTURE.md](../contracts/ARCHITECTURE.md), "Privacy").
- No speaker recognition and no voice prints are made. Speaker tags are hints.

## Versions

`schema_version` is `gosafe.stt.window.v1`. `provenance.normalizer_version` (`id-norm-0.1`) and `provenance.pii_masker_version` (`pii-id-0.2`) change when the text rules change, so store them with any LLM answer you want to reproduce. Adding a field is compatible; removing one or changing its meaning needs a new schema version and an update to [contracts/stt-window.md](../contracts/stt-window.md).

## What is not known yet

- Every number above comes from synthetic ride voices with synthetic noise and from read Wikipedia-style speech. **No recording of a real ride exists**, so real accuracy is unknown.
- Phone speed, memory and battery are not measured.
- The prompt above was not tried with an LLM.
- FLEURS is not held out for maleo (it was trained on it), so FLEURS numbers are optimistic. See [models/README.md](models/README.md).
