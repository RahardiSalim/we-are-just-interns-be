from tests.conftest import needs_emulator

pytestmark = needs_emulator


def test_user_saves_consent_and_push_token(client, login, db):
    login("rider2")
    assert client.post("/me/consent", json={"audioConsent": False}).status_code == 200
    assert client.post("/me/fcm-token", json={"token": "tok-123"}).status_code == 200

    user = db.document("users", "rider2").get().to_dict()
    assert user["audioConsent"] is False
    assert user["fcmToken"] == "tok-123"
    assert user["role"] == "rider", "other fields stay"
