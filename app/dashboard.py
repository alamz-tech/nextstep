"""Impact dashboard: aggregate counts only, small-cell suppression, role-based access.

Learner funnel:     app opens → private checks → referrals issued → visits confirmed by clinics
                    (self-reported visits are shown separately).
Facilitator metrics: sessions, approximate reach, questions, top themes, crisis flags (count only).
Filters: date range, state, age tier, language, setting.
"""
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
              org: str = "", sessions: list[dict] | None = None, themes: list[dict] | None = None,
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
        elif e == "consent_given":
            lang[r["lang"]] += n
        elif e == "question_asked":
            qinput["voice" if r["dim2"] == "voice" else "text"] += n

    def pct(a: int, b: int) -> str:
        return f"{round(a / b * 100)}%" if (a >= SUPPRESS_BELOW and b >= SUPPRESS_BELOW) else "–"

    opens, checks, refs = tot["app_open"], tot["check_completed"], tot["referral_issued"]
    clinic, selfrep = tot["visit_confirmed_clinic"], tot["visit_self_reported"]

    def w(a: int) -> float:
        return round(min(a / opens * 100, 100), 1) if opens and a >= SUPPRESS_BELOW else 0

    def split(c: Counter, labels):
        total = sum(c[k] for k, _ in labels)
        return [{"label": lab, "v": suppress(c[k]), "share": pct(c[k], total),
                 "pct": round(c[k] / total * 100, 1) if total and c[k] >= SUPPRESS_BELOW else 0} for k, lab in labels]

    ses = sessions or []
    reach = sum(s["audience_size"] for s in ses)
    th = Counter()
    for t in themes or []:
        th[t["label"]] += t["count"]
    labels = {"7": "Last 7 days", "30": "Last 30 days", "90": "Last 90 days", "all": "Since pilot start"}
    start = since or (date.fromisoformat(pilot_start) if pilot_start else first)
    return {
        "range": range_key if range_key in labels else "all",
        "range_text": f"{start.strftime('%-d %b %Y') if start else '[PILOT START DATE]'} – {today.strftime('%-d %b %Y')}",
        "filters": f, "sample": sample,
        "kpis": [
            {"key": "opens", "label": "App opens", "v": suppress(opens), "note": "Days with the app opened"},
            {"key": "checks", "label": "Private checks", "v": suppress(checks), "note": "Completed all questions"},
            {"key": "referrals", "label": "Referrals issued", "v": suppress(refs), "note": "Referral codes created"},
            {"key": "clinic", "label": "Visits confirmed by clinics", "v": suppress(clinic), "note": "Codes entered by partner clinics", "tone": "accent"},
            {"key": "selfrep", "label": "Visits self-reported", "v": suppress(selfrep), "note": "Learner said 'I went'"},
            {"key": "crisis", "label": "Crisis escalations", "v": suppress(tot["crisis_escalation"]), "note": "Count only", "tone": "support"},
        ],
        "funnel": [
            {"label": "App opens", "v": suppress(opens), "pct": 100 if opens >= SUPPRESS_BELOW else 0, "conv": "Started"},
            {"label": "Private checks", "v": suppress(checks), "pct": w(checks), "conv": f"{pct(checks, opens)} of opens"},
            {"label": "Referrals issued", "v": suppress(refs), "pct": w(refs), "conv": f"{pct(refs, checks)} of checks"},
            {"label": "Visits confirmed by clinics", "v": suppress(clinic), "pct": w(clinic), "conv": f"{pct(clinic, refs)} of referrals", "tone": "accent"},
        ],
        "self_reported": {"v": suppress(selfrep), "conv": pct(selfrep, refs)},
        "ages": split(age, [("18_24", "18–24"), ("15_17", "15–17"), ("under_15", "Under 15 (exited)")]),
        "langs": split(lang, [("en", "English"), ("pcm", "Nigerian Pidgin"), ("ha", "Hausa")]),
        "voice_share": pct(qinput["voice"], sum(qinput.values())),
        "crisis": suppress(tot["crisis_escalation"]),
        "facilitator": {
            "sessions": suppress(tot["session_created"]), "reach": suppress(reach) if ses else "–",
            "joins": suppress(tot["session_joined"]), "questions": suppress(tot["box_question"]),
            "flags": suppress(tot["box_flagged"]), "filtered": suppress(tot["box_filtered"]),
            "top_themes": [{"label": k, "v": suppress(v)} for k, v in th.most_common(5) if v >= SUPPRESS_BELOW],
        },
    }


def make_router(container) -> APIRouter:
    r = APIRouter()
    s = container.settings

    @r.get("/dashboard")
    def page():
        return FileResponse(ROOT / "app" / "static" / "dashboard" / "index.html")

    @r.get("/v1/dashboard/summary")
    def summary(range: str = "30", state: str = "", tier: str = "", lang: str = "", setting: str = "",
                p: Principal = Depends(require("platform_admin", "org_admin"))):
        filters = {"state": state.lower(), "tier": tier, "lang": lang, "setting": setting}
        rows = container.repo.event_rows()
        if p.role == "org_admin":
            ses = container.repo.list_fsessions(org_id=p.org_id)
            org_slug = (p.org_id or "").replace("org_", "")
            # Facilitator metrics are limited to the admin's own org; learner funnel stays global aggregate.
            rows = [x for x in rows if not x["event"].startswith(("session_", "box_", "theme_")) or x["org"] == org_slug]
        else:
            ses = container.repo.list_fsessions()
        days = {"7": 7, "30": 30, "90": 90}.get(range)
        if days:
            cut = (date.today() - timedelta(days=days - 1)).isoformat()
            ses = [x for x in ses if x["session_date"] >= cut]
        if setting:
            ses = [x for x in ses if x["setting"] == setting]
        if tier:
            ses = [x for x in ses if x["age_band"] == tier]
        themes = [t for x in ses for t in container.repo.session_themes(x["id"])]
        return summarise(rows, range, filters=filters, sessions=ses, themes=themes,
                         pilot_start=s.pilot_start_date, sample=s.dashboard_sample_badge)

    return r
