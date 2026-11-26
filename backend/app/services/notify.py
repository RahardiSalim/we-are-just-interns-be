import logging

from firebase_admin import messaging

from app.core import config
from app.core.firebase import db, init

log = logging.getLogger(__name__)


def push(uid: str, data: dict) -> None:
    """Data push to the user's phone. Never raises: a missed push is covered by the check-in timeout."""
    token = (db().document("users", uid).get().to_dict() or {}).get("fcmToken")
    if not token or config.EMULATOR:  # the emulators have no FCM
        log.info("push skipped uid=%s data=%s", uid, data)
        return
    try:
        messaging.send(messaging.Message(token=token, data={k: str(v) for k, v in data.items()}), app=init())
    except Exception:
        log.exception("push failed uid=%s", uid)
