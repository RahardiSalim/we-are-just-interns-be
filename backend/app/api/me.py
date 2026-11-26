from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.core.auth import current_user
from app.core.firebase import db

router = APIRouter(prefix="/me", tags=["me"])


class Consent(BaseModel):
    audioConsent: bool


class Email(BaseModel):
    """Where the safety team's emails go (SOS received, the agent's decision). The phone signs in
    anonymously, so its account has no address of its own; the person types one in the app."""

    email: str = Field(pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$", max_length=254)


class FcmToken(BaseModel):
    token: str = Field(min_length=1, max_length=4096)


@router.post("/consent")
def set_consent(body: Consent, user: dict = Depends(current_user)) -> dict:
    db().document("users", user["uid"]).set({"audioConsent": body.audioConsent}, merge=True)
    return {"audioConsent": body.audioConsent}


@router.post("/email")
def set_email(body: Email, user: dict = Depends(current_user)) -> dict:
    email = body.email.strip().lower()
    db().document("users", user["uid"]).set({"email": email}, merge=True)
    return {"email": email}


@router.post("/fcm-token")
def set_fcm_token(body: FcmToken, user: dict = Depends(current_user)) -> dict:
    db().document("users", user["uid"]).set({"fcmToken": body.token}, merge=True)
    return {"ok": True}
