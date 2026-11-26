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


def put_recording(client, order, **extra):
    body = {"durationSec": 25.0, "contentType": "audio/aac", "markers": MARKERS, **extra}
    return client.put(f"/trips/{order}/recording", json=body)


def test_after_the_ride_every_piece_uploads_with_markers(client, login, db):
    login("rider1")
    client.post("/trips", json={"orderId": "GR-1004", "riderConsent": True})
    assert put_recording(client, "GR-1004").json() == {"status": "uploading"}
    piece = client.post("/trips/GR-1004/recording/pieces/1").json()
    assert piece["uploadUrl"] == "https://signed.test/PUT/recordings/GR-1004/rider/000001.aac"
    assert put_recording(client, "GR-1004", pieces=2, done=True).json() == {"status": "uploaded"}

    rec = db.document("trips", "GR-1004").get().to_dict()["recordings"]["rider"]
    assert (rec["status"], rec["pieces"], rec["live"]) == ("uploaded", 2, False)
    assert [m["kind"] for m in rec["markers"]] == ["warning", "high", "sos"]

    login("agent1")
    assert client.get("/trips/GR-1004/recording-urls").json() == {"rider": {"contentType": "audio/aac", "urls": [
        "https://signed.test/GET/recordings/GR-1004/rider/000000.aac",
        "https://signed.test/GET/recordings/GR-1004/rider/000001.aac",
    ]}}
    assert [a.get("action") for a in db.collection("auditLogs").get()] == ["view_recording"]


def test_pieces_need_the_details_first(client, login, db):
    login("rider1")
    client.post("/trips", json={"orderId": "GR-1007", "riderConsent": True})
    assert client.post("/trips/GR-1007/recording/pieces/0").status_code == 409


def test_live_marks_the_open_case_until_the_ride_ends(client, login, db):
    login("rider1")
    client.post("/trips", json={"orderId": "GR-1008", "riderConsent": True})
    created = client.post("/incidents", json={"tripId": "GR-1008", "trigger": "sos", "windowStart": "2026-11-26T12:00:00Z",
                                              "windowEnd": "2026-11-26T12:00:30Z"}).json()
    client.post(f"/incidents/{created['incidentId']}/finalize")
    assert put_recording(client, "GR-1008", pieces=1, live=True).json() == {"status": "live"}
    assert db.document("incidents", created["incidentId"]).get().get("live") is True
    put_recording(client, "GR-1008", pieces=3, done=True)
    assert db.document("incidents", created["incidentId"]).get().get("live") is False


def test_a_report_or_a_second_warning_shares_the_recording_but_one_warning_does_not(client, login, db):
    login("rider1")
    client.post("/trips", json={"orderId": "GR-1006", "riderConsent": True})
    warnings_only = {"markers": [MARKERS[0]]}
    assert put_recording(client, "GR-1006", **warnings_only).status_code == 409
    assert "recordings" not in db.document("trips", "GR-1006").get().to_dict()
    assert put_recording(client, "GR-1006", markers=[MARKERS[0], {"at": 12.0, "kind": "manual_unsafe"}]).status_code == 200
    assert put_recording(client, "GR-1006", markers=[MARKERS[0], {**MARKERS[0], "at": 30.0}]).status_code == 200


def test_no_recording_without_both_consents(client, login, db):
    login("rider1")
    client.post("/trips", json={"orderId": "GR-1005", "riderConsent": False})
    assert put_recording(client, "GR-1005").status_code == 409
    login("rider2")
    assert client.get("/trips/GR-1005/recording-urls").status_code == 403, "agents only"


def test_a_driver_phone_joins_the_ride_and_keeps_its_own_recording(client, login, db):
    login("rider1")
    client.post("/trips", json={"orderId": "GR-1009", "riderConsent": True})
    login("driver2")
    assert client.post("/me/consent", json={"audioConsent": True}).status_code == 200
    assert client.post("/trips", json={"role": "driver"}).json() == {"tripId": "GR-1009"}
    trip = db.document("trips", "GR-1009").get().to_dict()
    assert (trip["driverId"], trip["consent"]) == ("driver2", {"rider": True, "driver": True})

    put_recording(client, "GR-1009", pieces=1, done=True)
    login("rider1")
    put_recording(client, "GR-1009", pieces=2, done=True)
    recs = db.document("trips", "GR-1009").get().to_dict()["recordings"]
    assert (recs["driver"]["pieces"], recs["rider"]["pieces"]) == (1, 2)


def test_a_driver_with_no_ride_waiting_is_told(client, login, db):
    login("driver2")
    assert client.post("/trips", json={"role": "driver"}).status_code == 404
