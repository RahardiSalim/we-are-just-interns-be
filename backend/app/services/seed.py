"""Demo data: users and five cases covering every source, priority and status, each with a real recording
(RB-182735214's from the driver's phone). Never close these cases for tests: make a test trip.
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
    # Phone numbers are fake (0000 block), for the case page's call details.
    {"uid": "rider1", "role": "rider", "displayName": "Rina (rider)", "phone": "+62 812-0000-0101"},
    {"uid": "rider2", "role": "rider", "displayName": "Bayu (rider)", "phone": "+62 812-0000-0102"},
    {"uid": "driver1", "role": "driver", "displayName": "Dodi (driver)", "phone": "+62 813-0000-0201", "safeRideBadge": True},
    {"uid": "driver2", "role": "driver", "displayName": "Sari (driver)", "phone": "+62 813-0000-0202", "safeRideBadge": False},
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
            "phone": u.get("phone"),
            "fcmToken": None,
            # A driver's recording consent is their Safe Ride setting.
            "audioConsent": u.get("safeRideBadge", True),
            "safeRideBadge": u.get("safeRideBadge", False),
        })

    ride = json.loads((FIXTURES / "demo-ride.json").read_text())
    start = now - timedelta(minutes=12)
    flag_at = start + timedelta(seconds=22)  # the harassment line in demo-ride.wav
    trip = client.document("trips", "RB-182730459")  # trip ID = GoJek order ID
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
    batch.set(client.document("incidents", "K7QM2XRAp9LbT3vWc8Ne"), {
        "tripId": "RB-182730459",
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
        "summary": "Pemicu: deteksi otomatis di ponsel pada trip RB-182730459. Penilaian otomatis: sexual_harassment (80%).",
        "clipPath": None,
        "source": "device",
        "assignedAgent": None,
        "decision": None,
        "createdAt": flag_at,
        "deleteAt": now + timedelta(days=30),
    })

    # More cases so the queue, its filters and the Closed tab have something to show.
    sos = json.loads((FIXTURES / "demo-ride-sos.json").read_text())
    sos_start = now - timedelta(minutes=9)
    sos_at = next(m["at"] for m in sos["markers"] if m["kind"] == "sos")

    def trip(trip_id: str, rider: str, driver: str, start: datetime, seconds: float, recordings: dict | None = None) -> None:
        batch.set(client.document("trips", trip_id), {
            "riderId": rider, "driverId": driver, "mode": "goride", "status": "ended",
            "consent": {"rider": True, "driver": True},
            "startedAt": start, "endedAt": start + timedelta(seconds=seconds),
            **({"recordings": recordings} if recordings else {}),
        })

    def incident(incident_id: str, trip_id: str, created: datetime, lines: list[tuple[str, bool]], **fields) -> None:
        one = {"trigger": fields["trigger"], "by": fields["reportedBy"], "label": fields["label"], "score": fields["score"], "at": created}
        batch.set(client.document("incidents", incident_id), {
            "reports": [one], "live": False,
            "tripId": trip_id, "windowStart": created - timedelta(seconds=30), "windowEnd": created,
            "transcript": [{"start": i * 4.0, "end": i * 4.0 + 3.5, "text": text, "flagged": flagged}
                           for i, (text, flagged) in enumerate(lines)],
            "clipPath": None, "source": "device", "assignedAgent": None, "decision": None,
            "createdAt": created, "deleteAt": now + timedelta(days=30), **fields,
        })

    # RB-182731106: SOS with a full recording (driver leaves the route and threatens the rider).
    trip("RB-182731106", "rider2", "driver2", sos_start, sos["durationSec"], {"rider": {
        "contentType": sos["contentType"], "pieces": 1, "live": False, "durationSec": sos["durationSec"],
        "markers": sos["markers"], "transcript": sos["transcript"], "status": "uploaded", "uploadedBy": "rider2",
        "updatedAt": now - timedelta(minutes=1), "review": None,
    }})
    incident("B4NZ8HTYq2MdR6sJw1Kf", "RB-182731106", sos_start + timedelta(seconds=sos_at),
             [(line["text"], line["at"] >= 15) for line in sos["transcript"]],
             reportedBy="rider2", trigger="sos", status="escalated", severity="high", label="threat", score=0.88,
             summary="Penumpang menekan SOS setelah pengemudi keluar dari rute, menyuruhnya diam, dan mengancam jika melapor.")

    def recorded(fixture: dict, by: str, phone: str = "rider") -> dict:
        """One phone's recording, uploaded in one piece (a report or a high flag uploads at the end; an SOS streamed live)."""
        return {phone: {
            "contentType": fixture["contentType"], "pieces": 1, "live": False, "durationSec": fixture["durationSec"],
            "markers": fixture["markers"], "transcript": fixture["transcript"], "status": "uploaded", "uploadedBy": by,
            "updatedAt": now - timedelta(minutes=1), "review": None,
        }}

    def lines(fixture: dict) -> list[tuple[str, bool]]:
        flagged = {m["text"] for m in fixture["markers"]}
        return [(line["text"], line["text"] in flagged) for line in fixture["transcript"]]

    # RB-182733872: "I feel unsafe" (Report), already taken by an agent. A report uploads the ride when it ends.
    report = json.loads((FIXTURES / "demo-ride-report.json").read_text())
    trip("RB-182733872", "rider1", "driver2", now - timedelta(minutes=40), report["durationSec"], recorded(report, "rider1"))
    incident("P2LW5CVEx7GhN9tQa3Ub", "RB-182733872", now - timedelta(minutes=31), lines(report),
             reportedBy="rider1", trigger="manual_unsafe", status="under_review", severity="medium",
             label="uncomfortable", score=0.63, assignedAgent="agent2",
             summary="Penumpang melaporkan perjalanan setelah pengemudi bertanya soal rumah dan berniat mampir.")

    # RB-182735214: flagged by the driver's phone (the passenger threatens the driver); the driver's phone uploaded the ride.
    driver_ride = json.loads((FIXTURES / "demo-ride-driver.json").read_text())
    trip("RB-182735214", "rider2", "driver1", now - timedelta(minutes=6), driver_ride["durationSec"],
         recorded(driver_ride, "driver1", phone="driver"))
    incident("T9FR3MJDk4WsE8yLz6Hc", "RB-182735214", now - timedelta(minutes=3), lines(driver_ride),
             reportedBy="driver1", trigger="auto", status="escalated", severity="high", label="threat", score=0.91,
             summary="Pemicu: deteksi otomatis di ponsel pengemudi pada trip RB-182735214. Penilaian otomatis: threat (91%).")

    # RB-182728690: an SOS that an agent already decided (for the Closed tab).
    closed = json.loads((FIXTURES / "demo-ride-closed.json").read_text())
    trip("RB-182728690", "rider1", "driver1", now - timedelta(hours=3), closed["durationSec"], recorded(closed, "rider1"))
    incident("H6XK1QPSn5BvY2rCd7Ga", "RB-182728690", now - timedelta(hours=2, minutes=45), lines(closed),
             reportedBy="rider1", trigger="sos", status="closed", severity="high", label="sexual_harassment", score=0.82,
             assignedAgent="agent1",
             summary="Penumpang menekan SOS setelah pengemudi meminta nomor pribadi berulang kali.",
             decision={"customer": "contact", "driver": "warn", "customerNote": "Kami sudah menghubungi Anda lewat telepon.",
                       "driverNote": "", "agentId": "agent1", "ts": now - timedelta(hours=2)})

    batch.commit()
    storage.upload_bytes("recordings/RB-182730459/rider/000000.wav", (FIXTURES / "demo-ride.wav").read_bytes(), ride["contentType"])
    storage.upload_bytes("recordings/RB-182731106/rider/000000.wav", (FIXTURES / "demo-ride-sos.wav").read_bytes(), sos["contentType"])
    storage.upload_bytes("recordings/RB-182733872/rider/000000.wav", (FIXTURES / "demo-ride-report.wav").read_bytes(), report["contentType"])
    storage.upload_bytes("recordings/RB-182728690/rider/000000.wav", (FIXTURES / "demo-ride-closed.wav").read_bytes(), closed["contentType"])
    storage.upload_bytes("recordings/RB-182735214/driver/000000.wav", (FIXTURES / "demo-ride-driver.wav").read_bytes(), driver_ride["contentType"])
    for trip_id, phone in (("RB-182730459", "rider"), ("RB-182731106", "rider"), ("RB-182733872", "rider"), ("RB-182735214", "driver"), ("RB-182728690", "rider")):
        review_recording(trip_id, phone)
    return {"users": len(USERS), "trips": 5, "incidents": 5}


def reset_data() -> None:
    client = db()
    for name in COLLECTIONS:
        client.recursive_delete(client.collection(name))
