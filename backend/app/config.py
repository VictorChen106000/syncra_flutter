"""App settings loaded from .env. Source of truth: docs/api-contract.md §1, §5."""

from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    env: Literal["dev", "staging", "prod"] = "dev"

    firebase_credentials_path: str

    anthropic_api_key: str
    rapidapi_key: str
    jsearch_host: str = "jsearch.p.rapidapi.com"

    llm_model_cheap: str = "claude-haiku-4-5"
    llm_model_strong: str = "claude-opus-4-7"

    allowed_origins: str = "http://localhost:*"

    api_prefix: str = "/api/v1"
    version: str = "0.1.0"

    rate_limit_upload_daily: int = 20
    rate_limit_tailor_daily: int = 20
    rate_limit_brief_daily: int = 12
    rate_limit_chat_daily: int = 30

    resume_max_bytes: int = Field(default=5 * 1024 * 1024)

    @property
    def cors_origins(self) -> list[str]:
        return [o.strip() for o in self.allowed_origins.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]


settings = get_settings()
