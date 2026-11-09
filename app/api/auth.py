"""Accounts, password hashing, signed bearer tokens and role-based access.

Roles: facilitator, org_admin, clinic_partner, platform_admin. Learners have no
account: they send a random install ID in the X-Install-ID header.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
import time
from dataclasses import dataclass

from fastapi import Depends, Header, HTTPException, Request, status

ROLES = {"facilitator", "org_admin", "clinic_partner", "platform_admin"}


def hash_password(pw: str) -> str:
    salt = secrets.token_bytes(16)
    h = hashlib.scrypt(pw.encode(), salt=salt, n=2**14, r=8, p=1, dklen=32)
    return "scrypt$" + base64.b64encode(salt).decode() + "$" + base64.b64encode(h).decode()


def verify_password(pw: str, stored: str) -> bool:
    try:
        _, s, h = stored.split("$")
        calc = hashlib.scrypt(pw.encode(), salt=base64.b64decode(s), n=2**14, r=8, p=1, dklen=32)
        return hmac.compare_digest(calc, base64.b64decode(h))
    except Exception:
        return False


def _b64(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def _unb64(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def sign_token(secret: str, payload: dict, ttl_s: int) -> str:
    body = dict(payload, exp=int(time.time()) + ttl_s)
    raw = _b64(json.dumps(body, separators=(",", ":")).encode())
    sig = _b64(hmac.new(secret.encode(), raw.encode(), hashlib.sha256).digest())
    return f"{raw}.{sig}"


def read_token(secret: str, token: str) -> dict | None:
    try:
        raw, sig = token.split(".")
        good = _b64(hmac.new(secret.encode(), raw.encode(), hashlib.sha256).digest())
        if not hmac.compare_digest(good, sig):
            return None
        body = json.loads(_unb64(raw))
        return body if body.get("exp", 0) > time.time() else None
    except Exception:
        return None


@dataclass
class Principal:
    id: str
    role: str
    org_id: str | None
    username: str


def current_principal(request: Request, authorization: str | None = Header(default=None)) -> Principal:
    c = request.app.state.container
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "sign in required")
    body = read_token(c.settings.signing_secret, authorization.split(" ", 1)[1].strip())
    if not body:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid or expired token")
    acc = c.repo.get_account(body.get("sub", ""))
    if not acc or not acc["active"] or acc["role"] != body.get("role"):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "account disabled")
    return Principal(acc["id"], acc["role"], acc["org_id"], acc["username"])


def require(*roles: str):
    def dep(p: Principal = Depends(current_principal)) -> Principal:
        if p.role not in roles:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "not allowed for this role")
        return p
    return dep


def bootstrap_admin(container) -> None:
    s = container.settings
    if s.bootstrap_admin_user and s.bootstrap_admin_password and not container.repo.get_account_by_username(s.bootstrap_admin_user):
        container.repo.create_account(s.bootstrap_admin_user, hash_password(s.bootstrap_admin_password), "platform_admin", None)
