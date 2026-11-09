"""Persistence behind a repository interface (SQLite now; Postgres later).

What is stored, and why:
  * events      – aggregate daily counts with category dimensions only. No user ids.
  * referrals   – referral code, service, state/tier/lang, linked to an install-ID HMAC
                  so "delete my data" can remove it. No names, no phone numbers.
  * accounts    – facilitator / org admin / clinic partner / platform admin logins.
  * orgs        – organisations that own accounts.
  * fsessions   – facilitator sessions (setting, date, age band, approx size, join code).
  * questions   – anonymous question-box text, REDACTED (names/numbers stripped) and
                  deleted when the session is closed or after QUESTION_TTL_HOURS.
  * themes      – per-session theme counts and answered flags (kept for reports).
  * sessions / reminders – only used by the optional WhatsApp channel (off by default).

No learner message text is ever written. Ask questions are processed in memory.
"""
from __future__ import annotations

import json
import os
import secrets
import sqlite3
import threading
import time
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from typing import Any

SCHEMA = """
CREATE TABLE IF NOT EXISTS sessions (uid TEXT PRIMARY KEY, state_json TEXT NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS reminders (
  id INTEGER PRIMARY KEY AUTOINCREMENT, uid TEXT NOT NULL, channel TEXT NOT NULL, recipient_enc TEXT,
  lang TEXT NOT NULL, due_at INTEGER NOT NULL, kind TEXT NOT NULL, sent INTEGER NOT NULL DEFAULT 0);
CREATE INDEX IF NOT EXISTS reminders_due ON reminders(sent, due_at);
CREATE TABLE IF NOT EXISTS events (
  day TEXT NOT NULL, event TEXT NOT NULL,
  dim1 TEXT NOT NULL DEFAULT '', dim2 TEXT NOT NULL DEFAULT '',
  state TEXT NOT NULL DEFAULT '', tier TEXT NOT NULL DEFAULT '', lang TEXT NOT NULL DEFAULT '',
  setting TEXT NOT NULL DEFAULT '', org TEXT NOT NULL DEFAULT '',
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, event, dim1, dim2, state, tier, lang, setting, org));
CREATE TABLE IF NOT EXISTS referrals (
  code TEXT PRIMARY KEY, install_hash TEXT NOT NULL, service_id TEXT NOT NULL, state TEXT NOT NULL,
  tier TEXT NOT NULL, lang TEXT NOT NULL, setting TEXT NOT NULL DEFAULT '', created_day TEXT NOT NULL,
  expires_at INTEGER NOT NULL, confirmed_day TEXT, confirmed_org TEXT);
CREATE INDEX IF NOT EXISTS referrals_install ON referrals(install_hash);
CREATE TABLE IF NOT EXISTS orgs (id TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL, state TEXT NOT NULL DEFAULT '');
CREATE TABLE IF NOT EXISTS accounts (
  id TEXT PRIMARY KEY, username TEXT UNIQUE NOT NULL, pw_hash TEXT NOT NULL, role TEXT NOT NULL,
  org_id TEXT, active INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS fsessions (
  id TEXT PRIMARY KEY, org_id TEXT NOT NULL, facilitator_id TEXT NOT NULL, setting TEXT NOT NULL,
  session_date TEXT NOT NULL, age_band TEXT NOT NULL, audience_size INTEGER NOT NULL, state TEXT NOT NULL DEFAULT '',
  lang TEXT NOT NULL DEFAULT 'en', join_code TEXT UNIQUE NOT NULL, status TEXT NOT NULL DEFAULT 'open',
  created_at INTEGER NOT NULL, closed_at INTEGER,
  joins INTEGER NOT NULL DEFAULT 0, submitted INTEGER NOT NULL DEFAULT 0, flagged INTEGER NOT NULL DEFAULT 0,
  filtered INTEGER NOT NULL DEFAULT 0, referral_cards INTEGER NOT NULL DEFAULT 0,
  checklist_json TEXT NOT NULL DEFAULT '{}');
CREATE TABLE IF NOT EXISTS questions (
  id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL, text_redacted TEXT NOT NULL,
  theme_key TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS questions_session ON questions(session_id);
CREATE TABLE IF NOT EXISTS themes (
  session_id TEXT NOT NULL, theme_key TEXT NOT NULL, label TEXT NOT NULL, count INTEGER NOT NULL DEFAULT 0,
  answered INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (session_id, theme_key));
"""

