"""Shared FastAPI dependencies: current_user, rate_limit. Per docs/api-contract.md §1."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Annotated

from fastapi import Depends, Header, HTTPException, status
from firebase_admin import exceptions as fb_exc
from google.cloud.firestore import AsyncTransaction, SERVER_TIMESTAMP

from app.firebase import db, verify_id_token
from app.schemas import User


async def _load_user(uid: str) -> User:
    snap = await db().collection("users").document(uid).get()
    if not snap.exists:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"type": "not_found", "message": "User not found. Call POST /auth/session first.", "status_code": 404},
        )
    data = snap.to_dict() or {}
    data["id"] = uid
    return User.model_validate(data)


async def get_verified_uid(
    authorization: Annotated[str | None, Header()] = None,
) -> str:
    """Verify token and return UID only. Use for endpoints where the user doc may not exist yet."""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"type": "auth", "message": "Missing bearer token.", "status_code": 401},
        )
    token = authorization.split(" ", 1)[1].strip()
    try:
        return await verify_id_token(token)
    except (fb_exc.FirebaseError, ValueError) as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"type": "auth", "message": f"Invalid token: {e}", "status_code": 401},
        ) from e


async def get_current_user(uid: Annotated[str, Depends(get_verified_uid)]) -> User:
    return await _load_user(uid)


VerifiedUid = Annotated[str, Depends(get_verified_uid)]
CurrentUser = Annotated[User, Depends(get_current_user)]


def rate_limit(endpoint_key: str, daily_cap: int):
    """Dependency factory: per-user daily cap on LLM-heavy endpoints.

    Counters at users/{uid}/usage/{YYYY-MM-DD}. Increments via Firestore transaction.
    """

    async def _check(user: CurrentUser) -> None:
        today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        client = db()
        ref = client.collection("users").document(user.id).collection("usage").document(today)

        @client.transactional  # type: ignore[misc]
        async def _txn(tx: AsyncTransaction) -> int:
            snap = await ref.get(transaction=tx)
            current = (snap.to_dict() or {}).get(endpoint_key, 0) if snap.exists else 0
            if current >= daily_cap:
                return current
            tx.set(
                ref,
                {endpoint_key: current + 1, "updated_at": SERVER_TIMESTAMP},
                merge=True,
            )
            return current + 1

        new_count = await _txn(client.transaction())
        if new_count > daily_cap:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail={
                    "type": "rate_limited",
                    "message": f"Daily cap of {daily_cap} reached for {endpoint_key}.",
                    "status_code": 429,
                },
            )

    return _check
