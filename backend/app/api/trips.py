from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from google.api_core.exceptions import AlreadyExists
from google.cloud.firestore import SERVER_TIMESTAMP
from pydantic import BaseModel, Field

from app.core.auth import current_user, require_role
from app.core.firebase import db

router = APIRouter(prefix="/trips", tags=["trips"])

DEMO_DRIVER = "driver1"  # shortcut: every demo trip gets the seeded driver; real matching is GoTo's job


class StartTrip(BaseModel):
    # GoJek's order ID is the trip ID. No location or route is ever sent: GoJek already has it.
    orderId: str = Field(pattern=r"^[A-Za-z0-9_-]{1,64}$")
    mode: Literal["goride", "gocar"] = "goride"


class TripEvent(BaseModel):
    type: Literal["sos", "manual_unsafe"]
    ts: datetime | None = None  # device time; server time when missing
    data: dict = {}


class EventBatch(BaseModel):
    events: list[TripEvent] = Field(max_length=500)  # Firestore batch limit


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
def start_trip(body: StartTrip, user: dict = Depends(require_role("rider"))) -> dict:
    users = {uid: (db().document("users", uid).get().to_dict() or {}) for uid in (user["uid"], DEMO_DRIVER)}
    try:
        db().document("trips", body.orderId).create({
            "riderId": user["uid"],
            "driverId": DEMO_DRIVER,
            "mode": body.mode,
            "status": "active",
            "consent": {
                "rider": users[user["uid"]].get("audioConsent", False),
                "driver": users[DEMO_DRIVER].get("audioConsent", False),
            },
            "startedAt": SERVER_TIMESTAMP,
            "endedAt": None,
        })
    except AlreadyExists:
        raise HTTPException(409, "A trip for this order already exists")
    return {"tripId": body.orderId}


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
