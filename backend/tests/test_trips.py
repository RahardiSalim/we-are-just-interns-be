from tests.conftest import needs_emulator

pytestmark = needs_emulator


def test_rider_starts_logs_and_ends_a_trip_by_order_id(client, login, db):
    login("rider1")
    assert client.post("/trips", json={"orderId": "GR-1001", "mode": "goride"}).json() == {"tripId": "GR-1001"}

    trip = db.document("trips", "GR-1001").get().to_dict()
    assert (trip["status"], trip["riderId"], trip["driverId"]) == ("active", "rider1", "driver1")
    assert trip["consent"] == {"rider": True, "driver": True}

    login("driver1")  # the driver's app sends events too
    assert client.post("/trips/GR-1001/events", json={"events": [{"type": "sos"}]}).json() == {"count": 1}
    stored = [e.to_dict() for e in db.collection("trips/GR-1001/events").get()]
    assert [(e["type"], e["data"]["by"]) for e in stored] == [("sos", "driver1")]

    assert client.post("/trips/GR-1001/end").status_code == 200
    assert db.document("trips", "GR-1001").get().to_dict()["status"] == "ended"


def test_no_location_is_accepted_or_stored(client, login, db):
    login("rider1")
    client.post("/trips", json={"orderId": "GR-1002"})
    assert client.post("/trips/GR-1002/events", json={"events": [{"type": "gps"}]}).status_code == 422
    client.post("/trips/GR-1002/events", json={"events": [{"type": "sos", "lat": -6.2, "lng": 106.8}]})

    trip = db.document("trips", "GR-1002").get().to_dict()
    event = db.collection("trips/GR-1002/events").get()[0].to_dict()
    assert not {"plannedRoute", "lat", "lng"} & (trip.keys() | event.keys()), "GoJek holds location, not us"


def test_one_trip_per_order(client, login, db):
    login("rider1")
    assert client.post("/trips", json={"orderId": "GR-1003"}).status_code == 200
    assert client.post("/trips", json={"orderId": "GR-1003"}).status_code == 409
    assert client.post("/trips", json={"orderId": "bad/id"}).status_code == 422


def test_consent_comes_from_both_users(client, login, db):
    login("rider1")
    client.post("/me/consent", json={"audioConsent": False})
    trip_id = client.post("/trips", json={"orderId": "GR-1004"}).json()["tripId"]
    assert db.document("trips", trip_id).get().to_dict()["consent"] == {"rider": False, "driver": True}


def test_only_riders_start_trips_and_only_participants_touch_them(client, login, db):
    login("driver1")
    assert client.post("/trips", json={"orderId": "GR-1005"}).status_code == 403

    login("rider1")
    trip_id = client.post("/trips", json={"orderId": "GR-1005"}).json()["tripId"]
    login("rider2")
    assert client.post(f"/trips/{trip_id}/events", json={"events": []}).status_code == 403
    assert client.post(f"/trips/{trip_id}/end").status_code == 403
    assert client.post("/trips/nope/end").status_code == 404
