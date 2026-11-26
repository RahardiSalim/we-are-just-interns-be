import secrets
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from google.api_core.exceptions import AlreadyExists
from google.cloud.firestore import SERVER_TIMESTAMP
from pydantic import BaseModel, Field

from app.core.auth import current_user, require_role
from app.core.firebase import db
from app.services import review, storage

router = APIRouter(prefix="/trips", tags=["trips"])

DEMO_DRIVER = "driver1"  # shortcut: every demo trip gets the seeded driver; real matching is GoTo's job
Label = Literal["normal", "uncomfortable", "sexual_harassment", "threat"]
EXTENSIONS = {"audio/mp4": "m4a", "audio/ogg": "ogg", "audio/wav": "wav"}


class StartTrip(BaseModel):
    # GoJek's order ID is the trip ID. No location or route is ever sent: GoJek already has it.
    orderId: str | None = Field(None, pattern=r"^[A-Za-z0-9_-]{1,64}$")  # generated when missing (demo)
    mode: Literal["goride", "gocar"] = "goride"
    # The rider answers the consent prompt when the ride starts; the driver opted in earlier in their settings.
    riderConsent: bool


class TripEvent(BaseModel):
    type: Literal["sos", "manual_unsafe"]
    ts: datetime | None = None  # device time; server time when missing
    data: dict = {}


class EventBatch(BaseModel):
    events: list[TripEvent] = Field(max_length=500)  # Firestore batch limit


class Marker(BaseModel):
    """A moment in the full recording an agent should check."""

    at: float = Field(ge=0)  # seconds from the start of the recording
    kind: Literal["warning", "high", "sos", "manual_unsafe"]
    label: Label | None = None
    score: float | None = Field(None, ge=0, le=1)
    text: str | None = Field(None, max_length=2000)


class Utterance(BaseModel):
    at: float = Field(ge=0)  # seconds from the start of the recording
    end: float | None = Field(None, ge=0)
    text: str = Field(max_length=2000)


class Recording(BaseModel):
    durationSec: float = Field(ge=0, le=6 * 3600)
    contentType: Literal["audio/mp4", "audio/ogg", "audio/wav"]
    markers: list[Marker] = Field(max_length=500)
    transcript: list[Utterance] = Field([], max_length=5000)  # the phone's speech-to-text for the whole ride


def participant_trip(trip_id: str, uid: str) -> dict:
    """The trip, if the caller is its rider or driver. 404 / 403 otherwise."""
    snap = db().document("trips", trip_id).get()
    if not snap.exists:
        raise HTTPException(404, "Trip not found")
    trip = snap.to_dict()
    if uid not in (trip["riderId"], trip["driverId"]):
        raise HTTPException(403, "Not your trip")
    return trip


@router.post("")
def start_trip(body: StartTrip, user: dict = Depends(current_user)) -> dict:
    trip_id = body.orderId or f"GR-{secrets.token_hex(4).upper()}"
    driver = db().document("users", DEMO_DRIVER).get().to_dict() or {}
    try:
        db().document("trips", trip_id).create({
            "riderId": user["uid"],
            "driverId": DEMO_DRIVER,
            "mode": body.mode,
            "status": "active",
            "consent": {"rider": body.riderConsent, "driver": driver.get("audioConsent", False)},
            "startedAt": SERVER_TIMESTAMP,
            "endedAt": None,
        })
    except AlreadyExists:
        raise HTTPException(409, "A trip for this order already exists")
    return {"tripId": trip_id}


@router.post("/{trip_id}/events")
def add_events(trip_id: str, body: EventBatch, user: dict = Depends(current_user)) -> dict:
    participant_trip(trip_id, user["uid"])
    batch = db().batch()
    events = db().collection("trips", trip_id, "events")
    for e in body.events:
        batch.set(events.document(), {**e.model_dump(), "ts": e.ts or SERVER_TIMESTAMP, "data": {**e.data, "by": user["uid"]}})
    batch.commit()
    return {"count": len(body.events)}


@router.post("/{trip_id}/end")
def end_trip(trip_id: str, user: dict = Depends(current_user)) -> dict:
    participant_trip(trip_id, user["uid"])
    db().document("trips", trip_id).update({"status": "ended", "endedAt": SERVER_TIMESTAMP})
    return {"status": "ended"}


@router.post("/{trip_id}/recording")
def start_recording_upload(trip_id: str, body: Recording, user: dict = Depends(current_user)) -> dict:
    """After the ride: the full audio plus the moments to check. Returns where to upload it."""
    trip = participant_trip(trip_id, user["uid"])
    if not (trip["consent"]["rider"] and trip["consent"]["driver"]):
        raise HTTPException(409, "No recording: rider and driver did not both consent")
    # Privacy: a full ride is only shared when the phone flagged it high or someone pressed SOS.
    if not any(m.kind in ("high", "sos") for m in body.markers):
        raise HTTPException(409, "Only rides with a high flag or an SOS send their recording")
    path = f"recordings/{trip_id}.{EXTENSIONS[body.contentType]}"
    db().document("trips", trip_id).update({"recording": {
        **body.model_dump(),
        "path": path,
        "status": "awaiting_upload",
        "uploadedBy": user["uid"],
        "createdAt": SERVER_TIMESTAMP,
    }})
    return {"uploadUrl": storage.signed_url(path, "PUT", body.contentType), "uploadMethod": storage.upload_method()}


@router.post("/{trip_id}/recording/done")
def finish_recording_upload(trip_id: str, background: BackgroundTasks, user: dict = Depends(current_user)) -> dict:
    trip = participant_trip(trip_id, user["uid"])
    if not trip.get("recording"):
        raise HTTPException(404, "No recording started for this trip")
    db().document("trips", trip_id).update({"recording.status": "uploaded", "recording.uploadedAt": SERVER_TIMESTAMP})
    background.add_task(review.review_recording, trip_id)  # summary + verified flag for the agent
    return {"status": "uploaded"}


@router.get("/{trip_id}/recording-url")
def recording_url(trip_id: str, agent: dict = Depends(require_role("agent"))) -> dict:
    snap = db().document("trips", trip_id).get()
    rec = snap.to_dict().get("recording") if snap.exists else None
    if not rec or rec["status"] != "uploaded":
        raise HTTPException(404, "No uploaded recording for this trip")
    url = storage.signed_url(rec["path"], "GET")
    db().collection("auditLogs").add(
        {"agentId": agent["uid"], "tripId": trip_id, "action": "view_recording", "ts": SERVER_TIMESTAMP}
    )
    return {"url": url}
