from fastapi import APIRouter, Depends, HTTPException

from app.core import config
from app.core.auth import require_role
from app.services import seed


def dev_enabled() -> None:
    if not config.ENABLE_DEV_ROUTES:
        raise HTTPException(404)


# dev_enabled runs first, so a disabled build answers 404 without revealing the routes need auth.
router = APIRouter(prefix="/dev", tags=["dev"], dependencies=[Depends(dev_enabled), Depends(require_role("agent"))])


@router.post("/seed")
def dev_seed() -> dict:
    return seed.seed_data()


@router.post("/reset")
def dev_reset() -> dict:
    seed.reset_data()
    return seed.seed_data()
