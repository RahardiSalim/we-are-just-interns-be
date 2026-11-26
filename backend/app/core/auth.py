from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from firebase_admin import auth

from app.core import firebase

bearer = HTTPBearer(auto_error=False)


def current_user(creds: HTTPAuthorizationCredentials | None = Depends(bearer)) -> dict:
    """Decoded Firebase ID token: uid, email, and the `role` custom claim."""
    if creds is None:
        raise HTTPException(401, "Missing bearer token")
    try:
        return auth.verify_id_token(creds.credentials, app=firebase.init())
    except (ValueError, auth.InvalidIdTokenError):
        raise HTTPException(401, "Invalid or expired token")


def require_role(*roles: str):
    def check(user: dict = Depends(current_user)) -> dict:
        if user.get("role") not in roles:
            raise HTTPException(403, f"Requires role: {', '.join(roles)}")
        return user

    return check
