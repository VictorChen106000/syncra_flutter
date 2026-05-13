"""External job sources. Right now: JSearch via RapidAPI.

Written by C covering for B (2026-05-13). B should revisit:
- The 1-hour cache (in-memory; loses warmth on Railway redeploys — fine for MVP).
- Map of JSearch fields to our Job schema (especially salary normalization).
"""

from __future__ import annotations

import asyncio
import hashlib
import logging
import time
from datetime import datetime, timezone
from typing import Any

import httpx

from app.config import settings
from app.firebase import db
from app.schemas import Job

log = logging.getLogger("syncra.sources")

_CACHE_TTL_SECONDS = 3600  # 1 hour, per team-briefs Person B notes.
_HTTP_TIMEOUT = httpx.Timeout(15.0, connect=5.0)
_query_cache: dict[str, tuple[float, list[Job]]] = {}
_cache_lock = asyncio.Lock()


def _cache_key(query: str, location: str | None, limit: int) -> str:
    raw = f"{query.lower().strip()}|{(location or '').lower().strip()}|{limit}"
    return hashlib.sha256(raw.encode()).hexdigest()[:16]


def _job_id_for(title: str, company: str, source_url: str) -> str:
    """Deterministic ID so re-discoveries collapse on Firestore upsert."""
    raw = f"{title.lower().strip()}|{company.lower().strip()}|{source_url.lower().strip()}"
    return "job_" + hashlib.sha256(raw.encode()).hexdigest()[:20]


def _jsearch_to_job(raw: dict[str, Any]) -> Job | None:
    title = (raw.get("job_title") or "").strip()
    company = (raw.get("employer_name") or "").strip()
    source_url = (raw.get("job_apply_link") or raw.get("job_google_link") or "").strip()
    description = (raw.get("job_description") or "").strip()
    if not title or not company or not source_url:
        return None

    location_parts = [
        raw.get("job_city"),
        raw.get("job_state"),
        raw.get("job_country"),
    ]
    location = ", ".join(p for p in location_parts if p) or None
    if raw.get("job_is_remote"):
        location = "Remote" if not location else f"Remote — {location}"

    salary: str | None = None
    if raw.get("job_min_salary") and raw.get("job_max_salary"):
        salary = f"${int(raw['job_min_salary']):,}-${int(raw['job_max_salary']):,}"
        if raw.get("job_salary_period"):
            salary += f"/{str(raw['job_salary_period']).lower()}"

    posted = raw.get("job_posted_at_datetime_utc")
    discovered_at = (
        datetime.fromisoformat(posted.replace("Z", "+00:00"))
        if isinstance(posted, str)
        else datetime.now(timezone.utc)
    )

    return Job(
        id=_job_id_for(title, company, source_url),
        title=title,
        company=company,
        location=location,
        salary=salary,
        description=description,
        source="jsearch",
        source_url=source_url,
        discovered_at=discovered_at,
    )


async def _fetch_jsearch(query: str, location: str | None, limit: int) -> list[dict[str, Any]]:
    params: dict[str, str] = {
        "query": query if not location else f"{query} in {location}",
        "page": "1",
        "num_pages": "1",
        "country": "us",
        "date_posted": "week",
    }
    headers = {
        "X-RapidAPI-Key": settings.rapidapi_key,
        "X-RapidAPI-Host": settings.jsearch_host,
    }
    url = f"https://{settings.jsearch_host}/search"

    async with httpx.AsyncClient(timeout=_HTTP_TIMEOUT) as client:
        resp = await client.get(url, params=params, headers=headers)
        resp.raise_for_status()
        body = resp.json()

    raw_jobs = body.get("data") or []
    return raw_jobs[:limit]


async def _upsert(jobs: list[Job]) -> None:
    if not jobs:
        return
    client = db()
    batch = client.batch()
    for job in jobs:
        ref = client.collection("jobs").document(job.id)
        batch.set(ref, job.model_dump(mode="json"), merge=True)
    await batch.commit()


async def search(query: str, location: str | None = None, limit: int = 25) -> list[Job]:
    """Search JSearch, normalize, dedupe, upsert into global `jobs/`, return Job list.

    Cache hits within `_CACHE_TTL_SECONDS` avoid hitting RapidAPI again.
    """
    key = _cache_key(query, location, limit)
    now = time.monotonic()

    async with _cache_lock:
        cached = _query_cache.get(key)
        if cached and (now - cached[0]) < _CACHE_TTL_SECONDS:
            log.info("sources.cache_hit query=%s location=%s", query, location)
            return cached[1]

    raw = await _fetch_jsearch(query, location, limit)
    seen: set[str] = set()
    jobs: list[Job] = []
    for item in raw:
        job = _jsearch_to_job(item)
        if job is None or job.id in seen:
            continue
        seen.add(job.id)
        jobs.append(job)

    await _upsert(jobs)

    async with _cache_lock:
        _query_cache[key] = (now, jobs)

    log.info("sources.fetched query=%s count=%d", query, len(jobs))
    return jobs


async def get(job_id: str) -> Job | None:
    snap = await db().collection("jobs").document(job_id).get()
    if not snap.exists:
        return None
    data = snap.to_dict() or {}
    data["id"] = snap.id
    return Job.model_validate(data)
