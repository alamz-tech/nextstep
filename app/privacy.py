"""Privacy primitives: identifier hashing, reminder encryption and log scrubbing."""
from __future__ import annotations

import hashlib
import hmac
import logging
import re

from cryptography.fernet import Fernet, InvalidToken


def hash_id(raw: str, secret: str) -> str:
    """One-way salted HMAC-SHA256 of a phone number / session id. Never reversible."""
    return hmac.new(secret.encode(), raw.strip().encode(), hashlib.sha256).hexdigest()


class ReminderCipher:
    """Encrypts the WhatsApp recipient for an OPTED-IN reminder only.

    A reminder must be delivered to a phone number, which a one-way hash cannot do.
    This is the single place a reversible identifier exists; it is deleted once the
    last check-in is sent, on STOP/DELETE, or by the TTL sweep.
    """

    def __init__(self, key: str):
        self._f = Fernet(key.encode()) if key else None

    @property
    def available(self) -> bool:
        return self._f is not None

    def encrypt(self, value: str) -> str | None:
        return self._f.encrypt(value.encode()).decode() if self._f else None

    def decrypt(self, token: str | None) -> str | None:
        if not (self._f and token):
            return None
        try:
            return self._f.decrypt(token.encode()).decode()
        except InvalidToken:
            return None


# Phone-number-like runs of digits (7+ digits, optional + and separators).
_PHONE = re.compile(r"\+?\d[\d\s\-()]{6,}\d")
# JSON-ish fields that may carry user text.
_TEXT_FIELDS = re.compile(r'("(?:body|text|transcript|caption|wa_id|from|input)"\s*:\s*")[^"]*(")', re.I)


def scrub(text: str) -> str:
    text = _TEXT_FIELDS.sub(r"\1[scrubbed]\2", text)
    return _PHONE.sub("[number]", text)


class ScrubFilter(logging.Filter):
    """Removes phone numbers and message text from every log record."""

    def filter(self, record: logging.LogRecord) -> bool:
        try:
            msg = record.getMessage()
        except Exception:  # pragma: no cover
            return True
        record.msg = scrub(msg)
        record.args = ()
        return True


def install_log_scrubbing() -> None:
    f = ScrubFilter()
    root = logging.getLogger()
    for h in root.handlers:
        h.addFilter(f)
    root.addFilter(f)
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access", "httpx", "app"):
        lg = logging.getLogger(name)
        lg.addFilter(f)
        for h in lg.handlers:
            h.addFilter(f)
