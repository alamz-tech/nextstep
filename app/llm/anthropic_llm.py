"""Anthropic adapter (default when LLM_PROVIDER=anthropic). Model from ANTHROPIC_MODEL."""
from __future__ import annotations

import logging

import anthropic

log = logging.getLogger("app.llm")


class AnthropicLLM:
    name = "anthropic"

    def __init__(self, settings):
        self.s = settings
        # Credentials resolve from ANTHROPIC_API_KEY (or an `ant auth login` profile).
        self.client = anthropic.Anthropic(timeout=settings.llm_timeout_s, max_retries=1)

    def complete(self, system: str, user: str, max_tokens: int = 800, json_schema: dict | None = None) -> str | None:
        output_config: dict = {"effort": self.s.anthropic_effort}
        if json_schema:
            output_config["format"] = {"type": "json_schema", "schema": json_schema}
        kwargs: dict = dict(
            model=self.s.anthropic_model,
            max_tokens=max_tokens,
            system=system,
            messages=[{"role": "user", "content": user}],
            output_config=output_config,
        )
        try:
            if self.s.anthropic_fallbacks:
                # Server-side refusal fallback: Anthropic re-runs a declined request on
                # its recommended fallback model. Disable with ANTHROPIC_FALLBACKS=false.
                resp = self.client.beta.messages.create(
                    betas=["server-side-fallback-2026-07-01"], fallbacks="default", **kwargs
                )
            else:
                resp = self.client.messages.create(**kwargs)
        except anthropic.RateLimitError:
            log.warning("llm rate limited; using deterministic fallback")
            return None
        except anthropic.APIStatusError as e:
            log.warning("llm api error status=%s; using deterministic fallback", e.status_code)
            return None
        except anthropic.APIConnectionError:
            log.warning("llm connection error; using deterministic fallback")
            return None
        if resp.stop_reason in ("refusal", "max_tokens"):
            log.warning("llm stop_reason=%s; using deterministic fallback", resp.stop_reason)
            return None
        text = "".join(b.text for b in resp.content if getattr(b, "type", "") == "text")
        return text or None
