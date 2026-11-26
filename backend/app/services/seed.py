"""Demo data: users, one flagged ride with its real recording, and its escalated incident.
Fixed ids so re-seeding overwrites."""

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

from app.core.firebase import db
from app.services import storage
from app.services.review import review_recording

# Local runs read contracts/fixtures; the deploy workflow copies it to backend/fixtures for the image.
_here = Path(__file__).resolve().parents[2]
FIXTURES = _here / "fixtures" if (_here / "fixtures").exists() else _here.parent / "contracts" / "fixtures"

USERS = [
    {"uid": "rider1", "role": "rider", "displayName": "Rina (rider)"},
    {"uid": "rider2", "role": "rider", "displayName": "Bayu (rider)"},
    {"uid": "driver1", "role": "driver", "displayName": "Dodi (driver)", "safeRideBadge": True},
    {"uid": "driver2", "role": "driver", "displayName": "Sari (driver)", "safeRideBadge": False},
    {"uid": "agent1", "role": "agent", "displayName": "Agent Putri"},
    {"uid": "agent2", "role": "agent", "displayName": "Agent Arif"},
]

COLLECTIONS = ["users", "trips", "incidents", "auditLogs"]


def email(uid: str) -> str:
    return f"{uid}@gosafe.test"


def seed_data() -> dict:
    client = db()
    now = datetime.now(timezone.utc)
    batch = client.batch()

    for u in USERS:
        batch.set(client.document("users", u["uid"]), {
            "role": u["role"],
            "displayName": u["displayName"],
            "fcmToken": None,
            # A driver's recording consent is their Safe Ride setting.
            "audioConsent": u.get("safeRideBadge", True),
            "safeRideBadge": u.get("safeRideBadge", False),
        })

    ride = json.loads((FIXTURES / "demo-ride.json").read_text())
    start = now - timedelta(minutes=12)
    flag_at = start + timedelta(seconds=22)  # the harassment line in demo-ride.m4a
    trip = client.document("trips", "GR-DEMO-1")  # trip ID = GoJek order ID
    batch.set(trip, {
        "riderId": "rider1",
        "driverId": "driver1",
        "mode": "goride",
        "status": "ended",
        "consent": {"rider": True, "driver": True},
        "startedAt": start,
        "endedAt": start + timedelta(seconds=ride["durationSec"]),
        "recordings": {"rider": {
            "contentType": ride["contentType"],
            "pieces": 1,
            "live": False,
            "durationSec": ride["durationSec"],
            "markers": ride["markers"],
            "transcript": ride["transcript"],
            "status": "uploaded",
            "uploadedBy": "rider1",
            "updatedAt": now - timedelta(minutes=2),
            "review": None,
        }},
    })

    window = [line for line in ride["transcript"] if line["at"] <= 22.0]
    t0 = window[0]["at"]
    batch.set(client.document("incidents", "demo-incident-1"), {
        "tripId": "GR-DEMO-1",
        "reportedBy": "rider1",
        "trigger": "auto",
        "windowStart": start + timedelta(seconds=t0),
        "windowEnd": flag_at,
        "status": "escalated",
        "severity": "high",
        "label": "sexual_harassment",
        "score": 0.8,
        "transcript": [
            {"start": round(line["at"] - t0, 1), "end": round(line["end"] - t0, 1), "text": line["text"],
             "flagged": line["at"] in (9.8, 22.0, 18.2)}
            for line in window
        ],
        "summary": "Pemicu: deteksi otomatis di ponsel pada trip GR-DEMO-1. Penilaian otomatis: sexual_harassment (80%).",
        "clipPath": None,
        "source": "device",
        "assignedAgent": None,
        "decision": None,
        "createdAt": flag_at,
        "deleteAt": now + timedelta(days=30),
    })

    batch.commit()
    storage.upload_bytes("recordings/GR-DEMO-1/rider/000000.m4a", (FIXTURES / "demo-ride.m4a").read_bytes(), ride["contentType"])
    review_recording("GR-DEMO-1", "rider")
    return {"users": len(USERS), "trips": 1, "incidents": 1}


def reset_data() -> None:
    client = db()
    for name in COLLECTIONS:
        client.recursive_delete(client.collection(name))
