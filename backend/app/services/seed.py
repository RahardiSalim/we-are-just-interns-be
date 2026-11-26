"""Demo data: users docs, one trip with events, one escalated incident. Fixed ids so re-seeding overwrites."""

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

from app.core.firebase import db

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

COLLECTIONS = ["users", "trips", "incidents", "checkins", "auditLogs"]


def email(uid: str) -> str:
    return f"{uid}@gosafe.test"


def seed_data() -> dict:
    client = db()
    now = datetime.now(timezone.utc)
    route = json.loads((FIXTURES / "demo-trip.json").read_text())
    batch = client.batch()

    for u in USERS:
        batch.set(client.document("users", u["uid"]), {
            "role": u["role"],
            "displayName": u["displayName"],
            "fcmToken": None,
            "audioConsent": True,
            "safeRideBadge": u.get("safeRideBadge", False),
        })

    start = now - timedelta(minutes=12)
    trip = client.document("trips", "demo-trip-1")
    batch.set(trip, {
        "riderId": "rider1",
        "driverId": "driver1",
        "mode": "goride",
        "status": "ended",
        "plannedRoute": route["polyline"],
        "consent": {"rider": True, "driver": True},
        "startedAt": start,
        "endedAt": now - timedelta(minutes=2),
    })
    for i, (lat, lng) in enumerate(route["points"]):
        batch.set(trip.collection("events").document(f"gps-{i}"), {
            "type": "gps", "ts": start + timedelta(minutes=2 * i), "lat": lat, "lng": lng, "data": {},
        })
    sos_lat, sos_lng = route["points"][3]
    sos_ts = start + timedelta(minutes=6)
    batch.set(trip.collection("events").document("sos-1"), {
        "type": "sos", "ts": sos_ts, "lat": sos_lat, "lng": sos_lng, "data": {"by": "rider1"},
    })

    batch.set(client.document("incidents", "demo-incident-1"), {
        "tripId": "demo-trip-1",
        "reportedBy": "rider1",
        "trigger": "sos",
        "status": "escalated",
        "severity": "high",
        "label": "sexual_harassment",
        "score": 0.91,
        "transcript": [
            {"start": 0.0, "end": 4.2, "text": "Mbak, rumahnya di mana? Tinggal sendiri ya?", "flagged": False},
            {"start": 4.2, "end": 9.8, "text": "Cantik banget sih, mau nggak saya anterin tiap hari?", "flagged": True},
            {"start": 9.8, "end": 13.5, "text": "Pak, tolong fokus nyetir aja.", "flagged": False},
            {"start": 13.5, "end": 19.0, "text": "Ayo dong, nanti mampir dulu ke tempat saya.", "flagged": True},
        ],
        "summary": "Penumpang menekan SOS setelah pengemudi berulang kali menanyakan alamat dan mengajak mampir. "
                   "Penumpang meminta pengemudi fokus berkendara. (Contoh ringkasan untuk demo.)",
        "clipPath": None,  # shortcut: no sample clip yet, add one to contracts/fixtures in Phase 2
        "source": "cloud",
        "assignedAgent": None,
        "decision": None,
        "createdAt": sos_ts,
        "deleteAt": now + timedelta(days=7),
    })

    batch.commit()
    return {"users": len(USERS), "trips": 1, "incidents": 1}


def reset_data() -> None:
    client = db()
    for name in COLLECTIONS:
        client.recursive_delete(client.collection(name))
