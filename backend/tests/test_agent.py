from tests.conftest import needs_emulator
from tests.test_incidents import report, start_trip

pytestmark = needs_emulator


def audit(db) -> list[tuple[str, str]]:
    return sorted((a.get("action"), a.get("agentId")) for a in db.collection("auditLogs").get())


def test_agent_opens_listens_and_decides(client, login, db):
    incident_id = report(client, start_trip(client, login), trigger="sos")

    login("agent1")
    assert client.post(f"/incidents/{incident_id}/open").status_code == 200
    inc = db.document("incidents", incident_id).get().to_dict()
    assert (inc["status"], inc["assignedAgent"]) == ("under_review", "agent1")

    assert client.get(f"/incidents/{incident_id}/clip-url").json() == {"url": f"https://signed.test/GET/clips/{incident_id}.wav"}

    decided = client.post(f"/incidents/{incident_id}/decision", json={"action": "warn_driver", "note": "Teguran pertama"})
    assert decided.status_code == 200
    inc = db.document("incidents", incident_id).get().to_dict()
    assert inc["status"] == "closed"
    assert (inc["decision"]["action"], inc["decision"]["agentId"]) == ("warn_driver", "agent1")
    assert audit(db) == [("decide", "agent1"), ("view_clip", "agent1")]

    assert client.post(f"/incidents/{incident_id}/decision", json={"action": "dismiss"}).status_code == 409


def test_cases_still_in_check_in_cannot_be_opened(client, login, db):
    incident_id = report(client, start_trip(client, login), trigger="manual_unsafe")
    login("agent1")
    assert client.post(f"/incidents/{incident_id}/open").status_code == 409


def test_no_clip_means_404_and_no_audit_entry(client, login, db):
    login("rider1")
    incident_id = report(client, client.post("/trips", json={"orderId": "GR-2001", "riderConsent": False}).json()["tripId"], trigger="sos")
    login("agent1")
    assert client.get(f"/incidents/{incident_id}/clip-url").status_code == 404
    assert audit(db) == []


def test_riders_and_drivers_cannot_use_agent_endpoints(client, login, db):
    incident_id = report(client, start_trip(client, login), trigger="sos")
    for path in ("open", "decision"):
        assert client.post(f"/incidents/{incident_id}/{path}", json={"action": "dismiss"}).status_code == 403
    assert client.get(f"/incidents/{incident_id}/clip-url").status_code == 403
