from tests.conftest import needs_emulator

pytestmark = needs_emulator


def test_rider_starts_logs_and_ends_a_trip(client, login, db):
    login("rider1")
    trip_id = client.post("/trips", json={"mode": "goride"}).json()["tripId"]

    trip = db.document("trips", trip_id).get().to_dict()
    assert (trip["status"], trip["riderId"], trip["driverId"]) == ("active", "rider1", "driver1")
    assert trip["consent"] == {"rider": True, "driver": True}
    assert trip["plannedRoute"]

    login("driver1")  # the driver's app sends events too
    events = [{"type": "gps", "lat": -6.24, "lng": 106.80}, {"type": "sos", "lat": -6.23, "lng": 106.79}]
    assert client.post(f"/trips/{trip_id}/events", json={"events": events}).json() == {"count": 2}
    stored = [e.to_dict()["type"] for e in db.collection(f"trips/{trip_id}/events").get()]
    assert sorted(stored) == ["gps", "sos"]

    assert client.post(f"/trips/{trip_id}/end").status_code == 200
    assert db.document("trips", trip_id).get().to_dict()["status"] == "ended"


def test_consent_comes_from_both_users(client, login, db):
    login("rider1")
    client.post("/me/consent", json={"audioConsent": False})
    trip_id = client.post("/trips", json={}).json()["tripId"]
    assert db.document("trips", trip_id).get().to_dict()["consent"] == {"rider": False, "driver": True}


def test_only_riders_start_trips_and_only_participants_touch_them(client, login, db):
    login("driver1")
    assert client.post("/trips", json={}).status_code == 403

    login("rider1")
    trip_id = client.post("/trips", json={}).json()["tripId"]
    login("rider2")
    assert client.post(f"/trips/{trip_id}/events", json={"events": []}).status_code == 403
    assert client.post(f"/trips/{trip_id}/end").status_code == 403
    assert client.post("/trips/nope/end").status_code == 404
