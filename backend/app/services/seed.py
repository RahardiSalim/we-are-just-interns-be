"""Demo data: users docs, one trip with events, one escalated incident. Fixed ids so re-seeding overwrites."""

from datetime import datetime, timedelta, timezone

from app.core.firebase import db

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
    trip = client.document("trips", "GR-DEMO-1")  # trip ID = GoJek order ID
    batch.set(trip, {
        "riderId": "rider1",
        "driverId": "driver1",
        "mode": "goride",
        "status": "ended",
        "consent": {"rider": True, "driver": True},
        "startedAt": start,
        "endedAt": now - timedelta(minutes=2),
    })
    sos_ts = start + timedelta(minutes=6)
    batch.set(trip.collection("events").document("sos-1"), {"type": "sos", "ts": sos_ts, "data": {"by": "rider1"}})

    batch.set(client.document("incidents", "demo-incident-1"), {
        "tripId": "GR-DEMO-1",
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
        "clipPath": None,  # shortcut: no sample clip yet; add a recorded one when the team has it
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