ALLOWED_EVENTS = {
    # learner app
    "app_open", "consent_given", "age_tier_selected", "question_asked", "check_started", "check_completed",
    "referral_issued", "visit_self_reported", "visit_not_yet", "followup_help", "barrier_reported",
    "crisis_escalation", "out_of_scope", "voice_fallback", "data_deleted", "reminder_opt_in",
    # clinic
    "visit_confirmed_clinic",
    # facilitator
    "session_created", "session_joined", "box_question", "box_flagged", "box_filtered", "theme_answered",
    "kit_opened",
    # legacy chat channel (WhatsApp / simulator)
    "conversation_started", "referral_given", "visit_confirmed",
}
_DIM_OK = set("abcdefghijklmnopqrstuvwxyz0123456789_-")
CODE_ALPHABET = "ACDEFGHJKMNPQRTUVWXY34679"  # no 0/O, 1/I/L, 2/Z, 5/S, 8/B


def _clean(v: str | None) -> str:
    v = (v or "").lower()[:40]
    if not set(v) <= _DIM_OK:
        raise ValueError("event dimensions must be short category slugs")
    return v


def today() -> str:
    return datetime.now(timezone.utc).date().isoformat()


def new_code(n: int = 6) -> str:
    return "".join(secrets.choice(CODE_ALPHABET) for _ in range(n))


@dataclass
class Reminder:
    id: int
    uid: str
    channel: str
    recipient_enc: str | None
    lang: str
    due_at: int
    kind: str


