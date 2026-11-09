"""LLM provider abstraction.

The engine only ever asks an LLM to (1) classify a message and (2) compose an
answer from already-retrieved, reviewed chunks. Every call can fail or be
disabled; the engine then falls back to deterministic behaviour.
"""
from __future__ import annotations

import json
import logging
import re
from typing import Protocol

log = logging.getLogger("app.llm")


class LLM(Protocol):
    name: str

    def complete(self, system: str, user: str, max_tokens: int = 800, json_schema: dict | None = None) -> str | None:
        """Return the model's text, or None on any error/refusal."""


class NoLLM:
    name = "none"

    def complete(self, system: str, user: str, max_tokens: int = 800, json_schema: dict | None = None) -> str | None:
        return None


def parse_json(text: str | None) -> dict | None:
    if not text:
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        m = re.search(r"\{.*\}", text, re.S)
        if m:
            try:
                return json.loads(m.group(0))
            except json.JSONDecodeError:
                return None
    return None


def make_llm(settings) -> LLM:
    p = settings.llm_provider.lower()
    if p == "anthropic":
        from .anthropic_llm import AnthropicLLM
        return AnthropicLLM(settings)
    if p in ("openai_compat", "openai-compatible", "openai"):
        from .openai_compat import OpenAICompatLLM
        return OpenAICompatLLM(settings)
    return NoLLM()
