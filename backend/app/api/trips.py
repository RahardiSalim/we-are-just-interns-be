import json
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from google.cloud.firestore import SERVER_TIMESTAMP
from pydantic import BaseModel, Field

from app.core.auth import current_user, require_role
from app.core.firebase import db
from app.services.seed import FIXTURES

router = APIRouter(prefix="/trips", tags=["trips"])

DEMO_DRIVER = "driver1"  # shortcut: every demo trip gets the seeded driver; real matching is GoTo's job


class StartTrip(BaseModel):
    mode: Literal["goride", "gocar"] = "goride"


class TripEvent(BaseModel):
    type: Literal["gps", "sos", "manual_unsafe"]
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
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
    ref = db().collection("trips").document()
    ref.set({
        "riderId": user["uid"],
        "driverId": DEMO_DRIVER,
        "mode": body.mode,
        "status": "active",
        "plannedRoute": json.loads((FIXTURES / "demo-trip.json").read_text())["polyline"],
        "consent": {
            "rider": users[user["uid"]].get("audioConsent", False),
            "driver": users[DEMO_DRIVER].get("audioConsent", False),
        },
        "startedAt": SERVER_TIMESTAMP,
        "endedAt": None,
    })
    return {"tripId": ref.id}


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
