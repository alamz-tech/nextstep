"""Builds the shared objects (engine, repository, adapters) and applies engine results."""
from __future__ import annotations

import logging
import time
from dataclasses import dataclass

import yaml

from .config import Settings
from .copy_store import CopyStore
from .engine.checker import CheckScorer
from .engine.engine import Engine, Inbound, Result
from .engine.safety import SafetyRules
from .llm.base import make_llm
from .privacy import ReminderCipher, hash_id
from .retrieval.kb import KnowledgeBase
from .services import ServiceFinder
from .store.repo import make_repository
from .voice.base import make_voice

log = logging.getLogger("app")

DAY = 86400


def retention_text(hours: int) -> str:
    return f"{hours} hours" if hours < 48 else f"{hours // 24} days"


@dataclass
class Container:
    settings: Settings
    copy: CopyStore
    kb: KnowledgeBase
    engine: Engine
    repo: object
    cipher: ReminderCipher
    voice: object

    def uid(self, channel: str, raw_id: str) -> str:
        return hash_id(f"{channel}:{raw_id}", self.settings.hmac_secret)

    def process(self, channel: str, raw_id: str, inp: Inbound, recipient: str | None = None) -> Result:
        """Run one inbound event through the engine and persist the outcome."""
        uid = self.uid(channel, raw_id)
        state = self.repo.get_session(uid)
        res = self.engine.handle(state, inp)
        record = channel != "sim" or self.settings.sim_record_events
        if record:
            for ev, d1, d2 in res.events:
                try:
                    self.repo.log_event(ev, d1, d2)
                except ValueError as e:  # never let analytics break a reply
                    log.warning("event rejected: %s", e)
        for a in res.actions:
            t = a["type"]
            if t == "delete_user":
                self.repo.delete_user(uid)
            elif t in ("schedule_followups", "ensure_followup"):
                self._schedule(uid, channel, recipient, a, only_one=(t == "ensure_followup"))
            elif t == "cancel_followups":
                self.repo.cancel_reminders(uid)
        if res.delete:
            self.repo.delete_user(uid)
        elif res.state is not None:
            self.repo.save_session(uid, res.state)
        return res

    def _schedule(self, uid: str, channel: str, recipient: str | None, a: dict, only_one: bool) -> None:
        now = int(time.time())
        enc = None
        if channel == "whatsapp":
            if not self.cipher.available or not recipient:
                log.warning("reminder requested but REMINDER_ENCRYPTION_KEY not set; skipping")
                return
            enc = self.cipher.encrypt(recipient)
        kind_tier = f"|{a.get('tier') or ''}"
        if only_one:
            if not self.repo.pending_reminders(uid):
                self.repo.add_reminder(uid, channel, enc, a["lang"], now + 3 * DAY, "later" + kind_tier)
            return
        self.repo.cancel_reminders(uid)
        self.repo.add_reminder(uid, channel, enc, a["lang"], now + 3 * DAY, "day3" + kind_tier)
        self.repo.add_reminder(uid, channel, enc, a["lang"], now + 7 * DAY, "day7" + kind_tier)


def build(settings: Settings, repo=None) -> Container:
    contacts = settings.config_dir / "contacts.yaml"
    copy = CopyStore(settings.content_dir, contacts, retention_text(settings.session_ttl_hours))
    kb = KnowledgeBase(settings.content_dir / "kb", require_approved=not settings.demo_mode)
    scorer = CheckScorer(settings.content_dir / "check.yaml")
    finder = ServiceFinder(settings.services_csv, settings.demo_mode, settings.service_verified_max_age_days)
    rules = SafetyRules(settings.config_dir)
    llm = make_llm(settings)
    call_number = (yaml.safe_load(contacts.read_text(encoding="utf-8")) or {}).get("call_button_number") or ""
    engine = Engine(copy, kb, scorer, finder, rules, llm, demo_state=settings.demo_state,
                    compose_with_llm=settings.llm_compose_answers, llm_crisis=settings.llm_crisis_classifier,
                    call_number=str(call_number), demo_mode=settings.demo_mode)
    repo = repo or make_repository(settings.database_url)
    return Container(settings, copy, kb, engine, repo, ReminderCipher(settings.reminder_key), make_voice(settings))
