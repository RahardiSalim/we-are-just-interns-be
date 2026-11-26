"""Incident lifecycle after finalize: transcript → label → severity → escalation to an agent.

Only this module and the API handlers change `incidents.status` (architecture rule 5).
"""

import logging
import re
from datetime import datetime, timedelta, timezone


from app.core.firebase import db
from app.services.classify import classify

log = logging.getLogger(__name__)

OPEN_CASE_RETENTION = timedelta(days=30)
PHONE = re.compile(r"(\+62|\b0)[\d\s-]{8,14}\d")
TRIGGER_TEXT = {"sos": "SOS", "manual_unsafe": '"Saya merasa tidak aman"', "auto": "deteksi otomatis di ponsel"}


def transcribe(clip_path: str | None) -> list[dict]:
    # Speech-to-text is edge AI on the phones. Cloud STT (Chirp 3) is future work, so nothing to add here yet.
    return []


def severity(trigger: str, label: str | None) -> str:
    if trigger in ("auto", "sos"):
        # auto: the phone only reports on its own at the high threshold. sos: always a person, at once;
        # a check-in would also ask the driver, which gives away a silent report (the safe phrase is an auto flag).
        return "high"
    if label in ("threat", "sexual_harassment"):
        return "high"
    return "medium"  # a person reported it, so never dismiss silently


def process(incident_id: str) -> None:
    ref = db().document("incidents", incident_id)
    inc: dict = {}
    try:
        inc = ref.get().to_dict()
        lines = inc["transcript"] or transcribe(inc["clipPath"])
        label, score = inc.get("label"), inc.get("score")  # set when the device sent its own label
        if lines:
            lines, kw_label, kw_score = classify(lines)
            if label is None:
                label, score = kw_label, kw_score
        sev = severity(inc["trigger"], label)
        ref.update({"transcript": lines, "label": label, "score": score, "severity": sev})
        # Every case goes to an agent; severity orders the queue. No check-in: the phone already asked the
        # rider ("Are you okay?" / "Do you need help right now?"), and asking the driver would tip them off.
        escalate(incident_id)
    except Exception as e:
        log.exception("processing failed incident=%s", incident_id)
        # An SOS or high flag must still reach an agent: the queue shows escalated cases, not failed ones.
        urgent = inc.get("trigger") in ("sos", "auto")
        ref.update({"status": "escalated" if urgent else "failed", "error": str(e)[:500]})


def escalate(incident_id: str) -> None:
    """Sets status escalated (if not already) and writes the summary agents read first."""
    ref = db().document("incidents", incident_id)
    inc = ref.get().to_dict()
    ref.update({
        "status": "escalated",
        "summary": summarize(inc),
        "deleteAt": datetime.now(timezone.utc) + OPEN_CASE_RETENTION,
    })


def mask(text: str) -> str:
    # shortcut: masks phone numbers only; names need NER, add before sending text to a hosted LLM.
    return PHONE.sub("[nomor]", text)


def summarize(inc: dict) -> str:
    # shortcut: template until Sahabat-AI is hosted; feed it the same masked lines then.
    flagged = [mask(line["text"]) for line in inc["transcript"] if line.get("flagged")]
    parts = [f"Pemicu: {TRIGGER_TEXT[inc['trigger']]} pada trip {inc['tripId']}."]
    if inc.get("label"):
        parts.append(f"Penilaian otomatis: {inc['label']} ({round((inc.get('score') or 0) * 100)}%).")
    else:
        parts.append("Tidak ada transkrip; perlu ditinjau manual.")
    if flagged:
        parts.append("Kalimat yang ditandai: " + " / ".join(f'"{t}"' for t in flagged))
    return " ".join(parts)


def upgrade(incident_id: str) -> None:
    """A more urgent report (SOS, a high flag) joined an open case: make it high and put it in front of an agent."""
    ref = db().document("incidents", incident_id)
    status = ref.get().get("status")
    ref.update({"severity": "high"})
    if status != "under_review":  # an agent already has it; don't take it back to the queue
        escalate(incident_id)
