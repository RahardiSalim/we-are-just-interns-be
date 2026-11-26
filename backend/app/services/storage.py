import hashlib
import hmac
import os
from datetime import datetime, timedelta, timezone
from urllib.parse import quote

import google.auth
import httpx
from google.auth.transport.requests import Request
from firebase_admin import storage

from app.core import config
from app.core.firebase import init


def upload_method() -> str:
    """Real signed URLs take PUT; the Storage emulator's upload API only takes POST."""
    return "POST" if config.EMULATOR and not config.R2_BUCKET else "PUT"


def upload_bytes(path: str, data: bytes, content_type: str) -> None:
    """Server-side upload (seed data). Phones upload through signed URLs instead."""
    if config.R2_BUCKET:
        httpx.put(signed_url(path, "PUT"), content=data, headers={"Content-Type": content_type}).raise_for_status()
        return
    if config.EMULATOR:
        host = os.getenv("FIREBASE_STORAGE_EMULATOR_HOST", "127.0.0.1:9199")
        url = f"http://{host}/upload/storage/v1/b/{config.FIREBASE_STORAGE_BUCKET}/o?uploadType=media&name={quote(path, safe='')}"
        httpx.post(url, content=data, headers={"Content-Type": content_type}).raise_for_status()
        return
    storage.bucket(app=init()).blob(path).upload_from_string(data, content_type=content_type)


def signed_url(path: str, method: str, content_type: str = "audio/wav") -> str:
    """10-minute V4 signed URL for audio. PUT to upload (send the same Content-Type), GET to play.

    Needs the Cloud Run service account with "Service Account Token Creator" on itself;
    signing goes through IAM, so no key file is involved.
    """
    if config.R2_BUCKET:
        host = f"{config.R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
        return presign(method, host, f"/{config.R2_BUCKET}/{path}", config.R2_ACCESS_KEY_ID, config.R2_SECRET_ACCESS_KEY)
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
        content_type=content_type if method == "PUT" else None,
        service_account_email=creds.service_account_email,
        access_token=creds.token,
    )


def presign(method: str, host: str, path: str, key_id: str, secret: str,
            region: str = "auto", expires: int = 600, now: datetime | None = None) -> str:
    """S3 SigV4 query-string signature (R2 speaks S3). Signs only the host, so any Content-Type is accepted."""
    stamp = (now or datetime.now(timezone.utc)).strftime("%Y%m%dT%H%M%SZ")
    scope = f"{stamp[:8]}/{region}/s3/aws4_request"
    params = {
        "X-Amz-Algorithm": "AWS4-HMAC-SHA256",
        "X-Amz-Credential": f"{key_id}/{scope}",
        "X-Amz-Date": stamp,
        "X-Amz-Expires": str(expires),
        "X-Amz-SignedHeaders": "host",
    }
    query = "&".join(f"{k}={quote(v, safe='')}" for k, v in sorted(params.items()))
    canonical = f"{method}\n{quote(path)}\n{query}\nhost:{host}\n\nhost\nUNSIGNED-PAYLOAD"
    to_sign = f"AWS4-HMAC-SHA256\n{stamp}\n{scope}\n{hashlib.sha256(canonical.encode()).hexdigest()}"
    key = ("AWS4" + secret).encode()
    for part in (stamp[:8], region, "s3", "aws4_request"):
        key = hmac.new(key, part.encode(), hashlib.sha256).digest()
    signature = hmac.new(key, to_sign.encode(), hashlib.sha256).hexdigest()
    return f"https://{host}{quote(path)}?{query}&X-Amz-Signature={signature}"
