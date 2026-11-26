"""Tests for the STT module. They need numpy, scipy and soundfile only: the model
backends (torch, transformers, silero-vad) are not imported, so these run in seconds."""
import sys
import types

import numpy as np
import pytest

import stt_service as S


# ------------------------------------------------------------------ PII masking
@pytest.mark.parametrize("text", [
    "nomor saya 0812 3456 7890 ya",
    "nomor saya 081234567890 ya",
    "hubungi +62 812-3456-7890 sekarang",
])
def test_phone_numbers_are_masked(text):
    assert "[TELEPON]" in S.mask_pii(text)
    assert "8123" not in S.mask_pii(text)


@pytest.mark.parametrize("text", [
    "plat motor saya B 1234 XYZ",
    "lat motor saya b1234 xc",  # STT writes plates in lowercase and gets letters wrong
    "platnya ab 1234 cd ya",
    "B1234XYZ",
    "motor saya d 5678",  # the letter suffix is optional
])
def test_plates_are_masked(text):
    assert "[PLAT]" in S.mask_pii(text)


@pytest.mark.parametrize("text", [
    "saya sudah di 5 km dari sini",
    "rumah saya rt 5 rw 3",
    "jam 5 sore saya sampai",
    "km 12 jalan tol",
    "pukul 10 pagi",
    "tahun 2025 kemarin",
])
def test_ordinary_numbers_are_not_masked_as_plates(text):
    assert S.mask_pii(text) == text


def test_email_is_masked():
    assert S.mask_pii("kirim ke nama@example.com ya") == "kirim ke [EMAIL] ya"


# ----------------------------------------------------------------- normalisation
def test_slang_is_normalised():
    assert S.normalize("Udah gak banget, gue pulang aja") == "sudah tidak sekali saya pulang saja"


def test_placeholders_survive_normalisation():
    assert "[TELEPON]" in S.normalize(S.mask_pii("telepon 081234567890 dong"))


# ------------------------------------------------------------------------- flags
def test_hallucination_phrase_is_flagged():
    flags = S.make_flags("Terima kasih telah menonton", 3.0, {}, S.HALLUCINATION_PHRASES)
    assert "hallucination_lexicon_match" in flags


def test_empty_text_is_flagged_empty():
    assert S.make_flags("", 3.0, {}, S.HALLUCINATION_PHRASES) == ["empty"]


def test_repetition_is_flagged():
    assert "repetition_suspect" in S.make_flags("ha " * 40, 6.0, {}, S.HALLUCINATION_PHRASES)


def test_low_confidence_needs_a_logprob():
    res = {"avg_logprob": -1.5, "no_speech_prob": 0.1}
    assert "low_confidence" in S.make_flags("halo selamat siang pak", 3.0, res, S.HALLUCINATION_PHRASES)
    assert "low_confidence" not in S.make_flags("halo selamat siang pak", 3.0, {}, S.HALLUCINATION_PHRASES)


# ---------------------------------------------------------------------- segments
def test_close_spans_merge_and_tiny_ones_drop():
    segs = S.build_segments([(1.0, 2.0), (2.2, 3.0), (10.0, 10.2)], total_s=15.0)
    assert segs == [(0.75, 3.25)]  # merged (gap < 0.5 s), padded 0.25 s; the 0.2 s blip is dropped


def test_long_speech_is_split_to_the_max_length():
    segs = S.build_segments([(0.0, 45.0)], total_s=50.0)
    assert len(segs) == 3
    assert all(e - s <= 20.0 for s, e in segs)


# ----------------------------------------------------------------- full pipeline
def synthetic_ride(n_bursts=4, seed=0):
    """Noise bursts with silence between them, standing in for speech."""
    rng = np.random.default_rng(seed)
    sr = S.SR
    parts = [np.zeros(sr)]
    for dur in (2.0, 2.5, 1.5, 2.0)[:n_bursts]:
        t = np.arange(int(sr * dur)) / sr
        parts += [0.3 * 0.5 * (1 + np.sin(2 * np.pi * 4 * t)) * rng.standard_normal(len(t)), np.zeros(sr)]
    x = np.concatenate(parts) + 0.001 * rng.standard_normal(sum(map(len, parts)))
    return x.astype("float32")


