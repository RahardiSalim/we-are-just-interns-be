import time

from google.cloud.firestore_v1.base_query import FieldFilter

from app.core import config
from tests.conftest import needs_emulator
from tests.test_incidents import report, start_trip

pytestmark = needs_emulator


def checkins(db, incident_id) -> dict[str, str]:
    """userId -> checkin id"""
    q = db.collection("checkins").where(filter=FieldFilter("incidentId", "==", incident_id))
    return {c.get("userId"): c.id for c in q.get()}


def status(db, incident_id) -> str:
    return db.document("incidents", incident_id).get().get("status")


def test_gocar_needs_both_to_say_ok(client, login, db):
    incident_id = report(client, start_trip(client, login, mode="gocar"), trigger="manual_unsafe")
    ids = checkins(db, incident_id)

    assert client.post(f"/checkins/{ids['rider1']}/reply", json={"answer": "ok"}).status_code == 200
    assert status(db, incident_id) == "checkin_pending", "still waiting for the driver"
    login("driver1")
    client.post(f"/checkins/{ids['driver1']}/reply", json={"answer": "ok"})
    assert status(db, incident_id) == "resolved_ok"


def test_need_help_escalates_at_once(client, login, db):
    incident_id = report(client, start_trip(client, login), trigger="manual_unsafe")
    client.post(f"/checkins/{checkins(db, incident_id)['rider1']}/reply", json={"answer": "need_help"})
    inc = db.document("incidents", incident_id).get().to_dict()
    assert inc["status"] == "escalated" and inc["summary"]


def test_no_reply_escalates_after_the_timeout(client, login, db, monkeypatch):
    monkeypatch.setattr(config, "CHECKIN_TIMEOUT_SEC", 0.3)
    incident_id = report(client, start_trip(client, login), trigger="manual_unsafe")
    login("driver1")
    client.post(f"/checkins/{checkins(db, incident_id)['driver1']}/reply", json={"answer": "ok"})

    for _ in range(40):
        if status(db, incident_id) == "escalated":
            break
        time.sleep(0.1)
    assert status(db, incident_id) == "escalated"
    by_user = {c.get("userId"): c.get("status") for c in db.collection("checkins").get()}
    assert by_user == {"rider1": "no_reply", "driver1": "ok"}


def test_only_the_owner_answers_once(client, login, db):
    incident_id = report(client, start_trip(client, login), trigger="manual_unsafe")
    ids = checkins(db, incident_id)
    assert client.post(f"/checkins/{ids['driver1']}/reply", json={"answer": "ok"}).status_code == 403
    assert client.post(f"/checkins/{ids['rider1']}/reply", json={"answer": "ok"}).status_code == 200
    assert client.post(f"/checkins/{ids['rider1']}/reply", json={"answer": "need_help"}).status_code == 409


def test_goride_rider_ok_is_enough_because_the_driver_is_riding(client, login, db):
    incident_id = report(client, start_trip(client, login, mode="goride"), trigger="manual_unsafe")
    client.post(f"/checkins/{checkins(db, incident_id)['rider1']}/reply", json={"answer": "ok"})
    assert status(db, incident_id) == "resolved_ok"


def test_goride_driver_silence_alone_does_not_escalate(client, login, db, monkeypatch):
    monkeypatch.setattr(config, "CHECKIN_TIMEOUT_SEC", 0.3)
    incident_id = report(client, start_trip(client, login, mode="goride"), trigger="manual_unsafe")
    # the driver never answers; the rider answers late, after the timer, so the timer decides
    time.sleep(0.8)
    assert status(db, incident_id) == "escalated", "the rider's silence still escalates"


def test_driver_need_help_still_counts_on_goride(client, login, db):
    incident_id = report(client, start_trip(client, login, mode="goride"), trigger="manual_unsafe")
    login("driver1")
    client.post(f"/checkins/{checkins(db, incident_id)['driver1']}/reply", json={"answer": "need_help"})
    assert status(db, incident_id) == "escalated"
