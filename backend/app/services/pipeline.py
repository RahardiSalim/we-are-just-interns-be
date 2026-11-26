"""Incident lifecycle after finalize: transcript → label → severity → check-in or escalation.

Only this module and the API handlers change `incidents.status` (architecture rule 5).
"""

import logging
import re
import threading
from datetime import datetime, timedelta, timezone

from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from app.core import config
from app.core.firebase import db
from app.services import notify
from app.services.classify import classify

log = logging.getLogger(__name__)

OPEN_CASE_RETENTION = timedelta(days=30)
PHONE = re.compile(r"(\+62|\b0)[\d\s-]{8,14}\d")
TRIGGER_TEXT = {"sos": "SOS", "manual_unsafe": '"Saya merasa tidak aman"', "auto": "deteksi otomatis di ponsel"}


def transcribe(clip_path: str | None) -> list[dict]:
    # Speech-to-text is edge AI on the phones. Cloud STT (Chirp 3) is future work, so nothing to add here yet.
    return []


def severity(trigger: str, label: str | None) -> str:
    if trigger == "auto":
        return "high"  # the phone only reports on its own at the high threshold
    if label in ("threat", "sexual_harassment"):
        return "high"
    if label is None and trigger == "sos":
        return "high"  # SOS with nothing to judge it by: a person looks at it
    return "medium"  # a person reported it, so never dismiss silently


def process(incident_id: str) -> None:
    ref = db().document("incidents", incident_id)
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
        if sev == "high":
            escalate(incident_id)  # for trigger auto the phones already asked "Are you OK?" themselves
        else:
            start_checkins(incident_id, inc["tripId"])
    except Exception as e:
        log.exception("processing failed incident=%s", incident_id)
        ref.update({"status": "failed", "error": str(e)[:500]})


def start_checkins(incident_id: str, trip_id: str) -> None:
    """Asks rider and driver "Are you OK?" after an "I feel unsafe" press the model couldn't confirm."""
    trip = db().document("trips", trip_id).get().to_dict()
    db().document("incidents", incident_id).update({"status": "checkin_pending"})
    for uid in (trip["riderId"], trip["driverId"]):
        ref = db().collection("checkins").document()
        ref.set({"incidentId": incident_id, "userId": uid, "status": "sent",
                 # A GoRide driver can't tap while riding, so their answer isn't required (silence never escalates).
                 "required": not (uid == trip["driverId"] and trip.get("mode") == "goride"),
                 "sentAt": firestore.SERVER_TIMESTAMP, "repliedAt": None})
        notify.push(uid, {"type": "checkin", "checkinId": ref.id, "incidentId": incident_id})
    # shortcut: in-process timer; lost if the instance restarts. Move to Cloud Tasks if that bites.
    timer = threading.Timer(config.CHECKIN_TIMEOUT_SEC, checkin_timeout, [incident_id])
    timer.daemon = True
    timer.start()


def checkin_timeout(incident_id: str) -> None:
    ref = db().document("incidents", incident_id)

    @firestore.transactional
    def expire(tx) -> bool:
        snap = ref.get(transaction=tx)
        if not snap.exists or snap.get("status") != "checkin_pending":
            return False  # already answered
        silent = [c for c in tx.get(db().collection("checkins").where(filter=FieldFilter("incidentId", "==", incident_id)))
                  if c.get("status") == "sent"]
        for c in silent:
            tx.update(c.reference, {"status": "no_reply"})
        escalate_now = any(c.get("required") for c in silent)
        tx.update(ref, {"status": "escalated" if escalate_now else "resolved_ok"})
        return escalate_now

    if expire(db().transaction()):
        escalate(incident_id)


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