TEXTS = [
    "Bang, udah deket belum? Gak usah ngebut ya",
    "Nomor saya 0812 3456 7890, plat motornya B 1234 XYZ",
    "Terima kasih telah menonton",
    "",
]


def run(audio, texts):
    return S.process_window(audio, S.DummyBackend(texts), S.EnergyVAD(), trip_id="T1")


def test_window_follows_the_schema_and_keeps_status_fields():
    win = run(synthetic_ride(), TEXTS)
    assert win["schema_version"] == "gosafe.stt.window.v1"
    assert win["provenance"]["decode"]["language"] == "id"
    summary = win["window_summary"]
    assert (summary["n_segments"], summary["n_used_for_classifier"]) == (4, 2)
    assert summary["status"] == "ok"
    seg = win["segments"][1]
    assert "[TELEPON]" in seg["text_masked"] and "[PLAT]" in seg["text_masked"]
    assert seg["speaker_method"] == "provided_hint"  # a hint, never speaker recognition


def test_bad_segments_are_excluded_not_treated_as_normal():
    win = run(synthetic_ride(), TEXTS)
    hallucination, empty = win["segments"][2], win["segments"][3]
    assert "excluded_from_classifier" in hallucination["flags"]
    assert "excluded_from_classifier" in empty["flags"]


def test_silence_gives_no_speech():
    win = run(np.zeros(S.SR * 5, dtype="float32"), TEXTS)
    assert win["window_summary"]["status"] == "no_speech"
    assert win["segments"] == []


def test_only_unusable_text_gives_unintelligible():
    win = run(synthetic_ride(), ["", "Terima kasih telah menonton"])
    assert win["window_summary"]["status"] == "unintelligible"


def test_views_mark_unclear_segments():
    win = run(synthetic_ride(), TEXTS)
    view = S.render_llm_view(win)
    assert "(tidak jelas)" in view and "Status transkrip: ok" in view
    assert "[PLAT]" in S.render_classifier_view(win)


# -------------------------------------------------------- backend transcript shape
def test_transcript_lines_match_the_backend_shape():
    win = run(synthetic_ride(), TEXTS)
    lines = S.to_transcript_lines(win)
    assert len(lines) == 2  # the hallucination and the empty segment are dropped
    assert set(lines[0]) == {"start", "end", "text", "flagged"}
    assert lines[0]["flagged"] is False
    assert "0812" in lines[1]["text"]  # raw text: the backend masks before any LLM


def test_transcript_times_are_relative_to_the_window():
    audio = synthetic_ride()
    shifted = S.process_window(audio, S.DummyBackend(TEXTS), S.EnergyVAD(), trip_id="T1", offset_s=600.0)
    assert S.to_transcript_lines(shifted) == S.to_transcript_lines(run(audio, TEXTS))


# ------------------------------------------------------ whisper.cpp backend (glue only)
def test_whispercpp_backend_joins_segments_and_forces_indonesian(monkeypatch):
    """Uses a stand-in for pywhispercpp, so no model and no extra package are needed."""
    calls = {}

    class Seg:
        def __init__(self, text):
            self.text = text

    class FakeModel:
        def __init__(self, path, **params):
            calls["path"], calls["params"] = path, params

        def transcribe(self, audio):
            calls["samples"] = len(audio)
            return [Seg(" halo "), Seg("selamat siang ")]

    fake = types.ModuleType("pywhispercpp.model")
    fake.Model = FakeModel
    monkeypatch.setitem(sys.modules, "pywhispercpp", types.ModuleType("pywhispercpp"))
    monkeypatch.setitem(sys.modules, "pywhispercpp.model", fake)

    backend = S.WhisperCppBackend("/models/ggml-small-id-q8_0.bin")
    out = backend.transcribe(np.zeros(S.SR, dtype="float32"))

    assert out == {"text": "halo selamat siang", "avg_logprob": None, "no_speech_prob": None}
    assert calls["params"]["language"] == "id"  # language is forced, never auto-detected
    assert calls["samples"] == S.SR
    assert backend.name == "whisper.cpp ggml-small-id-q8_0.bin"

