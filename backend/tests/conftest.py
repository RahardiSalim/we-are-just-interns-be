import os

import httpx
import pytest
from fastapi.testclient import TestClient

from app.core import auth, config
from app.main import app
from app.services import notify, seed, storage

EMULATOR = os.getenv("FIRESTORE_EMULATOR_HOST")
needs_emulator = pytest.mark.skipif(not EMULATOR, reason="start the Firebase emulators and set FIRESTORE_EMULATOR_HOST")


@pytest.fixture
def client():
    yield TestClient(app)
    app.dependency_overrides.clear()


@pytest.fixture
def login(client):
    """login("rider1") makes every request act as that seeded user."""

    def as_user(uid: str):
        role = next(u["role"] for u in seed.USERS if u["uid"] == uid)
        app.dependency_overrides[auth.current_user] = lambda: {"uid": uid, "role": role}

    return as_user


@pytest.fixture
def db(monkeypatch):
    """Empty emulator Firestore with the seeded users, and the outside services faked."""
    httpx.delete(f"http://{EMULATOR}/emulator/v1/projects/{config.GCP_PROJECT}/databases/(default)/documents")
    seed.seed_data()
    pushes: list[tuple[str, dict]] = []
    monkeypatch.setattr(notify, "push", lambda uid, data: pushes.append((uid, data)))
    monkeypatch.setattr(storage, "signed_url", lambda path, method, *_: f"https://signed.test/{method}/{path}")
    from app.core.firebase import db as client

    c = client()
    c.pushes = pushes
    return c
