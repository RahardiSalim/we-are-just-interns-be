from functools import cache

import firebase_admin
from firebase_admin import firestore

from app.core import config


@cache
def init() -> firebase_admin.App:
    # No credential argument: Cloud Run's service account (or local ADC / emulators) is used.
    return firebase_admin.initialize_app(
        options={"projectId": config.GCP_PROJECT, "storageBucket": config.FIREBASE_STORAGE_BUCKET}
    )


def db():
    return firestore.client(init())
