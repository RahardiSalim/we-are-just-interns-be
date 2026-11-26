"""Emails to the rider and driver after an agent decides a case: over HTTPS through Resend when RESEND_API_KEY is set
(Render's free tier blocks SMTP ports), otherwise plain SMTP from the standard library.
What the emails say and how they look: services/email_content.py."""

import base64
import logging
import re
import smtplib
from datetime import datetime
from email.message import EmailMessage
from pathlib import Path
from zoneinfo import ZoneInfo

import httpx
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


RESEND_URL = "https://api.resend.com/emails"


def send(to: str, subject: str, text: str, html: str | None = None) -> None:
    """Sends one email (HTML with a plain-text copy). Never raises: a failed email must not undo the agent's decision."""
    if not (config.RESEND_API_KEY or config.SMTP_HOST):
        log.info("email skipped (no RESEND_API_KEY or SMTP_HOST) to=%s subject=%s", to, subject)
        return
    try:
        if config.RESEND_API_KEY:
            _send_resend(to, subject, text, html)
        else:
            _send_smtp(to, subject, text, html)
    except Exception:
        log.exception("email failed to=%s subject=%s", to, subject)


def _inline_pictures(html: str) -> list[str]:
    """The picture ids the HTML uses (logo, illustration, icons), each shown inline so it needs no remote images."""
    return list(dict.fromkeys(re.findall(r'src="cid:([\w-]+)"', html)))


def _send_resend(to: str, subject: str, text: str, html: str | None) -> None:
    body: dict = {"from": config.RESEND_FROM, "to": [to], "subject": subject, "text": text}
    if html:
        body["html"] = html
        pictures = [asset(cid) for cid in _inline_pictures(html)]
        if pictures:
            body["attachments"] = [
                {"filename": p.name, "content": base64.b64encode(p.read_bytes()).decode(), "content_id": p.stem} for p in pictures
            ]
    res = httpx.post(RESEND_URL, headers={"Authorization": f"Bearer {config.RESEND_API_KEY}"}, json=body, timeout=20)
    if res.status_code >= 400:
        raise RuntimeError(f"Resend answered {res.status_code}: {res.text[:300]}")


def _send_smtp(to: str, subject: str, text: str, html: str | None) -> None:
    msg = EmailMessage()
    msg["From"], msg["To"], msg["Subject"] = config.EMAIL_FROM, to, subject
    msg.set_content(text)
    if html:
        msg.add_alternative(html, subtype="html")
        # Every picture the HTML uses goes inline, so it shows without loading remote images.
        for cid in _inline_pictures(html):
            path = asset(cid)
            msg.get_payload()[1].add_related(path.read_bytes(), "image", "jpeg" if path.suffix == ".jpg" else "png", cid=f"<{cid}>")
    with smtplib.SMTP(config.SMTP_HOST, config.SMTP_PORT, timeout=10) as smtp:
        smtp.starttls()
        if config.SMTP_USER:
            smtp.login(config.SMTP_USER, config.SMTP_PASSWORD)
        smtp.send_message(msg)


def address(uid: str) -> str | None:
    """The account email from Firebase Auth; else the one the person typed in the app (`users.email`,
    for the phone's anonymous accounts). None when neither exists, and the email is skipped."""
    try:
        email = auth.get_user(uid, app=init()).email
    except Exception:
        log.exception("no auth account for uid=%s", uid)
        email = None
    email = email or (db().document("users", uid).get().to_dict() or {}).get("email")
    if not email:
        log.info("no email address for uid=%s: email skipped", uid)
    return email


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
