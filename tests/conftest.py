import os
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
os.environ.setdefault("DATABASE_URL", "sqlite://:memory:")
os.environ.setdefault("LLM_PROVIDER", "none")
os.environ.setdefault("SCHEDULER_ENABLED", "false")

from app.config import Settings  # noqa: E402
from app.container import build  # noqa: E402
from app.engine.engine import Inbound  # noqa: E402
from app.store.repo import SQLiteRepository  # noqa: E402


@pytest.fixture
def settings(monkeypatch):
    monkeypatch.setenv("DATABASE_URL", "sqlite://:memory:")
    monkeypatch.setenv("LLM_PROVIDER", "none")
    monkeypatch.setenv("HMAC_SECRET", "test-secret-value")
    monkeypatch.setenv("SCHEDULER_ENABLED", "false")
    return Settings()


@pytest.fixture
def container(settings):
    return build(settings, SQLiteRepository(":memory:"))


SETUP_STEPS = {
    "fresh": [],
    "consent": [("text", "Hi")],
    "age": [("text", "Hi"), ("button", "consent_agree")],
    "menu": [("text", "Hi"), ("button", "consent_agree"), ("button", "TIER")],
    "qa": [("text", "Hi"), ("button", "consent_agree"), ("button", "TIER"), ("button", "menu_ask")],
    "check": [("text", "Hi"), ("button", "consent_agree"), ("button", "TIER"), ("button", "check_start")],
    "loc": [("text", "Hi"), ("button", "consent_agree"), ("button", "TIER"), ("button", "menu_find")],
}


def drive(container, uid, setup="menu", tier="18_24", lang="en"):
    """Bring a test user to a given state."""
    for kind, val in SETUP_STEPS[setup]:
        if val == "TIER":
            val = "age_15_17" if tier == "15_17" else "age_18_24"
        if kind == "text":
            container.process("sim", uid, Inbound("text", text=val))
        else:
            container.process("sim", uid, Inbound("button", button=val))
        if lang != "en" and setup != "fresh":
            st = container.repo.get_session(container.uid("sim", uid))
            if st:
                st["lang"] = lang
                container.repo.save_session(container.uid("sim", uid), st)
