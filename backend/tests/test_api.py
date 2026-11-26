import pytest
from fastapi.testclient import TestClient

from app.core import auth, config
from app.main import app
from app.services import seed


@pytest.fixture
def client():
    yield TestClient(app)
    app.dependency_overrides.clear()


def login_as(role: str):
    # Firebase token verification is the external boundary, so tests replace it.
    app.dependency_overrides[auth.current_user] = lambda: {"uid": f"{role}1", "role": role}


def test_health(client):
    assert client.get("/health").json() == {"status": "ok"}


def test_dev_routes_hidden_when_disabled(client, monkeypatch):
    monkeypatch.setattr(config, "ENABLE_DEV_ROUTES", False)
    login_as("agent")
    assert client.post("/dev/seed").status_code == 404


def test_dev_routes_need_a_token(client, monkeypatch):
    monkeypatch.setattr(config, "ENABLE_DEV_ROUTES", True)
    assert client.post("/dev/seed").status_code == 401


def test_dev_routes_reject_bad_token(client, monkeypatch):
    monkeypatch.setattr(config, "ENABLE_DEV_ROUTES", True)
    monkeypatch.setattr(auth.auth, "verify_id_token", lambda *a, **k: (_ for _ in ()).throw(ValueError()))
    assert client.post("/dev/seed", headers={"Authorization": "Bearer junk"}).status_code == 401


def test_dev_routes_are_agent_only(client, monkeypatch):
    monkeypatch.setattr(config, "ENABLE_DEV_ROUTES", True)
    login_as("rider")
    assert client.post("/dev/seed").status_code == 403


def test_agent_can_seed(client, monkeypatch):
    monkeypatch.setattr(config, "ENABLE_DEV_ROUTES", True)
    monkeypatch.setattr(seed, "seed_data", lambda: {"users": 6, "trips": 1, "incidents": 1})
    login_as("agent")
    assert client.post("/dev/seed").json() == {"users": 6, "trips": 1, "incidents": 1}
