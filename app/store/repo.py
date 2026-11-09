"""Persistence behind a small repository interface.

Only three kinds of data are stored:
  * sessions  – conversation state for one hashed user, deleted after SESSION_TTL_HOURS
  * reminders – opted-in follow-ups (day 3 / day 7), deleted once sent or on STOP/DELETE
  * events    – aggregate daily counts (date, event, dim1, dim2, count). No user ids.

No message text is ever written. To move to Postgres, implement `Repository`
with the same methods and select it in `make_repository`.
"""
from __future__ import annotations

import json
import os
import sqlite3
import threading
import time
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from typing import Any, Protocol


@dataclass
class Reminder:
    id: int
    uid: str
    channel: str
    recipient_enc: str | None
    lang: str
    due_at: int
    kind: str


class Repository(Protocol):
    def get_session(self, uid: str) -> dict[str, Any] | None: ...
    def save_session(self, uid: str, state: dict[str, Any]) -> None: ...
    def delete_user(self, uid: str) -> None: ...
    def add_reminder(self, uid: str, channel: str, recipient_enc: str | None, lang: str, due_at: int, kind: str) -> None: ...
    def due_reminders(self, now: int, channel: str | None = None) -> list[Reminder]: ...
    def pending_reminders(self, uid: str) -> list[Reminder]: ...
    def mark_reminder_sent(self, rid: int) -> None: ...
    def cancel_reminders(self, uid: str) -> None: ...
    def log_event(self, event: str, dim1: str = "", dim2: str = "", day: date | None = None, n: int = 1) -> None: ...
    def event_rows(self, since: date | None) -> list[tuple[str, str, str, str, int]]: ...
    def purge_expired(self, session_ttl_s: int, events_retention_days: int, now: int | None = None) -> dict[str, int]: ...


SCHEMA = """
CREATE TABLE IF NOT EXISTS sessions (
  uid TEXT PRIMARY KEY,
  state_json TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS reminders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uid TEXT NOT NULL,
  channel TEXT NOT NULL,
  recipient_enc TEXT,
  lang TEXT NOT NULL,
  due_at INTEGER NOT NULL,
  kind TEXT NOT NULL,
  sent INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS reminders_due ON reminders(sent, due_at);
CREATE TABLE IF NOT EXISTS events (
  day TEXT NOT NULL,
  event TEXT NOT NULL,
  dim1 TEXT NOT NULL DEFAULT '',
  dim2 TEXT NOT NULL DEFAULT '',
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, event, dim1, dim2)
);
"""

# Event names the dashboard understands. Anything else is rejected so free text
# can never end up in the events table by mistake.
ALLOWED_EVENTS = {
    "conversation_started", "age_tier_selected", "question_asked", "check_started",
    "check_completed", "referral_given", "reminder_opt_in", "visit_confirmed",
    "visit_not_yet", "followup_help", "barrier_reported", "crisis_escalation",
    "out_of_scope", "voice_fallback", "data_deleted",
}
_DIM_OK = set("abcdefghijklmnopqrstuvwxyz0123456789_-")


def _clean_dim(v: str) -> str:
    v = (v or "").lower()[:32]
    if not set(v) <= _DIM_OK:
        raise ValueError("event dimensions must be short category slugs")
    return v


