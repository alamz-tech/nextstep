"""Impact dashboard, as in the design board: aggregate counts only, small-cell suppression,
admin sign-in. Funnel: conversations → private checks → referrals given → visits confirmed
(confirmed by partner clinics entering the referral code)."""
from __future__ import annotations

from collections import Counter
from datetime import date, timedelta

from fastapi import APIRouter, Depends
from fastapi.responses import FileResponse

from .api.auth import Principal, require
from .config import ROOT

SUPPRESS_BELOW = 5


def suppress(v: int) -> str:
    return "<5" if v < SUPPRESS_BELOW else f"{v:,}"


def summarise(rows: list[dict], range_key: str = "30", *, today: date | None = None, filters: dict | None = None,
              pilot_start: str = "", sample: bool = True) -> dict:
    today = today or date.today()
    days = {"7": 7, "30": 30, "90": 90}.get(range_key)
    since = today - timedelta(days=days - 1) if days else None
    f = {k: v for k, v in (filters or {}).items() if v}
    tot: Counter = Counter()
    age, lang, qinput = Counter(), Counter(), Counter()
    first = None
    for r in rows:
        d = date.fromisoformat(r["day"])
        if since and d < since:
            continue
        if any(r.get(k, "") != v for k, v in f.items()):
            continue
        first = min(first or d, d)
        e, n = r["event"], r["count"]
        tot[e] += n
        if e == "age_tier_selected":
            age[r["dim1"]] += n
        elif e == "conversation_started":
            lang[r["dim1"]] += n
        elif e == "consent_given":
            lang[r["lang"]] += n
        elif e == "question_asked":
            qinput["voice" if r["dim2"] == "voice" else "text"] += n

    def pct(a: int, b: int) -> str:
        return f"{round(a / b * 100)}%" if (a >= SUPPRESS_BELOW and b >= SUPPRESS_BELOW) else "–"

    # Design funnel: conversations → private checks → referrals given → visits confirmed (by partner clinics).
    conv = tot["conversation_started"] + tot["consent_given"]
    checks, refs, visits = tot["check_completed"], tot["referral_issued"], tot["visit_confirmed_clinic"]

    def w(a: int) -> float:
        return round(min(a / conv * 100, 100), 1) if conv and a >= SUPPRESS_BELOW else 0

    def split(c: Counter, labels):
        total = sum(c[k] for k, _ in labels)
        return [{"label": lab, "v": suppress(c[k]), "share": pct(c[k], total),
                 "pct": round(c[k] / total * 100, 1) if total and c[k] >= SUPPRESS_BELOW else 0} for k, lab in labels]

    labels = {"7": "Last 7 days", "30": "Last 30 days", "90": "Last 90 days", "all": "Since pilot start"}
    start = since or (date.fromisoformat(pilot_start) if pilot_start else first)
    return {
        "range": range_key if range_key in labels else "all",
        "range_text": f"{start.strftime('%-d %b %Y') if start else '[PILOT START DATE]'} – {today.strftime('%-d %b %Y')}",
        "sample": sample,
        "kpis": [
            {"key": "conversations", "label": "Conversations", "v": suppress(conv), "note": "Consented chats", "color": "#1B1F23"},
            {"key": "checks", "label": "Private checks", "v": suppress(checks), "note": "Completed all 6 questions", "color": "#1B1F23"},
            {"key": "referrals", "label": "Referrals given", "v": suppress(refs), "note": "Service cards sent", "color": "#1B1F23"},
            {"key": "visits", "label": "Visits confirmed", "v": suppress(visits), "note": "Confirmed by partner clinics", "color": "#6E1F3D"},
            {"key": "crisis", "label": "Crisis escalations", "v": suppress(tot["crisis_escalation"]), "note": "Count only", "color": "#6E1F3D"},
        ],
        "funnel": [
            {"label": "Conversations", "v": suppress(conv), "pct": 100 if conv >= SUPPRESS_BELOW else 0, "conv": "Started", "color": "#A3305A"},
            {"label": "Private checks", "v": suppress(checks), "pct": w(checks), "conv": f"{pct(checks, conv)} of conversations", "color": "#A3305A"},
            {"label": "Referrals given", "v": suppress(refs), "pct": w(refs), "conv": f"{pct(refs, checks)} of checks", "color": "#A3305A"},
            {"label": "Visits confirmed", "v": suppress(visits), "pct": w(visits), "conv": f"{pct(visits, refs)} of referrals", "color": "#6E1F3D"},
        ],
        "ages": split(age, [("18_24", "18–24"), ("15_17", "15–17"), ("under_15", "Under 15 (exited)")]),
        "langs": split(lang, [("en", "English"), ("pcm", "Nigerian Pidgin")]),
        "voice_share": pct(qinput["voice"], sum(qinput.values())),
        "crisis": suppress(tot["crisis_escalation"]),
    }


def make_router(container) -> APIRouter:
    r = APIRouter()
    s = container.settings

    @r.get("/dashboard")
    def page():
        return FileResponse(ROOT / "app" / "static" / "dashboard" / "index.html")

    @r.get("/v1/dashboard/summary")
    def summary(range: str = "30", p: Principal = Depends(require("platform_admin", "org_admin"))):
        return summarise(container.repo.event_rows(), range, pilot_start=s.pilot_start_date, sample=s.dashboard_sample_badge)

    return r
