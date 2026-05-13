"""LLM-judge job matching via Claude Haiku.

Written by C covering for B (2026-05-13). When B picks this up, the matcher prompt is the
highest-leverage piece to revisit — that's where score quality lives. Plumbing is
deliberately simple.

Per docs/api-contract.md §2 (v0.4):
- Public output is tier-only (`category`). No `match_score` on PipelineCard.
- The matcher still returns an internal score 0-100 used ONLY for sorting in reasoner.py.
"""

from __future__ import annotations

import logging
from typing import Any

from pydantic import BaseModel, Field

from app.llm import llm
from app.schemas import Job, PipelineCategory, ResumeJSON

log = logging.getLogger("syncra.matcher")


class MatchVerdict(BaseModel):
    """Internal verdict from the matcher. `match_score` is private — never surface in API."""

    match_score: int = Field(ge=0, le=100)
    category: PipelineCategory
    matched_skills: list[str] = Field(default_factory=list, max_length=5)
    missing_skills: list[str] = Field(default_factory=list, max_length=5)
    why: str


_SYSTEM_PROMPT = """\
You are a job-matching assistant. Score how well a candidate's resume fits a job posting,
then decide what action makes sense for the candidate.

SCORING RUBRIC (internal score, 0-100):
- 85-100: Strong fit. Title, level, and most must-have skills align. Candidate could apply today.
- 65-84:  Reasonable fit. Most required skills present, but 1-3 real gaps.
- 40-64:  Stretch fit. Adjacent role or experience; gaps are meaningful.
- 0-39:   Poor fit. Wrong field, wrong level, or fundamental skill mismatch.

CATEGORY (pick based on score AND missing_skills together):
- "ready":           score >= 85 AND missing_skills.length <= 1
- "input_needed":    score >= 70 AND 1 <= missing_skills.length <= 3
                     (real fit, but gaps the candidate may be able to bridge)
- "exploration":     everything else worth surfacing
                     (score 50-69, OR score >= 70 with too many gaps to fast-track)
- For score < 50, still call the tool, mark category="exploration", be honest in `why`.

CONSTRAINTS:
- Pick AT MOST 5 matched_skills and 5 missing_skills. Pick the most important ones,
  not the longest list.
- If a job field is empty or vague (no salary, short description), ignore it in scoring.
  Do not penalize the candidate for the API's data gaps.
- `why` is addressed to the candidate in second person ("Your X aligns with their Y...").
  Name a specific company, skill, or year from the resume. Avoid corporate fluff. Max 2 sentences.

You MUST respond by calling the submit_match_verdict tool. Do not respond in prose.
"""


_MATCH_TOOL: dict[str, Any] = {
    "name": "submit_match_verdict",
    "description": "Submit the structured match verdict for the resume/job pair.",
    "input_schema": {
        "type": "object",
        "properties": {
            "match_score": {
                "type": "integer",
                "minimum": 0,
                "maximum": 100,
                "description": "Internal numeric fit score. Used for sort order, not user-facing.",
            },
            "category": {
                "type": "string",
                "enum": ["ready", "input_needed", "exploration"],
                "description": "Public tier label.",
            },
            "matched_skills": {
                "type": "array",
                "items": {"type": "string"},
                "maxItems": 5,
                "description": "Up to 5 most important skills in both resume and JD.",
            },
            "missing_skills": {
                "type": "array",
                "items": {"type": "string"},
                "maxItems": 5,
                "description": "Up to 5 most important JD requirements the resume lacks.",
            },
            "why": {
                "type": "string",
                "description": "1-2 sentences, second person, candidate-facing.",
            },
        },
        "required": ["match_score", "category", "matched_skills", "missing_skills", "why"],
    },
}


def _user_message(resume: ResumeJSON, job: Job) -> str:
    return (
        "Resume (ResumeJSON):\n"
        + resume.model_dump_json(indent=2)
        + "\n\nJob:\n"
        + job.model_dump_json(indent=2)
    )


async def match(resume: ResumeJSON, job: Job) -> MatchVerdict:
    """Score resume against job. Forces structured output via tool use."""
    msg = await llm.haiku(
        messages=[{"role": "user", "content": _user_message(resume, job)}],
        system=_SYSTEM_PROMPT,
        tools=[_MATCH_TOOL],
        tool_choice={"type": "tool", "name": "submit_match_verdict"},
        max_tokens=512,
    )

    for block in msg.content:
        if getattr(block, "type", None) == "tool_use" and block.name == "submit_match_verdict":
            return MatchVerdict.model_validate(block.input)

    log.error("matcher.no_tool_call job=%s blocks=%s", job.id, [getattr(b, "type", "?") for b in msg.content])
    raise ValueError(f"Matcher did not call the tool for job {job.id}.")
