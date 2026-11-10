"""Runtime configuration, read once from environment variables.

Every setting has a safe default so the web demo runs with no credentials at all.
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _bool(name: str, default: bool) -> bool:
    v = os.environ.get(name)
    if v is None or v == "":
        return default
    return v.strip().lower() in {"1", "true", "yes", "on"}


def _int(name: str, default: int) -> int:
    v = os.environ.get(name)
    return int(v) if v not in (None, "") else default


def _str(name: str, default: str = "") -> str:
    return os.environ.get(name, default) or default


@dataclass
class Settings:
    # --- general ---
    demo_mode: bool = field(default_factory=lambda: _bool("DEMO_MODE", True))
    demo_state: str = field(default_factory=lambda: _str("DEMO_STATE", "Lagos"))
    database_url: str = field(default_factory=lambda: _str("DATABASE_URL", f"sqlite:///{ROOT / 'data' / 'nextstep.db'}"))
    content_dir: Path = field(default_factory=lambda: Path(_str("CONTENT_DIR", str(ROOT / "content"))))
    config_dir: Path = field(default_factory=lambda: Path(_str("CONFIG_DIR", str(ROOT / "config"))))
    services_csv: Path = field(default_factory=lambda: Path(_str("SERVICES_CSV", str(ROOT / "data" / "services.csv"))))

    # --- privacy ---
    # Secret used to HMAC phone numbers / session ids. MUST be set in production.
    hmac_secret: str = field(default_factory=lambda: _str("HMAC_SECRET", "dev-only-insecure-secret-change-me"))
    # Fernet key used ONLY to encrypt the WhatsApp recipient of an opted-in reminder.
    reminder_key: str = field(default_factory=lambda: _str("REMINDER_ENCRYPTION_KEY", ""))
    session_ttl_hours: int = field(default_factory=lambda: _int("SESSION_TTL_HOURS", 24))
    events_retention_days: int = field(default_factory=lambda: _int("EVENTS_RETENTION_DAYS", 365))
    service_verified_max_age_days: int = field(default_factory=lambda: _int("SERVICE_VERIFIED_MAX_AGE_DAYS", 90))

    # --- LLM ---
    llm_provider: str = field(default_factory=lambda: _str("LLM_PROVIDER", "none"))  # none | anthropic | openai_compat
    anthropic_model: str = field(default_factory=lambda: _str("ANTHROPIC_MODEL", "claude-opus-5-5"))
    anthropic_effort: str = field(default_factory=lambda: _str("ANTHROPIC_EFFORT", "low"))
    anthropic_fallbacks: bool = field(default_factory=lambda: _bool("ANTHROPIC_FALLBACKS", True))
    openai_base_url: str = field(default_factory=lambda: _str("OPENAI_COMPAT_BASE_URL", "http://localhost:11434/v1"))
    openai_model: str = field(default_factory=lambda: _str("OPENAI_COMPAT_MODEL", ""))
    openai_api_key: str = field(default_factory=lambda: _str("OPENAI_COMPAT_API_KEY", ""))
    # Reasoning models (e.g. gpt-oss on Groq): "low" uses far fewer tokens per call. Empty = not sent.
    openai_reasoning_effort: str = field(default_factory=lambda: _str("OPENAI_COMPAT_REASONING_EFFORT", ""))
    llm_timeout_s: float = field(default_factory=lambda: float(_str("LLM_TIMEOUT_S", "20")))
    # When false, Q&A always returns the approved chunk text verbatim (safest).
    llm_compose_answers: bool = field(default_factory=lambda: _bool("LLM_COMPOSE_ANSWERS", True))
    llm_crisis_classifier: bool = field(default_factory=lambda: _bool("LLM_CRISIS_CLASSIFIER", True))
    # Facilitator question box: let the LLM group questions BM25 can't place (keyword grouping is the fallback).
    llm_group_questions: bool = field(default_factory=lambda: _bool("LLM_GROUP_QUESTIONS", True))

    # --- voice ---
    stt_provider: str = field(default_factory=lambda: _str("STT_PROVIDER", "none"))  # none | openai_compat_http
    tts_provider: str = field(default_factory=lambda: _str("TTS_PROVIDER", "none"))
    voice_base_url: str = field(default_factory=lambda: _str("VOICE_BASE_URL", "http://localhost:8000/v1"))
    voice_api_key: str = field(default_factory=lambda: _str("VOICE_API_KEY", ""))
    stt_model: str = field(default_factory=lambda: _str("STT_MODEL", "Systran/faster-whisper-small"))
    tts_model: str = field(default_factory=lambda: _str("TTS_MODEL", ""))
    # Languages whose voice output has PASSED the quality evaluation. Empty = text only.
    voice_approved_langs: str = field(default_factory=lambda: _str("VOICE_APPROVED_LANGS", ""))
    feature_hausa: bool = field(default_factory=lambda: _bool("FEATURE_HAUSA", False))

    # --- WhatsApp Cloud API ---
    wa_verify_token: str = field(default_factory=lambda: _str("WHATSAPP_VERIFY_TOKEN", ""))
    wa_app_secret: str = field(default_factory=lambda: _str("WHATSAPP_APP_SECRET", ""))
    wa_access_token: str = field(default_factory=lambda: _str("WHATSAPP_ACCESS_TOKEN", ""))
    wa_phone_number_id: str = field(default_factory=lambda: _str("WHATSAPP_PHONE_NUMBER_ID", ""))
    wa_graph_version: str = field(default_factory=lambda: _str("WHATSAPP_GRAPH_VERSION", "v21.0"))

    # --- dashboard ---
    dashboard_user: str = field(default_factory=lambda: _str("DASHBOARD_USER", "admin"))
    dashboard_password: str = field(default_factory=lambda: _str("DASHBOARD_PASSWORD", ""))
    dashboard_sample_badge: bool = field(default_factory=lambda: _bool("DASHBOARD_SAMPLE_BADGE", True))
    pilot_start_date: str = field(default_factory=lambda: _str("PILOT_START_DATE", ""))

    # --- channels ---
    # WhatsApp is a possible FUTURE channel only, off by default. Meta's WhatsApp Business
    # policy bans general-purpose AI chatbots: if ever enabled it must stay a structured service.
    feature_whatsapp: bool = field(default_factory=lambda: _bool("FEATURE_WHATSAPP", False))

    # --- app API ---
    public_repo_url: str = field(default_factory=lambda: _str("PUBLIC_REPO_URL", "https://github.com/alamz-tech/nextstep"))
    public_base_url: str = field(default_factory=lambda: _str("PUBLIC_BASE_URL", "http://localhost:8077"))
    token_secret: str = field(default_factory=lambda: _str("TOKEN_SECRET", ""))
    token_ttl_hours: int = field(default_factory=lambda: _int("TOKEN_TTL_HOURS", 12))
    bootstrap_admin_user: str = field(default_factory=lambda: _str("PLATFORM_ADMIN_USER", ""))
    bootstrap_admin_password: str = field(default_factory=lambda: _str("PLATFORM_ADMIN_PASSWORD", ""))
    rate_limit_per_min: int = field(default_factory=lambda: _int("RATE_LIMIT_PER_MIN", 30))
    rate_limit_ask_per_min: int = field(default_factory=lambda: _int("RATE_LIMIT_ASK_PER_MIN", 10))
    rate_limit_box_per_min: int = field(default_factory=lambda: _int("RATE_LIMIT_BOX_PER_MIN", 6))
    question_ttl_hours: int = field(default_factory=lambda: _int("QUESTION_TTL_HOURS", 48))
    referral_ttl_days: int = field(default_factory=lambda: _int("REFERRAL_TTL_DAYS", 90))
    audio_cache_seconds: int = field(default_factory=lambda: _int("AUDIO_CACHE_SECONDS", 600))
    web_app_dir: Path = field(default_factory=lambda: Path(_str("WEB_APP_DIR", str(ROOT / "app_flutter" / "build" / "web"))))

    # --- simulator (testing tool only; replaced by the Flutter web build) ---
    sim_enabled: bool = field(default_factory=lambda: _bool("SIM_ENABLED", False))
    sim_record_events: bool = field(default_factory=lambda: _bool("SIM_RECORD_EVENTS", True))

    # --- follow-up scheduler ---
    scheduler_enabled: bool = field(default_factory=lambda: _bool("SCHEDULER_ENABLED", True))
    scheduler_interval_s: int = field(default_factory=lambda: _int("SCHEDULER_INTERVAL_S", 60))

    @property
    def sqlite_path(self) -> str:
        if not self.database_url.startswith("sqlite:///"):
            raise ValueError("Only sqlite:/// URLs are implemented; add a Postgres repository for others.")
        return self.database_url[len("sqlite:///"):]

    @property
    def approved_voice_langs(self) -> set[str]:
        return {x.strip() for x in self.voice_approved_langs.split(",") if x.strip()}

    def is_insecure_secret(self) -> bool:
        return self.hmac_secret.startswith("dev-only")

    @property
    def signing_secret(self) -> str:
        return self.token_secret or ("tok:" + self.hmac_secret)


_settings: Settings | None = None


def get_settings() -> Settings:
    global _settings
    if _settings is None:
        _settings = Settings()
    return _settings


def reset_settings() -> None:
    """Test helper: re-read environment."""
    global _settings
    _settings = None
