"""Speech-to-text and text-to-speech behind adapters.

Default is `none`: voice notes get a polite "please type" reply and answers are
sent as text, and each fallback is logged as an aggregate `voice_fallback` event.

`openai_compat_http` talks to any self-hosted server exposing OpenAI-style
`/audio/transcriptions` and `/audio/speech` endpoints (for example a Whisper or
Meta MMS model behind a small wrapper). No paid third-party service is used.

Quality gate: TTS is only used for languages listed in VOICE_APPROVED_LANGS,
which should be set ONLY after scripts/eval_voice.py has been run and a native
speaker has listened to the samples. We never ship garbled audio.
"""
from __future__ import annotations

import logging
from typing import Protocol

import httpx

log = logging.getLogger("app.voice")

LANG_CODES = {"en": "en", "pcm": "pcm", "ha": "ha"}


class STT(Protocol):
    def transcribe(self, audio: bytes, mime: str, lang: str) -> str | None: ...


class TTS(Protocol):
    def synthesize(self, text: str, lang: str) -> bytes | None: ...


class NoVoice:
    name = "none"

    def transcribe(self, audio: bytes, mime: str, lang: str) -> str | None:
        return None

    def synthesize(self, text: str, lang: str) -> bytes | None:
        return None


class HttpVoice:
    """OpenAI-compatible audio endpoints on a self-hosted server."""

    name = "openai_compat_http"

    def __init__(self, base_url: str, api_key: str, stt_model: str, tts_model: str, use_stt: bool, use_tts: bool):
        headers = {"Authorization": f"Bearer {api_key}"} if api_key else {}
        self.http = httpx.Client(base_url=base_url.rstrip("/"), timeout=30, headers=headers)
        self.stt_model, self.tts_model = stt_model, tts_model
        self.use_stt, self.use_tts = use_stt, use_tts

    def transcribe(self, audio: bytes, mime: str, lang: str) -> str | None:
        if not self.use_stt:
            return None
        try:
            r = self.http.post("/audio/transcriptions", files={"file": ("voice.ogg", audio, mime)},
                               data={"model": self.stt_model, "language": LANG_CODES.get(lang, "en")})
            r.raise_for_status()
            return (r.json().get("text") or "").strip() or None
        except (httpx.HTTPError, ValueError) as e:
            log.warning("stt failed: %s", type(e).__name__)
            return None

    def synthesize(self, text: str, lang: str) -> bytes | None:
        if not self.use_tts or not self.tts_model:
            return None
        try:
            r = self.http.post("/audio/speech", json={"model": self.tts_model, "input": text[:1200],
                                                      "voice": lang, "response_format": "mp3"})
            r.raise_for_status()
            return r.content or None
        except httpx.HTTPError as e:
            log.warning("tts failed: %s", type(e).__name__)
            return None


class GatedVoice:
    """Wraps an adapter and enforces the per-language quality gate."""

    def __init__(self, inner, approved_langs: set[str], hausa_enabled: bool):
        self.inner = inner
        self.approved = set(approved_langs)
        if not hausa_enabled:
            self.approved.discard("ha")

    @property
    def name(self) -> str:
        return getattr(self.inner, "name", "none")

    def transcribe(self, audio: bytes, mime: str, lang: str) -> str | None:
        return self.inner.transcribe(audio, mime, lang)

    def synthesize(self, text: str, lang: str) -> bytes | None:
        if lang not in self.approved:
            return None
        return self.inner.synthesize(text, lang)

    def tts_enabled_for(self, lang: str) -> bool:
        return lang in self.approved and self.name != "none"


def make_voice(settings) -> GatedVoice:
    use_stt = settings.stt_provider == "openai_compat_http"
    use_tts = settings.tts_provider == "openai_compat_http"
    inner = HttpVoice(settings.voice_base_url, settings.voice_api_key, settings.stt_model, settings.tts_model,
                      use_stt, use_tts) if (use_stt or use_tts) else NoVoice()
    return GatedVoice(inner, settings.approved_voice_langs, settings.feature_hausa)
