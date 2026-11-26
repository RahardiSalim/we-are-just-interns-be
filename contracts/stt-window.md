# STT window: `gosafe.stt.window.v1`

One JSON object per audio window, produced by [`stt/stt_service.py`](../stt/stt_service.py) (`process_window`). Nothing in the API or in Firestore uses it yet: today the phone sends `deviceTranscript` ([ARCHITECTURE.md](ARCHITECTURE.md)). This contract is the shape the modelling team's pipeline writes, so the phone, the backend and the dashboard can adopt it later without guessing.

Change rule: adding a field is compatible. Removing a field or changing its meaning needs `v2` and an update here, in the same change as the code.

## Window

| Field | Type | Notes |
|---|---|---|
| `schema_version` | string | `"gosafe.stt.window.v1"` |
| `window_id` | string | `"<trip_id>_w<offset seconds>"` |
| `trip_id` | string | Supplied by the caller. For GoSafe it is the GoJek order ID (a trip carries no location) |
| `service` | string | `"goride"` by default |
| `window` | `{ start_s, end_s }` | Seconds, offset included |
| `provenance` | object | See below |
| `segments` | array | See below. Empty when no speech was found |
| `window_summary` | object | See below |

`provenance`: `stt_path`, `backend` (model id), `vad` (`name`, `min_silence_s`, `pad_s`, `max_len_s`), `decode` (`language`, always `"id"`), `normalizer_version`, `pii_masker_version`, `processed_at` (UTC, ISO 8601).

## Segment

| Field | Type | Notes |
|---|---|---|
| `seg_id` | string | `s000`, `s001`, … |
| `start_s`, `end_s` | number | Seconds, window offset included |
| `channel` | string | Free label, `"unknown"` by default |
| `likely_speaker` | `driver` \| `passenger` \| `unknown` | A **hint** given by the caller, not speaker recognition |
| `speaker_confidence` | number | Confidence in the hint, not in the speech |
| `speaker_method` | string | `"provided_hint"` |
| `text_raw` | string | What the model heard. Not masked |
| `text_norm` | string | Lower-case, punctuation removed, slang normalised |
| `text_masked` | string | `text_raw` with PII masked first (`[TELEPON]`, `[PLAT]`, `[EMAIL]`), then normalised like `text_norm` |
| `lang` | string | `"id"` |
| `avg_logprob`, `no_speech_prob` | number \| null | `null` with the `hf` backend |
| `compression_ratio` | number | Repetition check |
| `segment_confidence` | number 0 to 1 | A heuristic, **not** a calibrated probability. Constant 0.70 when the backend gives no `avg_logprob` |
| `flags` | string[] | See below |
| `stt_latency_s` | number | Time for this segment |

### Flags

| Flag | Meaning |
|---|---|
| `empty` | No text |
| `hallucination_lexicon_match` | A known Whisper filler such as "terima kasih telah menonton" |
| `repetition_suspect` | Highly repetitive text |
| `likely_no_speech` | `no_speech_prob` high and `avg_logprob` low |
| `rate_suspect` | Too many or too few words for the duration |
| `low_confidence` | `avg_logprob` low |
| `excluded_from_classifier` | Added when the segment has `empty`, `hallucination_lexicon_match`, `likely_no_speech` or `repetition_suspect`. Consumers must skip the text |

## Summary and status

`window_summary`: `n_segments`, `n_used_for_classifier`, `speech_seconds`, `coverage_ratio` (used speech / all speech), `mean_segment_confidence`, `status`, `processing_s`.

| `status` | Meaning |
|---|---|
| `ok` | At least one usable segment, mean confidence 0.5 or more |
| `low_confidence` | Usable segments, mean confidence below 0.5 |
| `unintelligible` | Speech was found but every segment is excluded |
| `no_speech` | No segment at all |

Low-confidence or empty text is never `ok` by default. Consumers must read `status` and `flags`, and treat `no_speech` and `unintelligible` as "nothing to judge", not as "nothing wrong".

## Mapping to the backend transcript

`to_transcript_lines(window)` returns the `transcript` shape of [firestore-schema.md](firestore-schema.md): `[ { start, end, text, flagged } ]`.

- `start` and `end` are seconds from the window start (`start_s` minus `window.start_s`).
- Segments with `excluded_from_classifier` are dropped.
- `text` is `text_raw`, unmasked: the backend masks before any LLM sees it (ARCHITECTURE.md, "Privacy").
- `flagged` is always `false`. This module does not decide risk flags.

## Privacy

`text_masked` covers phone numbers, plates with an Indonesian region code (any letter case, since STT often writes `b1234 xc`) and emails. It does not cover plates spoken in words, names or addresses; those need an NER step before text goes to a hosted LLM.
