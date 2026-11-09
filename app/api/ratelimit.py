"""In-memory sliding-window rate limiter. Keys are hashes; nothing is persisted or logged."""
from __future__ import annotations

import hashlib
import threading
import time
from collections import defaultdict, deque

from fastapi import HTTPException, Request


class RateLimiter:
    def __init__(self):
        self._hits: dict[str, deque] = defaultdict(deque)
        self._lock = threading.Lock()

    def check(self, key: str, limit: int, window_s: int = 60) -> None:
        now = time.monotonic()
        with self._lock:
            q = self._hits[key]
            while q and now - q[0] > window_s:
                q.popleft()
            if len(q) >= limit:
                raise HTTPException(429, "Too many requests. Please wait a minute.")
            q.append(now)
            if len(self._hits) > 50000:  # bound memory
                for k in list(self._hits)[:10000]:
                    del self._hits[k]


def client_key(request: Request, extra: str = "") -> str:
    ip = request.client.host if request.client else "?"
    return hashlib.sha256(f"{ip}|{extra}".encode()).hexdigest()[:32]


def limit(request: Request, bucket: str, per_min: int, extra: str = "") -> None:
    request.app.state.ratelimiter.check(f"{bucket}:{client_key(request, extra)}", per_min)
