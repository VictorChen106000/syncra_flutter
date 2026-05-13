"""Agent reasoning — the Brief pipeline as a background task.

Written by C covering for B (2026-05-13). Mechanics are deliberately simple; intelligence
lives in jobs/matcher.py (the prompt). When B picks this up, look first at:
  - The concurrency limit (semaphore of 5) — tune if Anthropic rate-limits.
  - The agent_action / agent_justification strings — currently deterministic, no LLM.
"""

from __future__ import annotations

import asyncio
import logging
import uuid
from datetime import datetime, timezone

from app.firebase import db
from app.jobs import matcher, sources
from app.jobs.matcher import MatchVerdict
from app.schemas import (
    Brief,
    BriefProgress,
    Job,
    PipelineCard,
    ResumeJSON,
)

log = logging.getLogger("syncra.reasoner")

_MATCH_CONCURRENCY = 5
_DEFAULT_LIMIT = 25
_SCORE_FRESH_BONUS_HOURS = 24  # job posted <24h ago → "Proactive Intercept"


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _agent_action_and_justification(job: Job, verdict: MatchVerdict) -> tuple[str, str]:
    """Deterministic narrative. No LLM here — kept cheap and consistent."""
    age_hours = max(0.0, (_now() - job.discovered_at).total_seconds() / 3600.0)
    if verdict.category == "ready":
        if age_hours <= _SCORE_FRESH_BONUS_HOURS:
            return (
                "Proactive Intercept",
                f"{job.company} posted this {_humanize_age(age_hours)} ago — strong fit; recommend applying today.",
            )
        return (
            "Auto-Apply Recommended",
            f"Strong alignment with your background; the job is from {job.company}.",
        )
    if verdict.category == "input_needed":
        gap_count = len(verdict.missing_skills)
        return (
            "Review Required",
            f"Solid fit, but you're missing {gap_count} skill{'s' if gap_count != 1 else ''} the JD calls out — review before approving.",
        )
    return (
        "Worth a Look",
        f"Stretch fit at {job.company}. Browse if you have time; not a must-apply.",
    )


def _humanize_age(hours: float) -> str:
    if hours < 1.0:
        minutes = max(1, int(hours * 60))
        return f"{minutes} min"
    if hours < 48.0:
        return f"{int(hours)} hr"
    return f"{int(hours / 24)} days"


async def _load_active_resume(uid: str) -> ResumeJSON | None:
    """Pick a manual resume's parsed ResumeJSON. Sort newest-first in Python to avoid
    needing a composite Firestore index (single-field filters only)."""
    coll = db().collection("users").document(uid).collection("resumes")
    docs = [d async for d in coll.where("source", "==", "manual").stream()]
    docs.sort(key=lambda d: (d.to_dict() or {}).get("uploaded_at", ""), reverse=True)
    for resume_doc in docs:
        parsed = await resume_doc.reference.collection("parsed").document("parsed").get()
        if not parsed.exists:
            continue
        return ResumeJSON.model_validate(parsed.to_dict() or {})
    return None


async def _update_brief(uid: str, brief_id: str, **fields) -> None:
    fields["updated_at"] = _now()
    await db().collection("users").document(uid).collection("briefs").document(brief_id).set(
        fields, merge=True
    )


async def _write_pipeline_card(uid: str, job: Job, verdict: MatchVerdict) -> None:
    action, justification = _agent_action_and_justification(job, verdict)
    card_id = f"card_{uuid.uuid4().hex[:16]}"
    card = PipelineCard(
        id=card_id,
        user_id=uid,
        job=job,
        category=verdict.category,
        agent_action=action,
        agent_justification=justification,
        matched_skills=verdict.matched_skills,
        missing_skills=verdict.missing_skills,
        why=verdict.why,
        tailored_resume_id=None,
        created_at=_now(),
        status="pending",
    )
    await db().collection("users").document(uid).collection("pipeline").document(card_id).set(
        card.model_dump(mode="json")
    )


async def _match_one(
    sem: asyncio.Semaphore,
    resume: ResumeJSON,
    job: Job,
) -> tuple[Job, MatchVerdict] | None:
    async with sem:
        try:
            verdict = await matcher.match(resume, job)
            return job, verdict
        except Exception as e:  # noqa: BLE001 — single brief shouldn't kill the whole run
            log.exception("reasoner.match_failed job=%s err=%s", job.id, e)
            return None


async def run_brief(uid: str, brief_id: str, role_query: str, limit: int = _DEFAULT_LIMIT) -> None:
    """Background task. Updates `users/{uid}/briefs/{brief_id}` throughout.

    Wrapped in a top-level try/except so ANY crash flips the brief to status=error.
    Without this, an unhandled exception leaves the brief stuck on "running" forever
    and the frontend polls indefinitely.
    """
    try:
        await _update_brief(uid, brief_id, status="running", progress=BriefProgress().model_dump())

        resume = await _load_active_resume(uid)
        if resume is None:
            await _update_brief(
                uid,
                brief_id,
                status="error",
                error="No active resume found. Upload one before running a brief.",
            )
            return

        jobs = await sources.search(query=role_query, limit=limit)
        total = len(jobs)
        await _update_brief(
            uid, brief_id, progress=BriefProgress(current=0, total=total).model_dump()
        )

        sem = asyncio.Semaphore(_MATCH_CONCURRENCY)
        tasks = [asyncio.create_task(_match_one(sem, resume, job)) for job in jobs]

        results: list[tuple[Job, MatchVerdict]] = []
        completed = 0
        for coro in asyncio.as_completed(tasks):
            result = await coro
            completed += 1
            if result is not None:
                results.append(result)
            if completed % 3 == 0 or completed == total:
                await _update_brief(
                    uid,
                    brief_id,
                    progress=BriefProgress(current=completed, total=total).model_dump(),
                )

        # Sort by internal score (highest first) so the pipeline reads best-to-worst.
        results.sort(key=lambda r: r[1].match_score, reverse=True)

        for job, verdict in results:
            await _write_pipeline_card(uid, job, verdict)

        await _update_brief(
            uid,
            brief_id,
            status="done",
            card_count=len(results),
            progress=BriefProgress(current=total, total=total).model_dump(),
        )
        await db().collection("users").document(uid).set({"last_brief_at": _now()}, merge=True)
    except Exception as e:  # noqa: BLE001
        log.exception("reasoner.run_brief_failed brief=%s err=%s", brief_id, e)
        try:
            await _update_brief(uid, brief_id, status="error", error=str(e))
        except Exception:  # noqa: BLE001
            log.exception("reasoner.failed_to_record_error brief=%s", brief_id)


async def create_brief(uid: str) -> Brief:
    """Create the brief doc in `pending` state. Caller schedules run_brief afterward."""
    brief_id = f"brief_{uuid.uuid4().hex[:16]}"
    now = _now()
    brief = Brief(
        id=brief_id,
        status="pending",
        progress=BriefProgress(),
        card_count=None,
        error=None,
        created_at=now,
        updated_at=now,
    )
    await db().collection("users").document(uid).collection("briefs").document(brief_id).set(
        brief.model_dump(mode="json")
    )
    return brief
