"""Auth + users router. Per docs/api-contract.md §3.2."""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Response, status
from firebase_admin import auth as fb_auth

from app.deps import CurrentUser, VerifiedUid
from app.firebase import db
from app.schemas import User, UserUpdate

router = APIRouter(tags=["auth"])


@router.post("/auth/session", response_model=User)
async def create_session(uid: VerifiedUid) -> User:
    """Idempotent. Creates Firestore user doc on first call."""
    user_ref = db().collection("users").document(uid)
    snap = await user_ref.get()
    if snap.exists:
        data = snap.to_dict() or {}
        data["id"] = uid
        return User.model_validate(data)

    fb_user = fb_auth.get_user(uid)
    doc = {
        "name": fb_user.display_name or (fb_user.email or "User").split("@")[0],
        "email": fb_user.email or "",
        "role": None,
        "avatar_url": fb_user.photo_url,
        "is_agent_active": True,
        "autonomy_level": "suggest",
        "created_at": datetime.now(timezone.utc),
    }
    await user_ref.set(doc)
    return User.model_validate({**doc, "id": uid})


@router.get("/users/me", response_model=User)
async def get_me(user: CurrentUser) -> User:
    return user


@router.patch("/users/me", response_model=User)
async def patch_me(patch: UserUpdate, user: CurrentUser) -> User:
    updates = patch.model_dump(exclude_unset=True)
    if not updates:
        return user
    ref = db().collection("users").document(user.id)
    await ref.update(updates)
    snap = await ref.get()
    if not snap.exists:
        raise HTTPException(
            status_code=404,
            detail={"type": "not_found", "message": "User not found.", "status_code": 404},
        )
    data = snap.to_dict() or {}
    data["id"] = user.id
    return User.model_validate(data)


@router.delete("/users/me", status_code=status.HTTP_204_NO_CONTENT)
async def delete_me(user: CurrentUser) -> Response:
    user_ref = db().collection("users").document(user.id)
    subcollections = [
        "resumes",
        "pipeline",
        "applications",
        "conversations",
        "tailoring_jobs",
        "briefs",
        "usage",
    ]
    for name in subcollections:
        await _recursive_delete(user_ref.collection(name))
    await user_ref.delete()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


async def _recursive_delete(coll, batch_size: int = 100) -> None:
    while True:
        docs = [d async for d in coll.limit(batch_size).stream()]
        if not docs:
            return
        for doc in docs:
            for sub in doc.reference.collections():
                async for child in sub.stream():
                    await _recursive_delete_doc(child.reference)
            await doc.reference.delete()


async def _recursive_delete_doc(doc_ref) -> None:
    for sub in doc_ref.collections():
        async for child in sub.stream():
            await _recursive_delete_doc(child.reference)
    await doc_ref.delete()
