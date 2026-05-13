"""Firebase Admin init. Lazy — first call to db() initializes the app.

This lets /health (no auth, no DB) start even if creds are missing.
No Cloud Storage: see docs/api-contract.md §0 — PDFs render on demand from ResumeJSON.
"""

from __future__ import annotations

import asyncio
from functools import lru_cache

import firebase_admin
from firebase_admin import auth as fb_auth
from firebase_admin import credentials
from google.cloud.firestore import AsyncClient
from google.oauth2 import service_account

from app.config import settings


@lru_cache
def _app() -> firebase_admin.App:
    cred = credentials.Certificate(settings.firebase_credentials_path)
    return firebase_admin.initialize_app(cred)


@lru_cache
def db() -> AsyncClient:
    app = _app()
    creds = service_account.Credentials.from_service_account_file(
        settings.firebase_credentials_path
    )
    return AsyncClient(project=app.project_id, credentials=creds)


async def verify_id_token(token: str) -> str:
    """Verify a Firebase ID token. Returns the UID. Raises on invalid/expired."""
    _app()
    decoded = await asyncio.to_thread(fb_auth.verify_id_token, token, check_revoked=False)
    return decoded["uid"]
