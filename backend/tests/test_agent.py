from app.services import email_content
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

    decided = client.post(f"/incidents/{incident_id}/decision", json={"customer": "none", "driver": "warn", "driverNote": "Teguran pertama"})
    assert decided.status_code == 200
    inc = db.document("incidents", incident_id).get().to_dict()
    assert inc["status"] == "closed"
    assert (inc["decision"]["customer"], inc["decision"]["driver"], inc["decision"]["agentId"]) == ("none", "warn", "agent1")
    assert audit(db) == [("decide", "agent1"), ("view_clip", "agent1")]
    trip = db.document("trips", inc["tripId"]).get().to_dict()
    told = {f"{trip[k]}@gosafe.test" for k in ("riderId", "driverId") if trip.get(k)}
    assert {to for to, *_ in db.emails} == told  # a warning tells the rider and the driver
    ticket = email_content.ticket_number(incident_id)
    assert all(inc["tripId"] in subject or ticket in subject for _, subject, _ in db.emails)

    assert client.post(f"/incidents/{incident_id}/decision", json={"customer": "none", "driver": "none"}).status_code == 409


def test_a_report_goes_straight_to_an_agent(client, login, db):
    incident_id = report(client, start_trip(client, login), trigger="manual_unsafe")
    login("agent1")
    assert client.post(f"/incidents/{incident_id}/open").status_code == 200


def test_no_clip_means_404_and_no_audit_entry(client, login, db):
    login("rider1")
    incident_id = report(client, client.post("/trips", json={"orderId": "GR-2001", "riderConsent": False}).json()["tripId"], trigger="sos")
    login("agent1")
    assert client.get(f"/incidents/{incident_id}/clip-url").status_code == 404
    assert audit(db) == []


def test_riders_and_drivers_cannot_use_agent_endpoints(client, login, db):
    incident_id = report(client, start_trip(client, login), trigger="sos")
    for path in ("open", "decision"):
        assert client.post(f"/incidents/{incident_id}/{path}", json={"customer": "none", "driver": "none"}).status_code == 403
    assert client.get(f"/incidents/{incident_id}/clip-url").status_code == 403


def test_contacting_the_driver_emails_them_and_tells_the_rider(client, login, db):
    incident_id = report(client, start_trip(client, login), trigger="manual_unsafe", deviceLabel="threat", deviceScore=0.9)
    db.emails.clear()
    login("agent1")
    assert client.post(f"/incidents/{incident_id}/decision", json={"customer": "none", "driver": "contact"}).status_code == 200
    subjects = {to: subject for to, subject, _ in db.emails}
    assert subjects["driver1@gosafe.test"].startswith("Our safety team would like to talk to you")
    assert subjects["rider1@gosafe.test"].startswith("Update on your report")


def test_one_side_is_enough_and_nothing_chosen_dismisses(client, login, db):
    """Decisions are OR, not AND: only the driver, only the customer, or neither (dismiss)."""
    for body, told in (
        ({"driver": "warn"}, {"rider1@gosafe.test", "driver1@gosafe.test"}),
        ({"customer": "contact"}, {"rider1@gosafe.test"}),
        ({}, {"rider1@gosafe.test"}),  # dismiss: the customer hears "no further action", the driver nothing
    ):
        incident_id = report(client, start_trip(client, login), trigger="sos")
        db.emails.clear()
        login("agent1")
        assert client.post(f"/incidents/{incident_id}/decision", json=body).status_code == 200
        decision = db.document("incidents", incident_id).get().to_dict()["decision"]
        assert (decision["customer"], decision["driver"]) == (body.get("customer", "none"), body.get("driver", "none"))
        assert {to for to, *_ in db.emails} == told, body
        db.document("trips", "GR-2001").delete()  # the next round starts the same order again

