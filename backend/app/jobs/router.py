"""Jobs HTTP layer. Per docs/api-contract.md §3.4.

Written by C covering for B (2026-05-13).
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.deps import CurrentUser
from app.jobs import sources
from app.schemas import Job

router = APIRouter(prefix="/jobs", tags=["jobs"])


class JobSearchRequest(BaseModel):
    query: str = Field(min_length=1, max_length=200)
    location: str | None = None
    limit: int = Field(default=25, ge=1, le=50)


class JobSearchResponse(BaseModel):
    data: list[Job]


@router.get("/{job_id}", response_model=Job)
async def get_job(job_id: str, _user: CurrentUser) -> Job:
    job = await sources.get(job_id)
    if job is None:
        raise HTTPException(
            status_code=404,
            detail={"type": "not_found", "message": "Job not found.", "status_code": 404},
        )
    return job


@router.post("/search", response_model=JobSearchResponse)
async def search_jobs(
    body: JobSearchRequest, _user: CurrentUser
) -> JobSearchResponse:
    jobs = await sources.search(query=body.query, location=body.location, limit=body.limit)
    return JobSearchResponse(data=jobs)
