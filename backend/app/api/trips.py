import secrets
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Path
from google.api_core.exceptions import AlreadyExists
from google.cloud.firestore import SERVER_TIMESTAMP
from google.cloud.firestore_v1.base_query import FieldFilter
from pydantic import BaseModel, Field

from app.core.auth import current_user, require_role
from app.core.firebase import db
from app.services import review, storage

router = APIRouter(prefix="/trips", tags=["trips"])

DEMO_DRIVER = "driver1"  # shortcut: a rider's trip starts with the seeded driver until a driver phone joins it
# What makes a phone share its recording: a high flag, an SOS, or a report ("manual_unsafe").
SHARE_WHEN = ("high", "sos", "manual_unsafe")
WARNINGS_TO_SHARE = 2  # the second warning on a ride shares its recording (mobile/README.md "The ladder")
OPEN = ("awaiting_upload", "processing", "escalated", "under_review")
Label = Literal["normal", "uncomfortable", "sexual_harassment", "threat"]
EXTENSIONS = {"audio/aac": "aac", "audio/mp4": "m4a", "audio/ogg": "ogg", "audio/wav": "wav"}  # aac: ADTS, what the phone records


class StartTrip(BaseModel):
    # GoJek's order ID is the trip ID. No location or route is ever sent: GoJek already has it.
    orderId: str | None = Field(None, pattern=r"^[A-Za-z0-9_-]{1,64}$")  # generated when missing (demo)
    mode: Literal["goride", "gocar"] = "goride"
    # The rider answers the consent prompt when the ride starts; the driver opted in earlier in their settings.
    riderConsent: bool = False
    # A driver's phone joins the rider's trip instead of starting one.
    role: Literal["rider", "driver"] = "rider"


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
    """One phone's copy of the ride: what it heard and flagged, and how many audio pieces it has sent."""

    durationSec: float = Field(ge=0, le=6 * 3600)
    contentType: Literal["audio/aac", "audio/mp4", "audio/ogg", "audio/wav"]
    markers: list[Marker] = Field(max_length=500)
    transcript: list[Utterance] = Field([], max_length=5000)  # the phone's speech-to-text for the whole ride
    pieces: int = Field(0, ge=0, le=2000)  # audio pieces uploaded so far, numbered from 0
    live: bool = False  # emergency: the phone streams pieces and lines while the ride is on
    done: bool = False  # the ride ended and every piece is up


def role_of(trip: dict, uid: str) -> str:
    return "rider" if uid == trip["riderId"] else "driver"


def piece_path(trip_id: str, role: str, n: int, content_type: str) -> str:
    return f"recordings/{trip_id}/{role}/{n:06d}.{EXTENSIONS[content_type]}"


def mark_live(trip_id: str, live: bool) -> None:
    """Open cases of this ride show LIVE on the dashboard while a phone streams."""
    for snap in db().collection("incidents").where(filter=FieldFilter("tripId", "==", trip_id)).get():
        if snap.get("status") in OPEN:
            snap.reference.update({"live": live})


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
    if body.role == "driver":
        return join_as_driver(body, user["uid"])
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


def join_as_driver(body: StartTrip, uid: str) -> dict:
    """The driver's phone joins the rider's trip; the driver's consent is their Safe Ride setting.

    shortcut: without an order ID it joins the newest active trip still waiting for a driver, because the
    demo has no GoJek dispatch. In production the driver app passes GoJek's order ID.
    """
    trips = db().collection("trips")
    if body.orderId:
        snap = trips.document(body.orderId).get()
        candidates = [snap] if snap.exists else []
    else:
        candidates = trips.where(filter=FieldFilter("driverId", "==", DEMO_DRIVER)).where(
            filter=FieldFilter("status", "==", "active")).get()
    waiting = [c for c in candidates if c.get("status") == "active" and c.get("driverId") in (DEMO_DRIVER, uid)]
    if not waiting:
        raise HTTPException(404, "No ride is waiting for a driver")
    snap = max(waiting, key=lambda c: c.get("startedAt"))
    me = db().document("users", uid).get().to_dict() or {}
    snap.reference.update({"driverId": uid, "consent.driver": me.get("audioConsent", False)})
    return {"tripId": snap.id}


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


@router.put("/{trip_id}/recording")
def save_recording(trip_id: str, body: Recording, background: BackgroundTasks, user: dict = Depends(current_user)) -> dict:
    """A phone's recording details, sent before its pieces and again as they go up. Each phone has its own."""
    trip = participant_trip(trip_id, user["uid"])
    if not (trip["consent"]["rider"] and trip["consent"]["driver"]):
        raise HTTPException(409, "No recording: rider and driver did not both consent")
    # Privacy: a ride only leaves the phone after a high flag, an SOS, a report, or a second warning.
    warnings = sum(m.kind == "warning" for m in body.markers)
    if not any(m.kind in SHARE_WHEN for m in body.markers) and warnings < WARNINGS_TO_SHARE:
        raise HTTPException(409, "Only rides with a high flag, an SOS, a report or two warnings send their recording")
    role = role_of(trip, user["uid"])
    before = (trip.get("recordings") or {}).get(role) or {}
    status = "uploaded" if body.done else "live" if body.live else "uploading"
    db().document("trips", trip_id).update({f"recordings.{role}": {
        **body.model_dump(exclude={"live", "done"}),
        "live": body.live and not body.done,
        "status": status,
        "uploadedBy": user["uid"],
        "updatedAt": SERVER_TIMESTAMP,
        "review": before.get("review"),
    }})
    if body.live or before.get("live"):
        mark_live(trip_id, body.live and not body.done)
    if body.done and before.get("status") != "uploaded":
        background.add_task(review.review_recording, trip_id, role)  # summary + verified flag for the agent
    return {"status": status}


@router.post("/{trip_id}/recording/pieces/{n}")
def piece_upload_url(trip_id: str, n: int = Path(ge=0, le=1999), user: dict = Depends(current_user)) -> dict:
    """Where to upload audio piece n. Re-sending a piece overwrites it, so retries are safe."""
    trip = participant_trip(trip_id, user["uid"])
    role = role_of(trip, user["uid"])
    rec = (trip.get("recordings") or {}).get(role)
    if not rec:
        raise HTTPException(409, "Send the recording details first")
    path = piece_path(trip_id, role, n, rec["contentType"])
    return {"uploadUrl": storage.signed_url(path, "PUT", rec["contentType"]), "uploadMethod": storage.upload_method()}


@router.get("/{trip_id}/recording-urls")
def recording_urls(trip_id: str, agent: dict = Depends(require_role("agent"))) -> dict:
    """10-minute links to every uploaded piece, per phone. The dashboard joins them to play. Logged."""
    snap = db().document("trips", trip_id).get()
    recs = (snap.to_dict() or {}).get("recordings") if snap.exists else None
    out = {
        role: {"contentType": r["contentType"],
               "urls": [storage.signed_url(piece_path(trip_id, role, i, r["contentType"]), "GET") for i in range(r["pieces"])]}
        for role, r in (recs or {}).items() if r.get("pieces")
    }
    if not out:
        raise HTTPException(404, "No uploaded recording for this trip")
    db().collection("auditLogs").add(
        {"agentId": agent["uid"], "tripId": trip_id, "action": "view_recording", "ts": SERVER_TIMESTAMP}
    )
    return out
