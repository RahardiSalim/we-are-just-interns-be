from datetime import datetime, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from google.cloud import firestore
from pydantic import BaseModel, Field, model_validator

from google.cloud.firestore_v1.base_query import FieldFilter

from app.api.trips import OPEN, participant_trip
from app.core.auth import current_user, require_role
from app.core.firebase import db
from app.services import mailer, pipeline, storage

router = APIRouter(prefix="/incidents", tags=["incidents"])

Label = Literal["normal", "uncomfortable", "sexual_harassment", "threat"]
CLIP_RETENTION = timedelta(days=7)
URGENCY = {"manual_unsafe": 0, "auto": 1, "sos": 2}


class TranscriptLine(BaseModel):
    start: float = Field(ge=0)
    end: float = Field(ge=0)
    text: str = Field(max_length=2000)


class CreateIncident(BaseModel):
    tripId: str
    trigger: Literal["sos", "manual_unsafe", "auto"]  # auto: the phone's classifier hit the high threshold
    windowStart: datetime
    windowEnd: datetime
    deviceTranscript: list[TranscriptLine] | None = Field(None, max_length=500)
    deviceLabel: Label | None = None
    deviceScore: float | None = Field(None, ge=0, le=1)

    @model_validator(mode="after")
    def auto_needs_the_phone_verdict(self):
        if self.trigger == "auto" and (self.deviceLabel is None or self.deviceScore is None):
            raise ValueError("trigger auto needs deviceLabel and deviceScore")
        return self


@router.post("")
def create_incident(body: CreateIncident, background: BackgroundTasks, user: dict = Depends(current_user)) -> dict:
    """One case per ride: a report while the ride already has an open case (from either phone) joins it."""
    trip = participant_trip(body.tripId, user["uid"])
    consented = trip["consent"]["rider"] and trip["consent"]["driver"]
    incidents = db().collection("incidents")
    report = {"trigger": body.trigger, "by": user["uid"], "label": body.deviceLabel, "score": body.deviceScore,
              "at": datetime.now(timezone.utc)}

    @firestore.transactional
    def file(tx) -> tuple[str, bool, str | None]:
        same_ride = tx.get(incidents.where(filter=FieldFilter("tripId", "==", body.tripId)))
        open_case = next((c for c in same_ride if c.get("status") in OPEN), None)
        if open_case:
            more_urgent = URGENCY[body.trigger] > URGENCY[open_case.get("trigger")]
            tx.update(open_case.reference, {"reports": firestore.ArrayUnion([report]),
                                            **({"trigger": body.trigger} if more_urgent else {})})
            return open_case.id, True, None
        ref = incidents.document()
        clip_path = f"clips/{ref.id}.wav" if consented else None  # nothing is uploaded without both consents
        tx.set(ref, {
            "tripId": body.tripId,
            "reportedBy": user["uid"],
            "trigger": body.trigger,
            "reports": [report],
            "windowStart": body.windowStart,
            "windowEnd": body.windowEnd,
            "status": "awaiting_upload",
            "severity": None,
            "label": body.deviceLabel,
            "score": body.deviceScore,
            "transcript": [{**t.model_dump(), "flagged": False} for t in body.deviceTranscript or []],
            "summary": None,
            "clipPath": clip_path,
            "source": "device" if body.deviceTranscript else "cloud",
            "live": False,
            "assignedAgent": None,
            "decision": None,
            "createdAt": firestore.SERVER_TIMESTAMP,
            "deleteAt": datetime.now(timezone.utc) + CLIP_RETENTION,
        })
        return ref.id, False, clip_path

    incident_id, merged, clip_path = file(db().transaction())
    if body.trigger == "sos":
        background.add_task(mailer.sos_received, incident_id)  # "ticket created" email, after the response
    if merged:
        if body.trigger in ("sos", "auto"):
            pipeline.upgrade(incident_id)
        return {"incidentId": incident_id, "merged": True}  # nothing to finalize: the case is already open
    # shortcut: no "failed after 10 min" sweep for incidents never finalized; they expire via deleteAt.
    return {
        "incidentId": incident_id,
        "merged": False,
        "uploadUrl": storage.signed_url(clip_path, "PUT") if clip_path else None,
        "uploadMethod": storage.upload_method(),  # send the WAV bytes with this method and Content-Type: audio/wav
    }


@router.post("/{incident_id}/finalize", status_code=202)
def finalize(incident_id: str, background: BackgroundTasks, user: dict = Depends(current_user)) -> dict:
    ref = db().document("incidents", incident_id)

    @firestore.transactional
    def claim(tx) -> None:
        snap = ref.get(transaction=tx)
        if not snap.exists:
            raise HTTPException(404, "Incident not found")
        if snap.get("reportedBy") != user["uid"]:
            raise HTTPException(403, "Not your incident")
        if snap.get("status") != "awaiting_upload":
            raise HTTPException(409, "Already finalized")
        tx.update(ref, {"status": "processing"})

    claim(db().transaction())
    background.add_task(pipeline.process, incident_id)
    return {"status": "processing"}


class Decision(BaseModel):
    action: Literal["dismiss", "warn_driver", "suspend_driver", "contact_rider"]
    note: str = Field("", max_length=2000)


def audit(agent_id: str, incident_id: str, action: str) -> None:
    db().collection("auditLogs").add(
        {"agentId": agent_id, "incidentId": incident_id, "action": action, "ts": firestore.SERVER_TIMESTAMP}
    )


@router.post("/{incident_id}/open")
def open_ticket(incident_id: str, agent: dict = Depends(require_role("agent"))) -> dict:
    ref = db().document("incidents", incident_id)

    @firestore.transactional
    def take(tx) -> None:
        snap = ref.get(transaction=tx)
        if not snap.exists:
            raise HTTPException(404, "Incident not found")
        if snap.get("status") == "escalated":
            tx.update(ref, {"status": "under_review", "assignedAgent": agent["uid"]})
        elif snap.get("status") != "under_review":
            raise HTTPException(409, f"Incident is {snap.get('status')}, not escalated")

    take(db().transaction())
    return {"status": "under_review"}


@router.get("/{incident_id}/clip-url")
def clip_url(incident_id: str, agent: dict = Depends(require_role("agent"))) -> dict:
    snap = db().document("incidents", incident_id).get()
    if not snap.exists or not snap.get("clipPath"):
        raise HTTPException(404, "No clip for this incident")
    url = storage.signed_url(snap.get("clipPath"), "GET")
    audit(agent["uid"], incident_id, "view_clip")  # every clip view is logged
    return {"url": url}


@router.post("/{incident_id}/decision")
def decide(incident_id: str, body: Decision, background: BackgroundTasks, agent: dict = Depends(require_role("agent"))) -> dict:
    ref = db().document("incidents", incident_id)

    @firestore.transactional
    def close(tx) -> None:
        snap = ref.get(transaction=tx)
        if not snap.exists:
            raise HTTPException(404, "Incident not found")
        if snap.get("status") not in ("escalated", "under_review"):
            raise HTTPException(409, f"Incident is {snap.get('status')}")
        tx.update(ref, {
            "status": "closed",
            "decision": {**body.model_dump(), "agentId": agent["uid"], "ts": firestore.SERVER_TIMESTAMP},
            "deleteAt": datetime.now(timezone.utc) + CLIP_RETENTION,  # closed: back to normal retention
        })

    close(db().transaction())
    audit(agent["uid"], incident_id, "decide")
    background.add_task(mailer.decision, incident_id, body.action)  # after the response, so SMTP never slows the agent
    return {"status": "closed"}
