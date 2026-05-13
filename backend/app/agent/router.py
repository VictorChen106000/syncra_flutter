"""Agent HTTP layer: brief lifecycle + pipeline + approve/dismiss.

Per docs/api-contract.md §3.5. Chat endpoint is out of scope for this commit.

Written by C covering for B (2026-05-13).
"""

from __future__ import annotations

import logging
import uuid
from datetime import datetime, timezone
from typing import Annotated, Any

from fastapi import APIRouter, BackgroundTasks, HTTPException, Query
from pydantic import BaseModel

from app.config import settings
from app.deps import CurrentUser, rate_limit
from app.firebase import db
from app.agent import reasoner
from app.schemas import (
    Application,
    Brief,
    Page,
    PipelineCard,
    PipelineCategory,
    PipelineStatus,
)

log = logging.getLogger("syncra.agent")
router = APIRouter(prefix="/agent", tags=["agent"])


# ---------------------------------------------------------------------------
# Request / response shapes (kept local — not in shared schemas)
# ---------------------------------------------------------------------------


class BriefCreateRequest(BaseModel):
    force: bool = False


class BriefCreateResponse(BaseModel):
    brief_id: str
    status: str
    poll_url: str


class ApproveRequest(BaseModel):
    resume_id: str
    auto_submit: bool = False


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _briefs_coll(uid: str):
    return db().collection("users").document(uid).collection("briefs")


def _pipeline_coll(uid: str):
    return db().collection("users").document(uid).collection("pipeline")


def _apps_coll(uid: str):
    return db().collection("users").document(uid).collection("applications")


async def _load_brief(uid: str, brief_id: str) -> Brief:
    snap = await _briefs_coll(uid).document(brief_id).get()
    if not snap.exists:
        raise HTTPException(
            status_code=404,
            detail={"type": "not_found", "message": "Brief not found.", "status_code": 404},
        )
    data = snap.to_dict() or {}
    data["id"] = brief_id
    return Brief.model_validate(data)


async def _load_card(uid: str, card_id: str) -> PipelineCard:
    snap = await _pipeline_coll(uid).document(card_id).get()
    if not snap.exists:
        raise HTTPException(
            status_code=404,
            detail={"type": "not_found", "message": "Pipeline card not found.", "status_code": 404},
        )
    data = snap.to_dict() or {}
    data["id"] = card_id
    return PipelineCard.model_validate(data)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


_brief_rate_limit = rate_limit("brief", settings.rate_limit_brief_daily)


@router.post(
    "/brief",
    status_code=202,
    response_model=BriefCreateResponse,
    dependencies=[],
)
async def create_brief(
    body: BriefCreateRequest,
    user: CurrentUser,
    background: BackgroundTasks,
    _: Annotated[None, type(None)] = None,  # rate-limit slot, see note below
) -> BriefCreateResponse:
    # Apply rate limit inline (FastAPI dependency factory consumed via Depends would be cleaner,
    # but rate_limit needs `user` which is also a dep — calling it directly here is simplest).
    await _brief_rate_limit(user)

    if not body.force:
        recent = (
            _briefs_coll(user.id)
            .order_by("created_at", direction="DESCENDING")
            .limit(1)
        )
        async for last in recent.stream():
            data = last.to_dict() or {}
            status_ = data.get("status")
            if status_ in ("pending", "running"):
                return BriefCreateResponse(
                    brief_id=last.id,
                    status=status_,
                    poll_url=f"{settings.api_prefix}/agent/brief/{last.id}",
                )

    brief = await reasoner.create_brief(user.id)
    role_query = user.role or "Software Engineer"
    background.add_task(reasoner.run_brief, user.id, brief.id, role_query)

    return BriefCreateResponse(
        brief_id=brief.id,
        status=brief.status,
        poll_url=f"{settings.api_prefix}/agent/brief/{brief.id}",
    )


@router.get("/brief/{brief_id}", response_model=Brief)
async def get_brief(brief_id: str, user: CurrentUser) -> Brief:
    return await _load_brief(user.id, brief_id)


@router.get("/pipeline", response_model=Page[PipelineCard])
async def list_pipeline(
    user: CurrentUser,
    category: Annotated[PipelineCategory | None, Query()] = None,
    pipeline_status: Annotated[PipelineStatus | None, Query(alias="status")] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 25,
    cursor: Annotated[str | None, Query()] = None,
) -> Page[PipelineCard]:
    q: Any = _pipeline_coll(user.id).order_by("created_at", direction="DESCENDING")
    if category is not None:
        q = q.where("category", "==", category)
    if pipeline_status is not None:
        q = q.where("status", "==", pipeline_status)
    if cursor:
        cursor_snap = await _pipeline_coll(user.id).document(cursor).get()
        if cursor_snap.exists:
            q = q.start_after(cursor_snap)

    docs = [d async for d in q.limit(limit + 1).stream()]
    next_cursor = docs[limit].id if len(docs) > limit else None
    data: list[PipelineCard] = []
    for d in docs[:limit]:
        item = d.to_dict() or {}
        item["id"] = d.id
        data.append(PipelineCard.model_validate(item))
    return Page[PipelineCard](data=data, next_cursor=next_cursor)


@router.post("/pipeline/{card_id}/approve", response_model=Application)
async def approve_card(
    card_id: str, body: ApproveRequest, user: CurrentUser
) -> Application:
    card = await _load_card(user.id, card_id)
    if card.status != "pending":
        raise HTTPException(
            status_code=409,
            detail={
                "type": "validation",
                "message": f"Card already {card.status}.",
                "status_code": 409,
            },
        )

    # TODO(person-a): if card.tailored_resume_id is None, trigger tailoring here.
    #   For v1, we just create the Application with the provided resume_id.
    #   auto_submit is accepted but actually submitting is out of scope (per team-briefs.md §B).
    if body.auto_submit:
        log.info("approve.auto_submit_noop user=%s card=%s", user.id, card_id)

    now = datetime.now(timezone.utc)
    app_id = f"app_{uuid.uuid4().hex[:16]}"
    application = Application(
        id=app_id,
        job=card.job,
        resume_id=body.resume_id,
        pipeline_card_id=card_id,
        status="submitted",
        submitted_at=now,
        last_update_at=now,
        next_step=None,
        cover_letter=None,
    )

    batch = db().batch()
    batch.set(_apps_coll(user.id).document(app_id), application.model_dump(mode="json"))
    batch.update(
        _pipeline_coll(user.id).document(card_id),
        {"status": "approved", "tailored_resume_id": body.resume_id},
    )
    await batch.commit()

    return application


@router.post("/pipeline/{card_id}/dismiss", status_code=204)
async def dismiss_card(card_id: str, user: CurrentUser) -> None:
    card = await _load_card(user.id, card_id)
    if card.status != "pending":
        raise HTTPException(
            status_code=409,
            detail={
                "type": "validation",
                "message": f"Card already {card.status}.",
                "status_code": 409,
            },
        )
    await _pipeline_coll(user.id).document(card_id).update({"status": "dismissed"})
