"""Anthropic client wrapper. Used by A (parser/tailor) and B (matcher/chat).

Per docs/api-contract.md §5:
- Haiku → resume parsing, job matching (cheap, called 20+ times per brief)
- Strong (Opus/Sonnet, env-controlled) → resume tailoring
- Opus + tools → agent chat reasoning
"""

from __future__ import annotations

import asyncio
import logging
import random
from typing import Any

from anthropic import APIStatusError, AsyncAnthropic
from anthropic.types import Message

from app.config import settings

log = logging.getLogger("syncra.llm")

_RETRY_STATUS = {429, 529}
_MAX_RETRIES = 4


class LLM:
    def __init__(self, client: AsyncAnthropic) -> None:
        self._client = client

    async def haiku(
        self,
        messages: list[dict[str, Any]],
        *,
        system: str | None = None,
        max_tokens: int = 2048,
        **kwargs: Any,
    ) -> Message:
        return await self._call(settings.llm_model_cheap, messages, system, max_tokens, **kwargs)

    async def strong(
        self,
        messages: list[dict[str, Any]],
        *,
        system: str | None = None,
        max_tokens: int = 4096,
        **kwargs: Any,
    ) -> Message:
        return await self._call(settings.llm_model_strong, messages, system, max_tokens, **kwargs)

    async def opus_with_tools(
        self,
        messages: list[dict[str, Any]],
        tools: list[dict[str, Any]],
        *,
        system: str | None = None,
        max_tokens: int = 4096,
        **kwargs: Any,
    ) -> Message:
        return await self._call(
            settings.llm_model_strong,
            messages,
            system,
            max_tokens,
            tools=tools,
            **kwargs,
        )

    async def _call(
        self,
        model: str,
        messages: list[dict[str, Any]],
        system: str | None,
        max_tokens: int,
        **kwargs: Any,
    ) -> Message:
        payload: dict[str, Any] = {
            "model": model,
            "messages": messages,
            "max_tokens": max_tokens,
            **kwargs,
        }
        if system is not None:
            payload["system"] = system

        for attempt in range(_MAX_RETRIES + 1):
            try:
                msg = await self._client.messages.create(**payload)
                log.info(
                    "llm.ok model=%s in=%d out=%d",
                    model,
                    msg.usage.input_tokens,
                    msg.usage.output_tokens,
                )
                return msg
            except APIStatusError as e:
                if e.status_code in _RETRY_STATUS and attempt < _MAX_RETRIES:
                    delay = (2**attempt) + random.random()
                    log.warning("llm.retry status=%s attempt=%d sleep=%.2fs", e.status_code, attempt, delay)
                    await asyncio.sleep(delay)
                    continue
                raise

        raise RuntimeError("unreachable")  # for type-checkers


llm = LLM(AsyncAnthropic(api_key=settings.anthropic_api_key))
