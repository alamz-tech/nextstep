"""Adapter for any OpenAI-compatible /chat/completions endpoint.

Use it to run NextStep on a self-hosted open model (e.g. vLLM, Ollama, llama.cpp
server) so there is no hard dependency on a closed model:

    LLM_PROVIDER=openai_compat
    OPENAI_COMPAT_BASE_URL=http://ollama:11434/v1
    OPENAI_COMPAT_MODEL=<model name>
"""
from __future__ import annotations

import logging

import httpx

log = logging.getLogger("app.llm")


class OpenAICompatLLM:
    name = "openai_compat"

    def __init__(self, settings):
        self.s = settings
        headers = {"Authorization": f"Bearer {settings.openai_api_key}"} if settings.openai_api_key else {}
        self.http = httpx.Client(base_url=settings.openai_base_url.rstrip("/"), timeout=settings.llm_timeout_s, headers=headers)

    def complete(self, system: str, user: str, max_tokens: int = 800, json_schema: dict | None = None) -> str | None:
        if not self.s.openai_model:
            log.warning("OPENAI_COMPAT_MODEL not set")
            return None
        body: dict = {
            "model": self.s.openai_model,
            "max_tokens": max_tokens,
            "temperature": 0,
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
        }
        if self.s.openai_reasoning_effort:
            body["reasoning_effort"] = self.s.openai_reasoning_effort
        if json_schema:
            body["response_format"] = {"type": "json_schema", "json_schema": {"name": "out", "schema": json_schema}}
        try:
            r = self.http.post("/chat/completions", json=body)
            if r.status_code == 400 and json_schema:
                body["response_format"] = {"type": "json_object"}  # older servers
                r = self.http.post("/chat/completions", json=body)
            r.raise_for_status()
            return r.json()["choices"][0]["message"]["content"]
        except (httpx.HTTPError, KeyError, IndexError, ValueError) as e:
            status = getattr(getattr(e, "response", None), "status_code", "")
            log.warning("openai_compat error %s %s; using deterministic fallback", type(e).__name__, status)
            return None
