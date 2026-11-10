"""/v1 staff API: sign-in, org/user admin, facilitator sessions, anonymous question box,
projector view, session reports, clinic referral confirmation.

Access rules (enforced on every endpoint):
  platform_admin – everything aggregate, manage orgs and accounts.
  org_admin      – manage accounts and see sessions/reports for their own org.
  facilitator    – create and run their own sessions; see themes, never raw questions.
  clinic_partner – confirm referral codes; sees only "confirmed / not valid".
Nobody can read individual learner or student data: there is no endpoint for it.
"""
from __future__ import annotations

import csv
import io
import re
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, Field

from . import redact as R
from .auth import ROLES, Principal, hash_password, require, sign_token, verify_password
from .ratelimit import limit
from .themes import regroup, suggested_answer

SETTINGS = {"school", "community", "clinic"}
AGE_BANDS = {"15_17", "18_24"}
CHECKLIST_KEYS = ["school_permission", "consent_requirements", "safeguarding_contact", "support_contacts_ready"]


class LoginIn(BaseModel):
    username: str = Field(min_length=3, max_length=64)
    password: str = Field(min_length=6, max_length=200)


class OrgIn(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    kind: str = Field(pattern="^(ngo|school|clinic|other)$")
    state: str = Field(default="", max_length=40)


class UserIn(BaseModel):
    username: str = Field(min_length=3, max_length=64, pattern=r"^[A-Za-z0-9_.-]+$")
    password: str = Field(min_length=10, max_length=200)
    role: str
    org_id: str | None = None


class SessionIn(BaseModel):
    setting: str
    session_date: date
    age_band: str
    audience_size: int = Field(ge=1, le=2000)
    lang: str = "en"


class QuestionIn(BaseModel):
    text: str = Field(min_length=1, max_length=500)


class ConfirmIn(BaseModel):
    code: str = Field(min_length=4, max_length=12)


class ChecklistIn(BaseModel):
    items: dict[str, bool]


def make_router(container) -> APIRouter:
    r = APIRouter(prefix="/v1")
    s = container.settings
    repo = container.repo
    eng = container.engine

    def ev(name, d1="", d2="", **dims):
        try:
            repo.log_event(name, d1, d2, **dims)
        except ValueError:
            pass

    def state_of(org_id: str | None) -> str:
        org = repo.get_org(org_id) if org_id else None
        st = (org or {}).get("state") or s.demo_state
        return re.sub(r"[^a-z0-9_-]", "", st.lower())

    # ------------------------------------------------------------ auth
    @r.post("/auth/login")
    def login(request: Request, body: LoginIn):
        limit(request, "login", 10, body.username.lower())
        acc = repo.get_account_by_username(body.username)
        if not acc or not acc["active"] or not verify_password(body.password, acc["pw_hash"]):
            raise HTTPException(401, "wrong username or password")
        token = sign_token(s.signing_secret, {"sub": acc["id"], "role": acc["role"]}, s.token_ttl_hours * 3600)
        org = repo.get_org(acc["org_id"]) if acc["org_id"] else None
        return {"token": token, "role": acc["role"], "username": acc["username"],
                "org": {"id": org["id"], "name": org["name"], "kind": org["kind"]} if org else None}

    @r.get("/auth/me")
    def me(p: Principal = Depends(require(*ROLES))):
        return {"id": p.id, "role": p.role, "username": p.username, "org_id": p.org_id}

    # ------------------------------------------------------------ admin
    @r.post("/admin/orgs")
    def create_org(body: OrgIn, p: Principal = Depends(require("platform_admin"))):
        return {"id": repo.create_org(body.name, body.kind, body.state)}

    @r.get("/admin/orgs")
    def list_orgs(p: Principal = Depends(require("platform_admin", "org_admin"))):
        if p.role == "org_admin":
            return {"orgs": [repo.get_org(p.org_id)]}
        return {"orgs": repo.list_orgs()}

    @r.post("/admin/users")
    def create_user(body: UserIn, p: Principal = Depends(require("platform_admin", "org_admin"))):
        if body.role not in ROLES:
            raise HTTPException(422, "unknown role")
        org_id = body.org_id
        if p.role == "org_admin":
            if body.role not in ("facilitator", "clinic_partner", "org_admin"):
                raise HTTPException(403, "org admins can create facilitators, clinic partners and org admins only")
            org_id = p.org_id
        if body.role != "platform_admin" and not (org_id and repo.get_org(org_id)):
            raise HTTPException(422, "org_id required")
        if repo.get_account_by_username(body.username):
            raise HTTPException(409, "username taken")
        return {"id": repo.create_account(body.username, hash_password(body.password), body.role, org_id)}

    @r.get("/admin/users")
    def list_users(p: Principal = Depends(require("platform_admin", "org_admin"))):
        return {"users": repo.list_accounts(p.org_id if p.role == "org_admin" else None)}

    @r.post("/admin/users/{aid}/disable")
    def disable_user(aid: str, p: Principal = Depends(require("platform_admin", "org_admin"))):
        acc = repo.get_account(aid)
        if not acc or (p.role == "org_admin" and acc["org_id"] != p.org_id):
            raise HTTPException(404)
        repo.set_account_active(aid, False)
        return {"ok": True}

    # ------------------------------------------------------------ facilitator sessions
    def own_session(sid: str, p: Principal) -> dict:
        fs = repo.get_fsession(sid)
        if not fs:
            raise HTTPException(404)
        allowed = (p.role == "platform_admin" or (p.role == "facilitator" and fs["facilitator_id"] == p.id)
                   or (p.role == "org_admin" and fs["org_id"] == p.org_id))
        if not allowed:
            raise HTTPException(404)  # do not reveal that it exists
        return fs

    def public_session(fs: dict) -> dict:
        return {k: fs[k] for k in ("id", "setting", "session_date", "age_band", "audience_size", "lang", "join_code",
                                    "status", "joins", "submitted", "flagged", "filtered", "referral_cards")} | {
            "join_url": f"{s.public_base_url.rstrip('/')}/join/{fs['join_code']}",
            "checklist": __import__("json").loads(fs["checklist_json"] or "{}")}

    @r.post("/sessions")
    def create_session(body: SessionIn, p: Principal = Depends(require("facilitator"))):
        if body.setting not in SETTINGS:
            raise HTTPException(422, "setting must be school, community or clinic")
        if body.age_band not in AGE_BANDS:
            raise HTTPException(422, "audience must be 15–17 or 18–24; younger audiences are out of scope")
        fs = repo.create_fsession(p.org_id, p.id, body.setting, body.session_date.isoformat(), body.age_band,
                                  body.audience_size, state_of(p.org_id), body.lang if body.lang in ("en", "pcm", "ha") else "en")
        ev("session_created", setting=body.setting, tier=body.age_band, state=fs["state"], org=p.org_id.replace("org_", ""))
        return public_session(fs)

    @r.get("/sessions")
    def list_sessions(p: Principal = Depends(require("facilitator", "org_admin", "platform_admin"))):
        if p.role == "facilitator":
            rows = repo.list_fsessions(facilitator_id=p.id)
        elif p.role == "org_admin":
            rows = repo.list_fsessions(org_id=p.org_id)
        else:
            rows = repo.list_fsessions()
        return {"sessions": [public_session(x) for x in rows]}

    @r.get("/sessions/{sid}")
    def get_session(sid: str, p: Principal = Depends(require("facilitator", "org_admin", "platform_admin"))):
        return public_session(own_session(sid, p))

    @r.post("/sessions/{sid}/checklist")
    def checklist(sid: str, body: ChecklistIn, p: Principal = Depends(require("facilitator"))):
        own_session(sid, p)
        repo.set_checklist(sid, {k: bool(body.items.get(k)) for k in CHECKLIST_KEYS})
        return {"ok": True}

    @r.post("/sessions/{sid}/close")
    def close(sid: str, p: Principal = Depends(require("facilitator", "org_admin"))):
        own_session(sid, p)
        repo.close_fsession(sid)  # deletes stored (redacted) question text
        return {"ok": True}

    def theme_view(fs: dict) -> list[dict]:
        out = []
        for t in repo.session_themes(fs["id"]):
            out.append({"key": t["theme_key"], "label": t["label"], "count": t["count"], "answered": bool(t["answered"]),
                        "suggested": suggested_answer(container.kb, t["theme_key"], fs["lang"])})
        return out

    @r.get("/sessions/{sid}/themes")
    def themes(sid: str, p: Principal = Depends(require("facilitator", "org_admin", "platform_admin"))):
        fs = own_session(sid, p)
        if fs["status"] == "open" and p.role == "facilitator":
            qs = repo.session_questions(sid)
            grouped, assign = regroup(container.kb, qs, fs["lang"], fs["age_band"],
                                     llm=container.engine.llm if container.settings.llm_group_questions else None)
            for qid, key in assign.items():
                repo.set_question_theme(qid, key)
            repo.replace_themes(sid, grouped)
        fs = repo.get_fsession(sid)
        support = container.copy.t(("app", "fac_support_reminder"), fs["lang"]) if fs["flagged"] else ""
        return {"session": public_session(fs), "themes": theme_view(fs), "flagged_count": fs["flagged"],
                "support_reminder": support}

    @r.post("/sessions/{sid}/themes/answered")
    def mark_answered(sid: str, body: dict, p: Principal = Depends(require("facilitator"))):
        fs = own_session(sid, p)
        key = str(body.get("key", ""))[:80]
        if repo.mark_theme(sid, key, bool(body.get("answered", True))) and body.get("answered", True):
            ev("theme_answered", setting=fs["setting"], tier=fs["age_band"], state=fs["state"], org=fs["org_id"].replace("org_", ""))
        return {"ok": True}

    @r.get("/sessions/{sid}/projector")
    def projector(sid: str, p: Principal = Depends(require("facilitator"))):
        fs = own_session(sid, p)
        # Themes and grounded answers only. Never raw questions.
        return {"join_code": fs["join_code"], "lang": fs["lang"],
                "themes": [{"label": t["label"], "count": t["count"], "answered": t["answered"],
                            "answer": (t["suggested"] or {}).get("text"), "sources": (t["suggested"] or {}).get("sources", [])}
                           for t in theme_view(fs)]}

    def report_data(fs: dict) -> dict:
        ths = repo.session_themes(fs["id"])
        return {"session_date": fs["session_date"], "setting": fs["setting"], "audience_age_band": fs["age_band"],
                "approximate_reach": fs["audience_size"], "anonymous_joins": fs["joins"],
                "questions_submitted": fs["submitted"], "crisis_flags": fs["flagged"], "filtered_submissions": fs["filtered"],
                "referral_cards_issued": fs["referral_cards"],
                "themes": [{"label": t["label"], "count": t["count"], "answered": bool(t["answered"])} for t in ths]}

    @r.get("/sessions/{sid}/report")
    def report(sid: str, format: str = "json", p: Principal = Depends(require("facilitator", "org_admin", "platform_admin"))):
        fs = own_session(sid, p)
        d = report_data(fs)
        if format == "csv":
            buf = io.StringIO()
            w = csv.writer(buf)
            w.writerow(["metric", "value"])
            for k, v in d.items():
                if k != "themes":
                    w.writerow([k, v])
            w.writerow([])
            w.writerow(["theme", "questions", "answered"])
            for t in d["themes"]:
                w.writerow([t["label"], t["count"], "yes" if t["answered"] else "no"])
            return Response(buf.getvalue(), media_type="text/csv",
                            headers={"Content-Disposition": f'attachment; filename="nextstep-session-{fs["session_date"]}.csv"'})
        if format == "pdf":
            from .pdf import session_report_pdf
            return Response(session_report_pdf(d), media_type="application/pdf",
                            headers={"Content-Disposition": f'attachment; filename="nextstep-session-{fs["session_date"]}.pdf"'})
        return d

    downloads: dict[str, tuple[float, str, str]] = {}

    @r.post("/sessions/{sid}/report-link")
    def report_link(sid: str, format: str = "pdf", p: Principal = Depends(require("facilitator", "org_admin", "platform_admin"))):
        """One-time, 2-minute download link, so the bearer token never goes in a URL."""
        import secrets as _s
        import time as _t
        own_session(sid, p)
        if format not in ("csv", "pdf"):
            raise HTTPException(422)
        now = _t.time()
        for k in [k for k, v in downloads.items() if now - v[0] > 120]:
            del downloads[k]
        nonce = _s.token_urlsafe(24)
        downloads[nonce] = (now, sid, format)
        return {"url": f"/v1/download/{nonce}"}

    @r.get("/download/{nonce}")
    def download(nonce: str):
        import time as _t
        v = downloads.pop(nonce, None)
        if not v or _t.time() - v[0] > 120:
            raise HTTPException(404)
        fs = repo.get_fsession(v[1])
        if not fs:
            raise HTTPException(404)
        d = report_data(fs)
        if v[2] == "pdf":
            from .pdf import session_report_pdf
            return Response(session_report_pdf(d), media_type="application/pdf",
                            headers={"Content-Disposition": f'attachment; filename="nextstep-session-{fs["session_date"]}.pdf"'})
        return report(v[1], "csv", Principal("system", "platform_admin", None, "system"))

    # ------------------------------------------------------------ anonymous question box (public, no login)
    @r.get("/join/{code}")
    def join_info(request: Request, code: str):
        limit(request, "join", s.rate_limit_per_min, code)
        fs = repo.get_fsession_by_code(code)
        if not fs:
            raise HTTPException(404, "session not found")
        return {"open": fs["status"] == "open", "setting": fs["setting"], "age_band": fs["age_band"], "lang": fs["lang"]}

    @r.post("/join/{code}/hello")
    def join_hello(request: Request, code: str):
        limit(request, "join", s.rate_limit_per_min, code)
        fs = repo.get_fsession_by_code(code)
        if not fs or fs["status"] != "open":
            raise HTTPException(404, "session not open")
        repo.bump_fsession(fs["id"], "joins")
        ev("session_joined", setting=fs["setting"], tier=fs["age_band"], state=fs["state"], org=fs["org_id"].replace("org_", ""))
        return {"ok": True}

    @r.post("/join/{code}/questions")
    def submit_question(request: Request, code: str, body: QuestionIn):
        limit(request, "box", s.rate_limit_box_per_min, code)
        fs = repo.get_fsession_by_code(code)
        if not fs or fs["status"] != "open":
            raise HTTPException(404, "session not open")
        lang = fs["lang"]
        dims = dict(setting=fs["setting"], tier=fs["age_band"], state=fs["state"], org=fs["org_id"].replace("org_", ""))
        # 1. crisis first: the student sees support immediately; nothing about them is stored.
        kind, layer, _ = eng.detect_crisis(body.text)
        if kind:
            repo.bump_fsession(fs["id"], "flagged")
            ev("box_flagged", kind, layer, **dims)
            ev("crisis_escalation", kind, "question_box", **dims)
            return {"status": "crisis", "crisis": eng.crisis_payload(kind, lang)}
        # 2. pranks / abuse / injection are filtered, not stored.
        if R.is_abusive(body.text) or eng.rules.scope_check(body.text) == "injection":
            repo.bump_fsession(fs["id"], "filtered")
            ev("box_filtered", **dims)
            return {"status": "filtered", "text": container.copy.t(("app", "box_filtered"), lang)}
        # 3. strip names / numbers before storage.
        clean, _ = R.redact(body.text)
        key, label = "open:other", ""
        from .themes import theme_for
        k, lab = theme_for(container.kb, clean, lang, fs["age_band"])
        if k != "open":
            key, label = k, lab
        else:
            label = "Other questions (no reviewed answer yet)"
        repo.add_question(fs["id"], clean, key, label)
        repo.bump_fsession(fs["id"], "submitted")
        ev("box_question", **dims)
        return {"status": "received", "text": container.copy.t(("app", "box_thanks"), lang)}

    # ------------------------------------------------------------ clinic partner
    @r.post("/clinic/confirm")
    def clinic_confirm(request: Request, body: ConfirmIn, p: Principal = Depends(require("clinic_partner"))):
        limit(request, "clinic", 30, p.id)
        ref = repo.get_referral(body.code)
        if not ref:
            return {"status": "not_found"}
        if ref["confirmed_day"]:
            return {"status": "already_confirmed"}
        if not repo.confirm_referral(body.code, p.org_id or ""):
            return {"status": "expired"}
        ev("visit_confirmed_clinic", lang=ref["lang"], tier=ref["tier"], state=ref["state"], setting=ref["setting"],
           org=(p.org_id or "").replace("org_", ""))
        return {"status": "confirmed"}  # no learner details are returned

    return r
