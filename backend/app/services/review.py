"""Review of a whole flagged ride: summary, verified label, and the moments that back it up.

Tried in order, first usable answer wins:
1. Sahabat-AI (GoTo + Indosat's Indonesian LLM), when LLM_BASE_URL points at an OpenAI-compatible
   endpoint (vLLM, Ollama, or a hosted API).
2. Gemini, when GEMINI_API_KEY is set (Google's OpenAI-compatible endpoint).
3. The keyword rules, which always work; the review says why it fell back.
Agents decide; this only helps.
"""

import json
import logging
from datetime import datetime, timezone

import httpx

from app.core import config
from app.core.firebase import db
from app.services.classify import classify
from app.services.pipeline import mask

log = logging.getLogger(__name__)

LABELS = ("normal", "uncomfortable", "sexual_harassment", "threat")

SYSTEM = (
    "You review ride-hailing trips in Indonesia for passenger and driver safety. "
    "You get the full transcript of one ride (speech-to-text, Indonesian, may contain errors) "
    "and the moments the phone flagged. Judge the whole conversation in context: friendly small talk "
    "is normal; personal questions that make someone uneasy are uncomfortable; sexual remarks, "
    "advances or invitations are sexual_harassment; intimidation or threats are threat. "
    "Never invent words that are not in the transcript. Reply with JSON only, no prose:\n"
    '{"summary": "<3 sentences max, Bahasa Indonesia, neutral, no names>", '
    '"label": "normal|uncomfortable|sexual_harassment|threat", "confidence": <0..1>, '
    '"moments": [{"at": <seconds, copied from a transcript line>, "label": "<label>", '
    '"reason": "<short, Bahasa Indonesia>"}]}'
)


def providers() -> list[dict]:
    """The configured LLMs, best first."""
    out = []
    if config.LLM_BASE_URL:
        out.append({"source": "sahabat-ai", "base": config.LLM_BASE_URL, "key": config.LLM_API_KEY, "model": config.LLM_MODEL})
    if config.GEMINI_API_KEY:
        out.append({"source": "gemini", "base": config.GEMINI_BASE_URL, "key": config.GEMINI_API_KEY, "model": config.GEMINI_MODEL})
    return out


def ask_llm(messages: list[dict], provider: dict) -> str:
    res = httpx.post(
        f"{provider['base'].rstrip('/')}/chat/completions",
        headers={"Authorization": f"Bearer {provider['key']}"},
        json={"model": provider["model"], "messages": messages, "temperature": 0},
        timeout=60,
    )
    res.raise_for_status()
    return res.json()["choices"][0]["message"]["content"]


def _mmss(sec: float) -> str:
    return f"{int(sec // 60):02d}:{int(sec % 60):02d}"


def _snap(at: float, lines: list[dict]) -> float:
    """A cited time must be a real transcript line, so a reviewer can jump to it."""
    return min(lines, key=lambda line: abs(line["at"] - at))["at"]


def _by_llm(lines: list[dict], markers: list[dict], provider: dict) -> dict:
    transcript = "\n".join(f"[{line['at']}] {line['text']}" for line in lines)
    flagged = "\n".join(f"[{m['at']}] phone flag: {m['kind']} {m.get('label') or ''}" for m in markers)
    raw = ask_llm([
        {"role": "system", "content": SYSTEM},
        {"role": "user", "content": f"Transcript:\n{transcript}\n\nPhone flags:\n{flagged or 'none'}"},
    ], provider)
    data = json.loads(raw[raw.index("{"): raw.rindex("}") + 1])  # tolerate text around the JSON
    if data["label"] not in LABELS:
        raise ValueError(f"unknown label {data['label']!r}")
    moments = [
        {"at": _snap(float(m["at"]), lines), "label": m["label"], "reason": str(m["reason"])[:300]}
        for m in data.get("moments", [])
        if m.get("label") in LABELS
    ]
    return {
        "source": provider["source"],
        "model": provider["model"],
        "summary": mask(str(data["summary"]))[:2000],
        "label": data["label"],
        "confidence": max(0.0, min(1.0, float(data["confidence"]))),
        "moments": sorted({m["at"]: m for m in moments}.values(), key=lambda m: m["at"]),
    }


def _by_rules(lines: list[dict], duration: float) -> dict:
    flagged, label, score = classify(lines)
    hits = [line for line in flagged if line["flagged"]]
    moments = [
        {"at": line["at"], "label": classify([line])[1], "reason": "Mengandung frasa yang ditandai."}
        for line in hits
    ]
    summary = (
        f"Perjalanan {_mmss(duration)} dengan {len(lines)} kalimat terdengar. "
        + (f"{len(hits)} kalimat ditandai, paling berat: {label}." if hits else "Tidak ada kalimat yang ditandai.")
    )
    return {"source": "rules", "summary": summary, "label": label, "confidence": score, "moments": moments}


def review_recording(trip_id: str) -> None:
    ref = db().document("trips", trip_id)
    rec = ref.get().to_dict()["recording"]
    lines = [{**line, "text": mask(line["text"])} for line in rec.get("transcript", [])]
    if not lines:
        return
    result, failed = None, []
    for provider in providers():
        try:
            result = _by_llm(lines, rec.get("markers", []), provider)
            break
        except Exception as e:
            log.exception("%s review failed trip=%s", provider["source"], trip_id)
            failed.append(f"{provider['source']} ({type(e).__name__})")
    note = None
    if failed:
        note = "Could not review with " + ", ".join(failed) + "."
    if not result:
        note = (note + " " if note else "No AI model is connected yet. ") + "Rule-based review shown."
        result = _by_rules(lines, rec.get("durationSec", 0))
    ref.update({"recording.review": {**result, "note": note, "createdAt": datetime.now(timezone.utc)}})
