"""Shared Pydantic models. Source of truth: docs/api-contract.md §2."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

AutonomyLevel = Literal["suggest", "ask_first", "auto_apply"]
ResumeSource = Literal["manual", "tailored"]
PipelineCategory = Literal["ready", "input_needed", "exploration"]
PipelineStatus = Literal["pending", "approved", "dismissed"]
ApplicationStatus = Literal[
    "submitted", "viewed", "replied", "interview", "offer", "rejected"
]
ChatSender = Literal["user", "agent"]
TailoringStatus = Literal["pending", "rendering", "done", "error"]
BriefStatus = Literal["pending", "running", "done", "error"]
ErrorType = Literal["validation", "auth", "not_found", "rate_limited", "server"]


class _Base(BaseModel):
    model_config = ConfigDict(populate_by_name=True)


class User(_Base):
    id: str
    name: str
    email: str
    role: str | None = None
    avatar_url: str | None = None
    is_agent_active: bool = True
    autonomy_level: AutonomyLevel = "suggest"
    created_at: datetime
    last_brief_at: datetime | None = None


class UserUpdate(_Base):
    name: str | None = None
    role: str | None = None
    autonomy_level: AutonomyLevel | None = None
    is_agent_active: bool | None = None


class Resume(_Base):
    id: str
    name: str
    size: int
    mime_type: str
    uploaded_at: datetime
    source: ResumeSource
    storage_url: str
    parent_resume_id: str | None = None
    tailored_for_job_id: str | None = None


class ResumeHeader(_Base):
    name: str
    email: str | None = None
    phone: str | None = None
    location: str | None = None
    linkedin: str | None = None
    website: str | None = None


class ResumeExperience(_Base):
    company: str
    role: str
    start: str
    end: str | None = None
    location: str | None = None
    bullets: list[str] = Field(default_factory=list)


class ResumeEducation(_Base):
    school: str
    degree: str
    start: str | None = None
    end: str | None = None
    details: str | None = None


class ResumeProject(_Base):
    name: str
    description: str | None = None
    bullets: list[str] = Field(default_factory=list)
    link: str | None = None


class ResumeJSON(_Base):
    """Internal structured representation. Not returned directly from endpoints."""

    header: ResumeHeader
    summary: str | None = None
    experience: list[ResumeExperience] = Field(default_factory=list)
    education: list[ResumeEducation] = Field(default_factory=list)
    skills: list[str] = Field(default_factory=list)
    projects: list[ResumeProject] = Field(default_factory=list)


class Job(_Base):
    id: str
    title: str
    company: str
    location: str | None = None
    salary: str | None = None
    description: str
    source: str
    source_url: str
    discovered_at: datetime


class PipelineCard(_Base):
    id: str
    user_id: str
    job: Job
    category: PipelineCategory
    match_score: int = Field(ge=0, le=100)
    agent_action: str
    agent_justification: str
    matched_skills: list[str] = Field(default_factory=list)
    missing_skills: list[str] = Field(default_factory=list)
    why: str
    tailored_resume_id: str | None = None
    created_at: datetime
    status: PipelineStatus = "pending"


class Application(_Base):
    id: str
    job: Job
    resume_id: str
    pipeline_card_id: str | None = None
    status: ApplicationStatus
    submitted_at: datetime
    last_update_at: datetime
    next_step: str | None = None
    cover_letter: str | None = None


class ChatAttachment(_Base):
    id: str
    name: str


class ChatToolCall(_Base):
    tool: str
    args: dict = Field(default_factory=dict)
    result_summary: str | None = None


class ChatMessage(_Base):
    id: str
    sender: ChatSender
    text: str
    attachments: list[ChatAttachment] = Field(default_factory=list)
    tool_calls: list[ChatToolCall] = Field(default_factory=list)
    result_cards: list[str] = Field(default_factory=list)
    created_at: datetime


class TailoringJob(_Base):
    id: str
    status: TailoringStatus
    resume_id: str | None = None
    error: str | None = None
    created_at: datetime
    updated_at: datetime


class BriefProgress(_Base):
    current: int = 0
    total: int = 0


class Brief(_Base):
    id: str
    status: BriefStatus
    progress: BriefProgress = Field(default_factory=BriefProgress)
    card_count: int | None = None
    error: str | None = None
    created_at: datetime
    updated_at: datetime


class ErrorBody(_Base):
    type: ErrorType
    message: str
    status_code: int


class ErrorResponse(_Base):
    error: ErrorBody


class Page[T](_Base):
    data: list[T]
    next_cursor: str | None = None
