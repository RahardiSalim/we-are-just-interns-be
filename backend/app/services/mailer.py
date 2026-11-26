"""Emails to the rider and driver after an agent decides a case. Plain SMTP from the standard library.
What the emails say and how they look: services/email_content.py."""

import logging
import re
import smtplib
from datetime import datetime
from email.message import EmailMessage
from pathlib import Path
from zoneinfo import ZoneInfo

from firebase_admin import auth

from app.core import config
from app.core.firebase import db, init
from app.services import email_content

log = logging.getLogger(__name__)
WIB = ZoneInfo("Asia/Jakarta")
LOGO = Path(__file__).parents[1] / "assets" / "gosafe-mark.png"


def send(to: str, subject: str, text: str, html: str | None = None) -> None:
    """Sends one email (HTML with a plain-text copy). Never raises: a failed email must not undo the agent's decision."""
    if not config.SMTP_HOST:
        log.info("email skipped (no SMTP_HOST) to=%s subject=%s", to, subject)
        return
    msg = EmailMessage()
    msg["From"], msg["To"], msg["Subject"] = config.EMAIL_FROM, to, subject
    msg.set_content(text)
    if html:
        msg.add_alternative(html, subtype="html")
        if f"cid:{email_content.LOGO_CID}" in html:  # inline, so it shows without loading remote images
            msg.get_payload()[1].add_related(LOGO.read_bytes(), "image", "png", cid=f"<{email_content.LOGO_CID}>")
    try:
        with smtplib.SMTP(config.SMTP_HOST, config.SMTP_PORT, timeout=10) as smtp:
            smtp.starttls()
            if config.SMTP_USER:
                smtp.login(config.SMTP_USER, config.SMTP_PASSWORD)
            smtp.send_message(msg)
    except Exception:
        log.exception("email failed to=%s subject=%s", to, subject)


def address(uid: str) -> str | None:
    """The account email from Firebase Auth, so no extra field is stored in Firestore."""
    try:
        return auth.get_user(uid, app=init()).email
    except Exception:
        log.exception("no email for uid=%s", uid)
        return None


def first_name(uid: str) -> str:
    name = (db().document("users", uid).get().to_dict() or {}).get("displayName") or "there"
    return re.sub(r"\s*\(.*\)$", "", name).split(" ")[0]  # "Sari (driver)" -> "Sari"


def wib(ts: datetime | None) -> str:
    return f"{ts.astimezone(WIB):%-d %b %Y, %H.%M} WIB" if ts else "Not recorded"


def _send_for_incident(incident_id: str, emails: tuple[email_content.Email, ...]) -> None:
    """Sends each email to the person it's for (rider, driver or the reporter), filled in from the incident and trip."""
    inc = db().document("incidents", incident_id).get().to_dict() or {}
    order = inc.get("tripId", "-")
    trip = db().document("trips", order).get().to_dict() or {}
    for e in emails:
        uid = inc.get("reportedBy") if e.to == "reporter" else trip.get(f"{e.to}Id")
        to = uid and address(uid)
        if not to:
            continue
        args = (first_name(uid), order, wib(trip.get("startedAt")), incident_id)
        send(to, email_content.subject(e, order, incident_id), email_content.text(e, *args), email_content.html(e, *args))


def sos_received(incident_id: str) -> None:
    """Tells whoever pressed SOS that their ticket was created and is being processed."""
    _send_for_incident(incident_id, (email_content.SOS_RECEIVED,))


def decision(incident_id: str, action: str) -> None:
    """Tells the rider (and the driver when they're warned or paused) what the safety team decided."""
    _send_for_incident(incident_id, email_content.DECISION_EMAILS.get(action, ()))
