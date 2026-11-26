from tests.conftest import needs_emulator

pytestmark = needs_emulator

MARKERS = [
    {"at": 9.0, "kind": "warning", "label": "uncomfortable", "score": 0.65, "text": "Udah punya pacar belum?"},
    {"at": 18.0, "kind": "high", "label": "sexual_harassment", "score": 0.8, "text": "Cantik banget sih"},
    {"at": 20.5, "kind": "sos"},
]


def test_a_ride_starts_with_the_riders_consent_and_the_drivers_setting(client, login, db):
    login("rider1")
    assert client.post("/trips", json={"orderId": "GR-1001", "riderConsent": True}).json() == {"tripId": "GR-1001"}

    trip = db.document("trips", "GR-1001").get().to_dict()
    assert (trip["status"], trip["riderId"], trip["driverId"], trip["mode"]) == ("active", "rider1", "driver1", "goride")
    # the driver opted in beforehand in their own settings (their Safe Ride badge)
    assert trip["consent"] == {"rider": True, "driver": True}

    login("driver1")  # the driver's app sends events too
    assert client.post("/trips/GR-1001/events", json={"events": [{"type": "sos"}]}).json() == {"count": 1}
    assert client.post("/trips/GR-1001/end").status_code == 200
    assert db.document("trips", "GR-1001").get().to_dict()["status"] == "ended"


def test_rider_can_decline_and_the_order_id_is_optional(client, login, db):
    login("rider2")
    trip_id = client.post("/trips", json={"riderConsent": False}).json()["tripId"]
    assert trip_id.startswith("GR-")
    assert db.document("trips", trip_id).get().to_dict()["consent"] == {"rider": False, "driver": True}


def test_no_location_is_accepted_or_stored(client, login, db):
    login("rider1")
    client.post("/trips", json={"orderId": "GR-1002", "riderConsent": True})
    assert client.post("/trips/GR-1002/events", json={"events": [{"type": "gps"}]}).status_code == 422
    client.post("/trips/GR-1002/events", json={"events": [{"type": "sos", "lat": -6.2, "lng": 106.8}]})

    trip = db.document("trips", "GR-1002").get().to_dict()
    event = db.collection("trips/GR-1002/events").get()[0].to_dict()
    assert not {"plannedRoute", "lat", "lng"} & (trip.keys() | event.keys()), "GoJek holds location, not us"


def test_one_trip_per_order_and_only_participants_touch_it(client, login, db):
    login("rider1")
    assert client.post("/trips", json={"orderId": "GR-1003", "riderConsent": True}).status_code == 200
    assert client.post("/trips", json={"orderId": "GR-1003", "riderConsent": True}).status_code == 409
    assert client.post("/trips", json={"orderId": "bad/id", "riderConsent": True}).status_code == 422
    login("rider2")
    assert client.post("/trips/GR-1003/events", json={"events": []}).status_code == 403
    assert client.post("/trips/GR-1003/end").status_code == 403
    assert client.post("/trips/nope/end").status_code == 404


def test_after_the_ride_the_full_recording_uploads_with_markers(client, login, db):
    login("rider1")
    client.post("/trips", json={"orderId": "GR-1004", "riderConsent": True})
    created = client.post("/trips/GR-1004/recording", json={"durationSec": 25.0, "contentType": "audio/mp4", "markers": MARKERS})
    assert created.status_code == 200, created.text
    assert created.json()["uploadUrl"] == "https://signed.test/PUT/recordings/GR-1004.m4a"

    rec = db.document("trips", "GR-1004").get().to_dict()["recording"]
    assert (rec["status"], rec["durationSec"]) == ("awaiting_upload", 25.0)
    assert [m["kind"] for m in rec["markers"]] == ["warning", "high", "sos"]

    assert client.post("/trips/GR-1004/recording/done").status_code == 200
    assert db.document("trips", "GR-1004").get().to_dict()["recording"]["status"] == "uploaded"

    login("agent1")
    assert client.get("/trips/GR-1004/recording-url").json() == {"url": "https://signed.test/GET/recordings/GR-1004.m4a"}
    assert [a.get("action") for a in db.collection("auditLogs").get()] == ["view_recording"]


def test_no_recording_without_both_consents(client, login, db):
    login("rider1")
    client.post("/trips", json={"orderId": "GR-1005", "riderConsent": False})
    body = {"durationSec": 5.0, "contentType": "audio/mp4", "markers": []}
    assert client.post("/trips/GR-1005/recording", json=body).status_code == 409
    login("rider2")
    assert client.get("/trips/GR-1005/recording-url").status_code == 403, "agents only"


def test_a_ride_with_only_warnings_keeps_its_recording_private(client, login, db):
    login("rider1")
    client.post("/trips", json={"orderId": "GR-1006", "riderConsent": True})
    warnings_only = {"durationSec": 25.0, "contentType": "audio/mp4", "markers": [MARKERS[0], {"at": 12.0, "kind": "manual_unsafe"}]}
    assert client.post("/trips/GR-1006/recording", json=warnings_only).status_code == 409
    assert "recording" not in db.document("trips", "GR-1006").get().to_dict()
