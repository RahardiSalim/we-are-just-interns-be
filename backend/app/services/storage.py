import os
from datetime import timedelta
from urllib.parse import quote

import google.auth
from google.auth.transport.requests import Request
from firebase_admin import storage

from app.core import config
from app.core.firebase import init


def upload_method() -> str:
    """Real signed URLs take PUT; the Storage emulator's upload API only takes POST."""
    return "POST" if config.EMULATOR else "PUT"


def signed_url(path: str, method: str) -> str:
    """10-minute V4 signed URL for a clip. PUT to upload (audio/wav), GET to play.

    Needs the Cloud Run service account with "Service Account Token Creator" on itself;
    signing goes through IAM, so no key file is involved.
    """
    if config.EMULATOR:
        # The Storage emulator's GCS API takes unsigned requests, so local runs need no Google credentials.
        host = os.getenv("FIREBASE_STORAGE_EMULATOR_HOST", "127.0.0.1:9199")
        bucket = config.FIREBASE_STORAGE_BUCKET
        if method == "PUT":
            return f"http://{host}/upload/storage/v1/b/{bucket}/o?uploadType=media&name={quote(path, safe='')}"
        return f"http://{host}/download/storage/v1/b/{bucket}/o/{quote(path, safe='')}?alt=media"

    creds, _ = google.auth.default()
    creds.refresh(Request())
    return storage.bucket(app=init()).blob(path).generate_signed_url(
        version="v4",
        expiration=timedelta(minutes=10),
        method=method,
        content_type="audio/wav" if method == "PUT" else None,
        service_account_email=creds.service_account_email,
        access_token=creds.token,
    )
