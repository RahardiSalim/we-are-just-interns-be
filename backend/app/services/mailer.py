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
ASSETS = Path(__file__).parents[1] / "assets"  # <cid>.png or <cid>.jpg for every inline picture


def asset(cid: str) -> Path:
    """The picture file for an inline image: PNG for icons and the logo, JPEG for the photo-sized illustration."""
    return next(p for p in (ASSETS / f"{cid}.png", ASSETS / f"{cid}.jpg") if p.exists())


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
        # Every picture the HTML uses (logo, illustration, icons) goes inline, so it shows without loading remote images.
        for cid in dict.fromkeys(re.findall(r'src="cid:([\w-]+)"', html)):
            path = asset(cid)
            msg.get_payload()[1].add_related(path.read_bytes(), "image", "jpeg" if path.suffix == ".jpg" else "png", cid=f"<{cid}>")
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


def _send_for_incident(incident_id: str, emails: tuple[email_content.Email, ...], notes: dict[str, str] | None = None) -> None:
    """Sends each email to the person it's for (rider, driver or the reporter), filled in from the incident and trip.
    `notes` maps "rider" / "driver" to the safety team's message for that person."""
    inc = db().document("incidents", incident_id).get().to_dict() or {}
    order = inc.get("tripId", "-")
    trip = db().document("trips", order).get().to_dict() or {}
    for e in emails:
        uid = inc.get("reportedBy") if e.to == "reporter" else trip.get(f"{e.to}Id")
        to = uid and address(uid)
        if not to:
            continue
        ticket = email_content.ticket_number(incident_id)
        args = (first_name(uid), order, wib(trip.get("startedAt")), ticket, (notes or {}).get(e.to, ""))
        send(to, email_content.subject(e, order, ticket), email_content.text(e, *args), email_content.html(e, *args))


def sos_received(incident_id: str) -> None:
    """Tells whoever pressed SOS that their ticket was created and is being processed."""
    _send_for_incident(incident_id, (email_content.SOS_RECEIVED,))


def decision(incident_id: str, customer: str, driver: str, customer_note: str = "", driver_note: str = "") -> None:
    """Tells the rider what the safety team decided, and the driver too unless the driver decision is "none"."""
    _send_for_incident(incident_id, email_content.decision_emails(customer, driver), {"rider": customer_note, "driver": driver_note})
