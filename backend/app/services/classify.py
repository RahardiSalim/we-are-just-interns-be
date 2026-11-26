"""Keyword pre-filter for Indonesian (incl. Jakarta slang).

shortcut: stands in for the IndoBERT classifier until the modelling team ships the ONNX export.
It is the spec's high-recall first pass, so expect false alarms; keep `label`/`score` the same shape
so swapping in the model only changes this file.
"""

import re

# Most severe first; a transcript takes the most severe label any line hits.
LEXICON = {
    "threat": [
        "bunuh", "pukul", "hajar", "tusuk", "pisau", "culik", "awas kamu", "diem aja", "diam aja",
        "jangan banyak tanya", "tahu rumah", "tau rumah", "jangan lapor", "lapor-lapor", "turun sini",
    ],
    "sexual_harassment": [
        "cantik banget", "seksi", "bodinya", "pegang", "cium", "raba", "tidur bareng", "ke hotel",
        "mampir ke tempat", "tempat saya", "kamar saya", "buka baju", "telanjang", "bugil",
    ],
    "uncomfortable": [
        "tinggal sendiri", "sendirian", "punya pacar", "rumahnya di mana", "minta nomor", "nomor wa",
        "umur berapa", "sayang",
    ],
}
PATTERNS = {label: re.compile(r"\b(" + "|".join(map(re.escape, words)) + r")\b") for label, words in LEXICON.items()}


def classify(lines: list[dict]) -> tuple[list[dict], str, float]:
    """Returns (lines with `flagged` set, label, score)."""
    hits: dict[str, int] = {}
    out = []
    for line in lines:
        text = line["text"].lower()
        counts = {label: len(rx.findall(text)) for label, rx in PATTERNS.items()}
        for label, n in counts.items():
            if n:  # phrases, not lines: two in one sentence is stronger
                hits[label] = hits.get(label, 0) + n
        out.append({**line, "flagged": any(counts.values())})
    label = next((lbl for lbl in LEXICON if lbl in hits), "normal")
    score = min(0.95, 0.5 + 0.15 * hits[label]) if label in hits else 0.5
    return out, label, score
