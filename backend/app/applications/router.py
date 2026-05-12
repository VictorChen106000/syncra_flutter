"""Application tracker endpoints. Per docs/api-contract.md §3.6."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Annotated

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

from app.deps import CurrentUser
from app.firebase import db
from app.schemas import Application, ApplicationStatus, Page

router = APIRouter(prefix="/applications", tags=["applications"])


class ApplicationPatch(BaseModel):
    status: ApplicationStatus | None = None
    next_step: str | None = None


def _apps_coll(uid: str):
    return db().collection("users").document(uid).collection("applications")


@router.get("", response_model=Page[Application])
async def list_applications(
    user: CurrentUser,
    status_filter: Annotated[ApplicationStatus | None, Query(alias="status")] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    cursor: Annotated[str | None, Query()] = None,
) -> Page[Application]:
    q = _apps_coll(user.id).order_by("submitted_at", direction="DESCENDING")
    if status_filter is not None:
        q = q.where("status", "==", status_filter)
    if cursor:
        cursor_snap = await _apps_coll(user.id).document(cursor).get()
        if cursor_snap.exists:
            q = q.start_after(cursor_snap)

    docs = [d async for d in q.limit(limit + 1).stream()]
    next_cursor = docs[limit].id if len(docs) > limit else None
    data = [_to_application(d) for d in docs[:limit]]
    return Page[Application](data=data, next_cursor=next_cursor)


@router.get("/{app_id}", response_model=Application)
async def get_application(app_id: str, user: CurrentUser) -> Application:
    snap = await _apps_coll(user.id).document(app_id).get()
    if not snap.exists:
        raise HTTPException(
            status_code=404,
            detail={"type": "not_found", "message": "Application not found.", "status_code": 404},
        )
    return _to_application(snap)


@router.patch("/{app_id}", response_model=Application)
async def patch_application(
    app_id: str, patch: ApplicationPatch, user: CurrentUser
) -> Application:
    updates = patch.model_dump(exclude_unset=True)
    if not updates:
        snap = await _apps_coll(user.id).document(app_id).get()
        if not snap.exists:
            raise HTTPException(
                status_code=404,
                detail={"type": "not_found", "message": "Application not found.", "status_code": 404},
            )
        return _to_application(snap)

    updates["last_update_at"] = datetime.now(timezone.utc)
    ref = _apps_coll(user.id).document(app_id)
    snap = await ref.get()
    if not snap.exists:
        raise HTTPException(
            status_code=404,
            detail={"type": "not_found", "message": "Application not found.", "status_code": 404},
        )
    await ref.update(updates)
    snap = await ref.get()
    return _to_application(snap)


def _to_application(snap) -> Application:
    data = snap.to_dict() or {}
    data["id"] = snap.id
    return Application.model_validate(data)
