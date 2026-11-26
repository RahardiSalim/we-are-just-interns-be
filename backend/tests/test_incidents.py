from google.cloud.firestore_v1.base_query import FieldFilter

from tests.conftest import needs_emulator

pytestmark = needs_emulator

WINDOW = {"windowStart": "2026-11-26T12:00:00Z", "windowEnd": "2026-11-26T12:00:30Z"}
HARASSMENT = [
    {"start": 0, "end": 4, "text": "Mbak, tinggal sendiri ya?"},
    {"start": 4, "end": 9, "text": "Cantik banget sih, nanti mampir ke tempat saya. Telepon 0812 3456 7890 ya."},
]


def start_trip(client, login, mode="goride") -> str:
    login("rider1")
    return client.post("/trips", json={"orderId": "GR-2001", "mode": mode}).json()["tripId"]


def report(client, trip_id, trigger="sos", **extra) -> str:
    created = client.post("/incidents", json={"tripId": trip_id, "trigger": trigger, **WINDOW, **extra})
    assert created.status_code == 200, created.text
    incident_id = created.json()["incidentId"]
    assert client.post(f"/incidents/{incident_id}/finalize").status_code == 202
    return incident_id


def test_harassment_transcript_escalates_with_masked_summary(client, login, db):
    trip_id = start_trip(client, login)
    created = client.post("/incidents", json={"tripId": trip_id, "trigger": "sos", "deviceTranscript": HARASSMENT, **WINDOW}).json()
    assert created["uploadUrl"].startswith("https://signed.test/PUT/clips/")
    assert created["uploadMethod"] == "POST", "the emulator takes POST uploads"
    assert db.document("incidents", created["incidentId"]).get().to_dict()["status"] == "awaiting_upload"

    assert client.post(f"/incidents/{created['incidentId']}/finalize").status_code == 202

    inc = db.document("incidents", created["incidentId"]).get().to_dict()
    assert (inc["status"], inc["severity"], inc["label"], inc["source"]) == ("escalated", "high", "sexual_harassment", "device")
    assert [line["flagged"] for line in inc["transcript"]] == [True, True]
    assert "Cantik" in inc["summary"] and "3456" not in inc["summary"], "phone numbers are masked"
    assert (inc["deleteAt"] - inc["createdAt"]).days >= 30, "open cases are kept longer"


def test_sos_without_any_transcript_escalates(client, login, db):
    incident_id = report(client, start_trip(client, login), trigger="sos")
    inc = db.document("incidents", incident_id).get().to_dict()
    assert (inc["status"], inc["severity"], inc["label"]) == ("escalated", "high", None)


def test_unsafe_report_without_transcript_checks_in_on_both(client, login, db):
    incident_id = report(client, start_trip(client, login), trigger="manual_unsafe")

    assert db.document("incidents", incident_id).get().to_dict()["status"] == "checkin_pending"
    checkins = [c.to_dict() for c in db.collection("checkins").where(filter=FieldFilter("incidentId", "==", incident_id)).get()]
    assert sorted((c["userId"], c["status"]) for c in checkins) == [("driver1", "sent"), ("rider1", "sent")]
    assert sorted(uid for uid, _ in db.pushes) == ["driver1", "rider1"]


def test_device_label_is_trusted_over_the_keyword_filter(client, login, db):
    incident_id = report(
        client, start_trip(client, login), trigger="manual_unsafe",
        deviceTranscript=[{"start": 0, "end": 3, "text": "Pak, kok lewat sini?"}], deviceLabel="threat", deviceScore=0.88,
    )
    inc = db.document("incidents", incident_id).get().to_dict()
    assert (inc["label"], inc["score"], inc["status"]) == ("threat", 0.88, "escalated")


def test_no_upload_without_both_consents(client, login, db):
    login("rider1")
    client.post("/me/consent", json={"audioConsent": False})
    trip_id = client.post("/trips", json={"orderId": "GR-2001"}).json()["tripId"]
    created = client.post("/incidents", json={"tripId": trip_id, "trigger": "sos", **WINDOW}).json()
    assert created["uploadUrl"] is None
    assert db.document("incidents", created["incidentId"]).get().to_dict()["clipPath"] is None


def test_finalize_runs_once_and_only_for_the_reporter(client, login, db):
    trip_id = start_trip(client, login)
    incident_id = client.post("/incidents", json={"tripId": trip_id, "trigger": "sos", **WINDOW}).json()["incidentId"]
    login("driver1")
    assert client.post(f"/incidents/{incident_id}/finalize").status_code == 403
    login("rider1")
    assert client.post(f"/incidents/{incident_id}/finalize").status_code == 202
    assert client.post(f"/incidents/{incident_id}/finalize").status_code == 409


def test_strangers_cannot_report_on_a_trip(client, login, db):
    trip_id = start_trip(client, login)
    login("rider2")
    assert client.post("/incidents", json={"tripId": trip_id, "trigger": "sos", **WINDOW}).status_code == 403


def test_auto_report_just_escalates(client, login, db):
    trip_id = start_trip(client, login)
    incident_id = report(
        client, trip_id, trigger="auto", deviceLabel="sexual_harassment", deviceScore=0.93,
        deviceTranscript=[{"start": 0, "end": 4, "text": "Cantik banget, mampir ke tempat saya ya."}],
    )
    inc = db.document("incidents", incident_id).get().to_dict()
    assert (inc["status"], inc["severity"], inc["label"]) == ("escalated", "high", "sexual_harassment")
    assert inc["summary"]
    assert db.collection("checkins").get() == [], "the phones ask \"Are you OK?\" themselves"


def test_auto_report_needs_the_phone_label(client, login, db):
    trip_id = start_trip(client, login)
    assert client.post("/incidents", json={"tripId": trip_id, "trigger": "auto", **WINDOW}).status_code == 422
