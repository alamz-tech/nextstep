"""Impact dashboard: aggregate counts only, HTTP basic auth, small-cell suppression."""
from __future__ import annotations

import secrets
from collections import Counter
from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import FileResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials

from .config import ROOT

SUPPRESS_BELOW = 5
basic = HTTPBasic(auto_error=False)


def suppress(v: int) -> str:
    return "<5" if v < SUPPRESS_BELOW else f"{v:,}"


def summarise(rows, range_key: str, today: date | None = None, pilot_start: str = "", sample: bool = True) -> dict:
    today = today or date.today()
    days = {"7": 7, "30": 30, "90": 90}.get(range_key)
    since = today - timedelta(days=days - 1) if days else None
    tot: Counter = Counter()
    by: dict[str, Counter] = {"age": Counter(), "lang": Counter(), "qinput": Counter(), "crisis": Counter()}
    first_day = None
    for day, ev, d1, d2, n in rows:
        dd = date.fromisoformat(day)
        if since and dd < since:
            continue
        first_day = min(first_day or dd, dd)
        tot[ev] += n
        if ev == "age_tier_selected":
            by["age"][d1] += n
        elif ev == "conversation_started":
            by["lang"][d1] += n
        elif ev == "question_asked":
            by["qinput"]["voice" if d2 == "voice" else "other"] += n

    conv, checks, refs, visits, crisis = (tot["conversation_started"], tot["check_completed"], tot["referral_given"],
                                          tot["visit_confirmed"], tot["crisis_escalation"])

    def pct(a: int, b: int) -> str:
        return f"{round(a / b * 100)}%" if (b >= SUPPRESS_BELOW and a >= SUPPRESS_BELOW) else "–"

    def width(a: int) -> float:
        return round(a / conv * 100, 1) if conv and a >= SUPPRESS_BELOW else 0

    def split(counter: Counter, labels: list[tuple[str, str]]) -> list[dict]:
        total = sum(counter[k] for k, _ in labels)
        return [{"key": k, "label": lab, "v": suppress(counter[k]),
                 "share": pct(counter[k], total) if total else "–", "pct": round(counter[k] / total * 100, 1) if total and counter[k] >= SUPPRESS_BELOW else 0}
                for k, lab in labels]

    labels = {"7": "Last 7 days", "30": "Last 30 days", "90": "Last 90 days", "all": "Since pilot start"}
    start = since or (date.fromisoformat(pilot_start) if pilot_start else first_day)
    q_total = sum(by["qinput"].values())
    return {
        "range": range_key if range_key in labels else "all",
        "range_label": labels.get(range_key, labels["all"]),
        "range_text": f"{start.strftime('%-d %b %Y') if start else '[PILOT START DATE]'} – {today.strftime('%-d %b %Y')}",
        "sample": sample,
        "kpis": [
            {"key": "conversations", "label": "Conversations", "v": suppress(conv), "note": "Consented chats"},
            {"key": "checks", "label": "Private checks", "v": suppress(checks), "note": "Completed all 6 questions"},
            {"key": "referrals", "label": "Referrals given", "v": suppress(refs), "note": "Service cards sent"},
            {"key": "visits", "label": "Visits confirmed", "v": suppress(visits), "note": "Self-reported at check-in", "tone": "accent"},
            {"key": "crisis", "label": "Crisis escalations", "v": suppress(crisis), "note": "Count only", "tone": "support"},
        ],
        "funnel": [
            {"label": "Conversations", "v": suppress(conv), "pct": 100 if conv >= SUPPRESS_BELOW else 0, "conv": "Started"},
            {"label": "Private checks", "v": suppress(checks), "pct": width(checks), "conv": f"{pct(checks, conv)} of conversations"},
            {"label": "Referrals given", "v": suppress(refs), "pct": width(refs), "conv": f"{pct(refs, checks)} of checks"},
            {"label": "Visits confirmed", "v": suppress(visits), "pct": width(visits), "conv": f"{pct(visits, refs)} of referrals", "tone": "accent"},
        ],
        "ages": split(by["age"], [("18_24", "18–24"), ("15_17", "15–17"), ("under_15", "Under 15 (exited)")]),
        "langs": split(by["lang"], [("en", "English"), ("pcm", "Nigerian Pidgin")]),
        "voice_share": pct(by["qinput"]["voice"], q_total),
        "crisis": suppress(crisis),
    }


def make_router(container) -> APIRouter:
    r = APIRouter()
    s = container.settings

    def auth(creds: HTTPBasicCredentials | None = Depends(basic)):
        if not s.dashboard_password:
            raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Dashboard disabled: set DASHBOARD_PASSWORD")
        ok = creds and secrets.compare_digest(creds.username, s.dashboard_user) and secrets.compare_digest(creds.password, s.dashboard_password)
        if not ok:
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, headers={"WWW-Authenticate": 'Basic realm="NextStep dashboard"'})

    @r.get("/dashboard", dependencies=[Depends(auth)])
    def page():
        return FileResponse(ROOT / "app" / "static" / "dashboard" / "index.html")

    @r.get("/dashboard/api/summary", dependencies=[Depends(auth)])
    def summary(range: str = "30"):
        since = None
        return summarise(container.repo.event_rows(since), range, pilot_start=s.pilot_start_date, sample=s.dashboard_sample_badge)

    return r
