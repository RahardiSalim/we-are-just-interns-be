from app.services.mailer import address as real_address  # the db fixture fakes mailer.address
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


def test_a_phone_user_saves_the_email_the_safety_team_writes_to(client, login, db):
    login("rider2")
    r = client.post("/me/email", json={"email": "  Rina.Customer@Example.COM "})
    assert r.status_code == 200 and r.json() == {"email": "rina.customer@example.com"}
    assert db.document("users", "rider2").get().to_dict()["email"] == "rina.customer@example.com"
    assert client.post("/me/email", json={"email": "not-an-email"}).status_code == 422


def test_an_anonymous_phone_account_is_emailed_at_the_address_it_typed(db):
    db.document("users", "anon-phone-1").set({"role": "rider", "email": "typed@example.com"})
    assert real_address("anon-phone-1") == "typed@example.com", "no Auth account: users.email"
    assert real_address("anon-phone-2") is None, "no address anywhere: the email is skipped"
