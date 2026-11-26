import os
from functools import cache

import firebase_admin
from firebase_admin import credentials, firestore
from google.auth.credentials import AnonymousCredentials

from app.core import config


class _EmulatorCredential(credentials.Base):
    """The emulators accept any caller, so skip Google's credential lookup."""

    def get_credential(self):
        return AnonymousCredentials()


@cache
def init() -> firebase_admin.App:
    # On Cloud Run (or with local ADC) credential=None means the service account / ADC is used.
    cred = _EmulatorCredential() if os.getenv("FIRESTORE_EMULATOR_HOST") else None
    return firebase_admin.initialize_app(
        cred, options={"projectId": config.GCP_PROJECT, "storageBucket": config.FIREBASE_STORAGE_BUCKET}
    )


def db():
    return firestore.client(init())