class SQLiteRepository:
    def __init__(self, path: str):
        if path != ":memory:":
            os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        self._db = sqlite3.connect(path, check_same_thread=False, isolation_level=None)
        self._db.row_factory = sqlite3.Row
        if path != ":memory:":
            self._db.execute("PRAGMA journal_mode=WAL")
        self._migrate()
        self._db.executescript(SCHEMA)
        self._lock = threading.Lock()

    def _migrate(self) -> None:
        cols = [r[1] for r in self._db.execute("PRAGMA table_info(events)").fetchall()]
        if cols and "state" not in cols:  # prototype schema v0 -> v1: events gained dimensions
            self._db.execute("ALTER TABLE events RENAME TO events_v0")

    def _x(self, sql: str, args: tuple = ()) -> sqlite3.Cursor:
        with self._lock:
            return self._db.execute(sql, args)

    # ------------------------------------------------ events
    def log_event(self, event: str, dim1: str = "", dim2: str = "", day: date | None = None, n: int = 1, *,
                  state: str = "", tier: str = "", lang: str = "", setting: str = "", org: str = "") -> None:
        if event not in ALLOWED_EVENTS:
            raise ValueError(f"unknown event {event!r}")
        d = (day or datetime.now(timezone.utc).date()).isoformat()
        vals = (d, event, _clean(dim1), _clean(dim2), _clean(state), _clean(tier), _clean(lang), _clean(setting), _clean(org), n)
        self._x("INSERT INTO events(day,event,dim1,dim2,state,tier,lang,setting,org,count) VALUES(?,?,?,?,?,?,?,?,?,?) "
                "ON CONFLICT(day,event,dim1,dim2,state,tier,lang,setting,org) DO UPDATE SET count=count+excluded.count", vals)

    def event_rows(self, since: date | None = None) -> list[dict]:
        q = "SELECT day,event,dim1,dim2,state,tier,lang,setting,org,count FROM events"
        rows = self._x(q + " WHERE day>=?", (since.isoformat(),)) if since else self._x(q)
        return [dict(r) for r in rows.fetchall()]

    # ------------------------------------------------ referrals
    def create_referral(self, install_hash: str, service_id: str, state: str, tier: str, lang: str,
                        setting: str = "", ttl_days: int = 90) -> str:
        for _ in range(20):
            code = new_code()
            try:
                self._x("INSERT INTO referrals(code,install_hash,service_id,state,tier,lang,setting,created_day,expires_at) "
                        "VALUES(?,?,?,?,?,?,?,?,?)", (code, install_hash, service_id, state, tier, lang, setting, today(),
                                                      int(time.time()) + ttl_days * 86400))
                return code
            except sqlite3.IntegrityError:
                continue
        raise RuntimeError("could not allocate referral code")

    def get_referral(self, code: str) -> dict | None:
        r = self._x("SELECT * FROM referrals WHERE code=?", (code.upper().strip(),)).fetchone()
        return dict(r) if r else None

    def confirm_referral(self, code: str, org_id: str) -> bool:
        cur = self._x("UPDATE referrals SET confirmed_day=?, confirmed_org=? WHERE code=? AND confirmed_day IS NULL AND expires_at>?",
                      (today(), org_id, code.upper().strip(), int(time.time())))
        return cur.rowcount == 1

    def referrals_for_install(self, install_hash: str) -> list[dict]:
        return [dict(r) for r in self._x("SELECT code,service_id,created_day,confirmed_day FROM referrals WHERE install_hash=?",
                                         (install_hash,)).fetchall()]

    def delete_install(self, install_hash: str) -> int:
        return self._x("DELETE FROM referrals WHERE install_hash=?", (install_hash,)).rowcount

    # ------------------------------------------------ orgs & accounts
    def create_org(self, name: str, kind: str, state: str = "") -> str:
        oid = "org_" + secrets.token_hex(6)
        self._x("INSERT INTO orgs(id,name,kind,state) VALUES(?,?,?,?)", (oid, name, kind, state))
        return oid

    def get_org(self, oid: str) -> dict | None:
        r = self._x("SELECT * FROM orgs WHERE id=?", (oid,)).fetchone()
        return dict(r) if r else None

    def list_orgs(self) -> list[dict]:
        return [dict(r) for r in self._x("SELECT * FROM orgs ORDER BY name").fetchall()]

    def create_account(self, username: str, pw_hash: str, role: str, org_id: str | None) -> str:
        aid = "acc_" + secrets.token_hex(6)
        self._x("INSERT INTO accounts(id,username,pw_hash,role,org_id,created_at) VALUES(?,?,?,?,?,?)",
                (aid, username.lower().strip(), pw_hash, role, org_id, int(time.time())))
        return aid

    def get_account_by_username(self, username: str) -> dict | None:
        r = self._x("SELECT * FROM accounts WHERE username=?", (username.lower().strip(),)).fetchone()
        return dict(r) if r else None

    def get_account(self, aid: str) -> dict | None:
        r = self._x("SELECT * FROM accounts WHERE id=?", (aid,)).fetchone()
        return dict(r) if r else None

    def list_accounts(self, org_id: str | None) -> list[dict]:
        q = "SELECT id,username,role,org_id,active FROM accounts"
        rows = self._x(q + " WHERE org_id=? ORDER BY username", (org_id,)) if org_id else self._x(q + " ORDER BY username")
        return [dict(r) for r in rows.fetchall()]

    def set_account_active(self, aid: str, active: bool) -> None:
        self._x("UPDATE accounts SET active=? WHERE id=?", (1 if active else 0, aid))

    # ------------------------------------------------ facilitator sessions
    def create_fsession(self, org_id: str, facilitator_id: str, setting: str, session_date: str, age_band: str,
                        audience_size: int, state: str, lang: str) -> dict:
        sid = "ses_" + secrets.token_hex(6)
        for _ in range(20):
            code = new_code(6)
            try:
                self._x("INSERT INTO fsessions(id,org_id,facilitator_id,setting,session_date,age_band,audience_size,state,lang,join_code,created_at) "
                        "VALUES(?,?,?,?,?,?,?,?,?,?,?)", (sid, org_id, facilitator_id, setting, session_date, age_band,
                                                          audience_size, state, lang, code, int(time.time())))
                return self.get_fsession(sid)
            except sqlite3.IntegrityError:
                continue
        raise RuntimeError("could not allocate join code")

    def get_fsession(self, sid: str) -> dict | None:
        r = self._x("SELECT * FROM fsessions WHERE id=?", (sid,)).fetchone()
        return dict(r) if r else None

    def get_fsession_by_code(self, code: str) -> dict | None:
        r = self._x("SELECT * FROM fsessions WHERE join_code=?", (code.upper().strip(),)).fetchone()
        return dict(r) if r else None

    def list_fsessions(self, *, facilitator_id: str | None = None, org_id: str | None = None) -> list[dict]:
        if facilitator_id:
            rows = self._x("SELECT * FROM fsessions WHERE facilitator_id=? ORDER BY created_at DESC", (facilitator_id,))
        elif org_id:
            rows = self._x("SELECT * FROM fsessions WHERE org_id=? ORDER BY created_at DESC", (org_id,))
        else:
            rows = self._x("SELECT * FROM fsessions ORDER BY created_at DESC")
        return [dict(r) for r in rows.fetchall()]

    def bump_fsession(self, sid: str, field: str, n: int = 1) -> None:
        assert field in {"joins", "submitted", "flagged", "filtered", "referral_cards"}
        self._x(f"UPDATE fsessions SET {field}={field}+? WHERE id=?", (n, sid))

    def set_checklist(self, sid: str, checklist: dict) -> None:
        self._x("UPDATE fsessions SET checklist_json=? WHERE id=?", (json.dumps(checklist), sid))

    def close_fsession(self, sid: str) -> None:
        self._x("UPDATE fsessions SET status='closed', closed_at=? WHERE id=?", (int(time.time()), sid))
        # Raw (redacted) question text is deleted as soon as the session closes.
        self._x("DELETE FROM questions WHERE session_id=?", (sid,))

    # ------------------------------------------------ question box
    def add_question(self, sid: str, text_redacted: str, theme_key: str, label: str) -> None:
        self._x("INSERT INTO questions(session_id,text_redacted,theme_key,created_at) VALUES(?,?,?,?)",
                (sid, text_redacted, theme_key, int(time.time())))
        self._x("INSERT INTO themes(session_id,theme_key,label,count) VALUES(?,?,?,1) "
                "ON CONFLICT(session_id,theme_key) DO UPDATE SET count=count+1", (sid, theme_key, label))

    def session_questions(self, sid: str) -> list[dict]:
        return [dict(r) for r in self._x("SELECT id,text_redacted,theme_key FROM questions WHERE session_id=?", (sid,)).fetchall()]

    def set_question_theme(self, qid: int, theme_key: str) -> None:
        self._x("UPDATE questions SET theme_key=? WHERE id=?", (theme_key, qid))

    def replace_themes(self, sid: str, themes: list[tuple[str, str, int]]) -> None:
        answered = {r["theme_key"] for r in self._x("SELECT theme_key FROM themes WHERE session_id=? AND answered=1", (sid,)).fetchall()}
        self._x("DELETE FROM themes WHERE session_id=?", (sid,))
        for key, label, count in themes:
            self._x("INSERT INTO themes(session_id,theme_key,label,count,answered) VALUES(?,?,?,?,?)",
                    (sid, key, label, count, 1 if key in answered else 0))

    def session_themes(self, sid: str) -> list[dict]:
        return [dict(r) for r in self._x("SELECT theme_key,label,count,answered FROM themes WHERE session_id=? ORDER BY count DESC, label",
                                         (sid,)).fetchall()]

    def mark_theme(self, sid: str, key: str, answered: bool) -> bool:
        return self._x("UPDATE themes SET answered=? WHERE session_id=? AND theme_key=?", (1 if answered else 0, sid, key)).rowcount == 1

    # ------------------------------------------------ WhatsApp-only state (feature-flagged channel)
    def get_session(self, uid: str) -> dict[str, Any] | None:
        row = self._x("SELECT state_json FROM sessions WHERE uid=?", (uid,)).fetchone()
        return json.loads(row[0]) if row else None

    def save_session(self, uid: str, state: dict[str, Any]) -> None:
        self._x("INSERT INTO sessions(uid,state_json,updated_at) VALUES(?,?,?) ON CONFLICT(uid) DO UPDATE SET "
                "state_json=excluded.state_json, updated_at=excluded.updated_at", (uid, json.dumps(state), int(time.time())))

    def delete_user(self, uid: str) -> None:
        self._x("DELETE FROM sessions WHERE uid=?", (uid,))
        self._x("DELETE FROM reminders WHERE uid=?", (uid,))

    def add_reminder(self, uid, channel, recipient_enc, lang, due_at, kind) -> None:
        self._x("INSERT INTO reminders(uid,channel,recipient_enc,lang,due_at,kind) VALUES(?,?,?,?,?,?)",
                (uid, channel, recipient_enc, lang, due_at, kind))

    def _rem(self, rows) -> list[Reminder]:
        return [Reminder(*tuple(r)) for r in rows]

    def due_reminders(self, now: int, channel: str | None = None) -> list[Reminder]:
        q = "SELECT id,uid,channel,recipient_enc,lang,due_at,kind FROM reminders WHERE sent=0 AND due_at<=?"
        args: tuple = (now,)
        if channel:
            q += " AND channel=?"
            args += (channel,)
        return self._rem(self._x(q + " ORDER BY due_at", args).fetchall())

    def pending_reminders(self, uid: str) -> list[Reminder]:
        return self._rem(self._x("SELECT id,uid,channel,recipient_enc,lang,due_at,kind FROM reminders WHERE sent=0 AND uid=? ORDER BY due_at",
                                 (uid,)).fetchall())

    def mark_reminder_sent(self, rid: int) -> None:
        self._x("UPDATE reminders SET sent=1, recipient_enc=NULL WHERE id=?", (rid,))

    def cancel_reminders(self, uid: str) -> None:
        self._x("DELETE FROM reminders WHERE uid=?", (uid,))

    # ------------------------------------------------ retention
    def purge_expired(self, session_ttl_s: int, events_retention_days: int, now: int | None = None,
                      question_ttl_s: int = 48 * 3600) -> dict[str, int]:
        now = now or int(time.time())
        out = {
            "sessions": self._x("DELETE FROM sessions WHERE updated_at < ?", (now - session_ttl_s,)).rowcount,
            "reminders": self._x("DELETE FROM reminders WHERE sent=1 OR due_at < ?", (now - 8 * 86400,)).rowcount,
            "questions": self._x("DELETE FROM questions WHERE created_at < ?", (now - question_ttl_s,)).rowcount,
            "referrals": self._x("DELETE FROM referrals WHERE expires_at < ?", (now,)).rowcount,
        }
        cutoff = (datetime.fromtimestamp(now, timezone.utc).date() - timedelta(days=events_retention_days)).isoformat()
        out["events"] = self._x("DELETE FROM events WHERE day < ?", (cutoff,)).rowcount
        return out

    # ------------------------------------------------ test helpers
    def count_rows(self, table: str) -> int:
        assert table in {"sessions", "reminders", "events", "referrals", "questions", "themes", "fsessions"}
        return self._x(f"SELECT COUNT(*) FROM {table}").fetchone()[0]

    def dump_all_text(self) -> str:
        parts = []
        for t in ("sessions", "reminders", "events", "referrals", "questions", "themes", "fsessions"):
            for row in self._x(f"SELECT * FROM {t}").fetchall():
                parts.append(" ".join(str(c) for c in tuple(row)))
        return "\n".join(parts)


Repository = SQLiteRepository


def make_repository(database_url: str) -> SQLiteRepository:
    if database_url == "sqlite://:memory:":
        return SQLiteRepository(":memory:")
    if database_url.startswith("sqlite:///"):
        return SQLiteRepository(database_url[len("sqlite:///"):])
    raise NotImplementedError("Postgres: implement the same methods with psycopg and select it here.")