class SQLiteRepository:
    def __init__(self, path: str):
        if path != ":memory:":
            os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        self._db = sqlite3.connect(path, check_same_thread=False, isolation_level=None)
        self._db.execute("PRAGMA journal_mode=WAL" if path != ":memory:" else "PRAGMA journal_mode=MEMORY")
        self._db.executescript(SCHEMA)
        self._lock = threading.Lock()

    def _x(self, sql: str, args: tuple = ()) -> sqlite3.Cursor:
        with self._lock:
            return self._db.execute(sql, args)

    # sessions
    def get_session(self, uid: str) -> dict[str, Any] | None:
        row = self._x("SELECT state_json FROM sessions WHERE uid=?", (uid,)).fetchone()
        return json.loads(row[0]) if row else None

    def save_session(self, uid: str, state: dict[str, Any]) -> None:
        self._x(
            "INSERT INTO sessions(uid,state_json,updated_at) VALUES(?,?,?) "
            "ON CONFLICT(uid) DO UPDATE SET state_json=excluded.state_json, updated_at=excluded.updated_at",
            (uid, json.dumps(state), int(time.time())),
        )

    def delete_user(self, uid: str) -> None:
        self._x("DELETE FROM sessions WHERE uid=?", (uid,))
        self._x("DELETE FROM reminders WHERE uid=?", (uid,))

    # reminders
    def add_reminder(self, uid, channel, recipient_enc, lang, due_at, kind) -> None:
        self._x(
            "INSERT INTO reminders(uid,channel,recipient_enc,lang,due_at,kind) VALUES(?,?,?,?,?,?)",
            (uid, channel, recipient_enc, lang, due_at, kind),
        )

    def _rem(self, rows) -> list[Reminder]:
        return [Reminder(*r) for r in rows]

    def due_reminders(self, now: int, channel: str | None = None) -> list[Reminder]:
        q = "SELECT id,uid,channel,recipient_enc,lang,due_at,kind FROM reminders WHERE sent=0 AND due_at<=?"
        args: tuple = (now,)
        if channel:
            q += " AND channel=?"
            args += (channel,)
        return self._rem(self._x(q + " ORDER BY due_at", args).fetchall())

    def pending_reminders(self, uid: str) -> list[Reminder]:
        return self._rem(self._x(
            "SELECT id,uid,channel,recipient_enc,lang,due_at,kind FROM reminders WHERE sent=0 AND uid=? ORDER BY due_at",
            (uid,)).fetchall())

    def mark_reminder_sent(self, rid: int) -> None:
        # Sent reminders keep no recipient.
        self._x("UPDATE reminders SET sent=1, recipient_enc=NULL WHERE id=?", (rid,))

    def cancel_reminders(self, uid: str) -> None:
        self._x("DELETE FROM reminders WHERE uid=?", (uid,))

    # events
    def log_event(self, event: str, dim1: str = "", dim2: str = "", day: date | None = None, n: int = 1) -> None:
        if event not in ALLOWED_EVENTS:
            raise ValueError(f"unknown event {event!r}")
        d = (day or datetime.now(timezone.utc).date()).isoformat()
        self._x(
            "INSERT INTO events(day,event,dim1,dim2,count) VALUES(?,?,?,?,?) "
            "ON CONFLICT(day,event,dim1,dim2) DO UPDATE SET count=count+excluded.count",
            (d, event, _clean_dim(dim1), _clean_dim(dim2), n),
        )

    def event_rows(self, since: date | None) -> list[tuple[str, str, str, str, int]]:
        if since:
            return self._x("SELECT day,event,dim1,dim2,count FROM events WHERE day>=?", (since.isoformat(),)).fetchall()
        return self._x("SELECT day,event,dim1,dim2,count FROM events").fetchall()

    def purge_expired(self, session_ttl_s: int, events_retention_days: int, now: int | None = None) -> dict[str, int]:
        now = now or int(time.time())
        s = self._x("DELETE FROM sessions WHERE updated_at < ?", (now - session_ttl_s,)).rowcount
        # Sent reminders and any reminder more than 8 days overdue are removed.
        r = self._x("DELETE FROM reminders WHERE sent=1 OR due_at < ?", (now - 8 * 86400,)).rowcount
        cutoff = (datetime.fromtimestamp(now, timezone.utc).date() - timedelta(days=events_retention_days)).isoformat()
        e = self._x("DELETE FROM events WHERE day < ?", (cutoff,)).rowcount
        return {"sessions": s, "reminders": r, "events": e}

    def count_rows(self, table: str) -> int:
        assert table in {"sessions", "reminders", "events"}
        return self._x(f"SELECT COUNT(*) FROM {table}").fetchone()[0]

    def dump_all_text(self) -> str:
        """Test helper: every stored value concatenated, to prove no message text is kept."""
        parts = []
        for t in ("sessions", "reminders", "events"):
            for row in self._x(f"SELECT * FROM {t}").fetchall():
                parts.append(" ".join(str(c) for c in row))
        return "\n".join(parts)


def make_repository(database_url: str) -> SQLiteRepository:
    if database_url.startswith("sqlite:///"):
        return SQLiteRepository(database_url[len("sqlite:///"):])
    if database_url == "sqlite://:memory:":
        return SQLiteRepository(":memory:")
    raise NotImplementedError("Postgres: implement Repository for psycopg and select it here.")
