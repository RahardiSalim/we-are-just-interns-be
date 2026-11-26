from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.core.auth import current_user
from app.core.firebase import db

router = APIRouter(prefix="/me", tags=["me"])


class Consent(BaseModel):
    audioConsent: bool


class FcmToken(BaseModel):
    token: str = Field(min_length=1, max_length=4096)


@router.post("/consent")
def set_consent(body: Consent, user: dict = Depends(current_user)) -> dict:
    db().document("users", user["uid"]).set({"audioConsent": body.audioConsent}, merge=True)
    return {"audioConsent": body.audioConsent}


@router.post("/fcm-token")
def set_fcm_token(body: FcmToken, user: dict = Depends(current_user)) -> dict:
    db().document("users", user["uid"]).set({"fcmToken": body.token}, merge=True)
    return {"ok": True}
