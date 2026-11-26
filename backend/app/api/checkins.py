from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from pydantic import BaseModel

from app.core.auth import current_user
from app.core.firebase import db
from app.services import pipeline

router = APIRouter(prefix="/checkins", tags=["checkins"])


class Reply(BaseModel):
    answer: Literal["ok", "need_help"]


@router.post("/{checkin_id}/reply")
def reply(checkin_id: str, body: Reply, user: dict = Depends(current_user)) -> dict:
    ref = db().document("checkins", checkin_id)

    # One transaction so two replies (or a reply and the timeout) can't both decide the case.
    @firestore.transactional
    def answer(tx) -> str:
        snap = ref.get(transaction=tx)
        if not snap.exists:
            raise HTTPException(404, "Check-in not found")
        if snap.get("userId") != user["uid"]:
            raise HTTPException(403, "Not your check-in")
        if snap.get("status") != "sent":
            raise HTTPException(409, "Already answered")
        inc_ref = db().document("incidents", snap.get("incidentId"))
        inc_status = inc_ref.get(transaction=tx).get("status")
        others = [c for c in tx.get(db().collection("checkins").where(filter=FieldFilter("incidentId", "==", snap.get("incidentId"))))
                  if c.id != checkin_id]

        tx.update(ref, {"status": body.answer, "repliedAt": firestore.SERVER_TIMESTAMP})
        if inc_status != "checkin_pending":
            return inc_status  # the timeout or the other party already decided
        if body.answer == "need_help":
            tx.update(inc_ref, {"status": "escalated"})
            return "escalated"
        if all(c.get("status") == "ok" for c in others):
            tx.update(inc_ref, {"status": "resolved_ok"})
            return "resolved_ok"
        return inc_status

    incident_status = answer(db().transaction())
    if incident_status == "escalated" and body.answer == "need_help":
        pipeline.escalate(ref.get().get("incidentId"))
    return {"status": body.answer, "incidentStatus": incident_status}
