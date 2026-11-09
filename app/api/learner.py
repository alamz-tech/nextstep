"""/v1 learner API. Anonymous: the app sends a random install ID (X-Install-ID).

Never stored: question text, audio, transcripts, check answers. Stored: aggregate
events, and referral codes linked to an HMAC of the install ID (for deletion).
"""
from __future__ import annotations

import hashlib
import json
import re
import secrets
import time

from fastapi import APIRouter, Depends, File, Form, Header, HTTPException, Request, Response, UploadFile
from pydantic import BaseModel, Field

from ..kits import build_kits
from ..privacy import hash_id
from .ratelimit import limit

INSTALL_RE = re.compile(r"^[A-Za-z0-9-]{16,64}$")
LANGS = {"en", "pcm", "ha"}
TIERS = {"15_17", "18_24"}


class Learner:
    def __init__(self, install_hash: str):
        self.install_hash = install_hash


def learner(request: Request, x_install_id: str | None = Header(default=None)) -> Learner:
    if not x_install_id or not INSTALL_RE.match(x_install_id):
        raise HTTPException(400, "X-Install-ID header required (random id generated on the device)")
    c = request.app.state.container
    limit(request, "learner", c.settings.rate_limit_per_min, x_install_id)
    return Learner(hash_id("install:" + x_install_id, c.settings.hmac_secret))


def _lang(v: str) -> str:
    return v if v in LANGS else "en"


def _tier(v: str | None) -> str:
    return v if v in TIERS else ""


class AudioCache:
    """Short-lived in-memory TTS audio; served once via an unguessable URL."""

    def __init__(self, ttl: int):
        self.ttl = ttl
        self._d: dict[str, tuple[float, bytes]] = {}

    def put(self, data: bytes) -> str:
        now = time.time()
        for k in [k for k, (t, _) in self._d.items() if now - t > self.ttl]:
            del self._d[k]
        key = secrets.token_urlsafe(18)
        self._d[key] = (now, data)
        return key

    def get(self, key: str) -> bytes | None:
        v = self._d.get(key)
        if not v or time.time() - v[0] > self.ttl:
            return None
        return v[1]


class Onboard(BaseModel):
    lang: str = "en"
    age_tier: str = Field(pattern="^(under_15|15_17|18_24)$")
    state: str = ""


class AskIn(BaseModel):
    question: str = Field(min_length=1, max_length=1000)
    lang: str = "en"
    tier: str = ""
    want_audio: bool = True


class EventIn(BaseModel):
    event: str = Field(pattern="^(app_open|check_started|reminder_opt_in)$")
    lang: str = "en"
    tier: str = ""


class CheckIn(BaseModel):
    answers: dict[str, str]
    lang: str = "en"
    tier: str = ""


class ReferralIn(BaseModel):
    service_id: str = Field(max_length=40)
    lang: str = "en"
    tier: str = ""
    session_code: str = Field(default="", max_length=12)


class OutcomeIn(BaseModel):
    outcome: str = Field(pattern="^(went|not_yet|need_help)$")
    barrier: str = Field(default="", pattern="^(|cost|scared|blocked|other)$")
    lang: str = "en"
    tier: str = ""


def make_router(container) -> APIRouter:
    r = APIRouter(prefix="/v1")
    s = container.settings
    eng = container.engine
    audio_cache = AudioCache(s.audio_cache_seconds)

    def ev(name, d1="", d2="", **dims):
        try:
            container.repo.log_event(name, d1, d2, **dims)
        except ValueError:
            pass

    def state_slug() -> str:
        return re.sub(r"[^a-z0-9_-]", "", s.demo_state.lower())

    # ---------------------------------------------------------------- config & content
    @r.get("/config")
    def config():
        return {"api_version": 1, "demo_mode": s.demo_mode, "demo_state": s.demo_state,
                "features": {"voice_in": container.voice.name != "none", "hausa": s.feature_hausa,
                             "llm": eng.llm.name, "whatsapp": s.feature_whatsapp},
                "tts_langs": sorted(container.voice.approved) if container.voice.name != "none" else [],
                "public_base_url": s.public_base_url}

    def bundle() -> dict:
        kb = [{"id": c.id, "title": c.title, "lang": c.lang, "topic": c.topic, "age_tier": c.age_tier, "body": c.body,
               "source_document": c.source_document, "source_section": c.source_section,
               "review_status": c.review_status, "keywords": c.keywords}
              for c in container.kb.all if container.kb._servable(c)]
        app_copy_p = s.content_dir / "app_copy.json"
        data = {
            "copy": container.copy.public_json(),
            "app_copy": json.loads(app_copy_p.read_text(encoding="utf-8")) if app_copy_p.exists() else {},
            "kb": kb,
            "check": {k: v for k, v in eng.scorer.cfg.items()},
            "services": [container.finder.to_public(x) for x in container.finder.list(None, None, None)],
            "kits": build_kits(container.kb),
            "demo_mode": s.demo_mode,
        }
        raw = json.dumps(data, sort_keys=True, ensure_ascii=False)
        data["version"] = hashlib.sha256(raw.encode()).hexdigest()[:16]
        return data

    @r.get("/content/bundle")
    def content_bundle(request: Request, response: Response):
        b = bundle()
        etag = f'"{b["version"]}"'
        if request.headers.get("if-none-match") == etag:
            return Response(status_code=304)
        response.headers["ETag"] = etag
        response.headers["Cache-Control"] = "no-cache"
        return b

    # ---------------------------------------------------------------- onboarding
    @r.post("/learner/onboard")
    def onboard(body: Onboard, who: Learner = Depends(learner)):
        lang = _lang(body.lang)
        ev("age_tier_selected", body.age_tier.replace("under_15", "under_15"), lang=lang)
        if body.age_tier == "under_15":
            # Nothing else is recorded; the app shows a kind exit screen and wipes itself.
            return {"exit": True, "text": container.copy.t(("age", "under15"), lang)}
        ev("consent_given", lang=lang, tier=body.age_tier, state=state_slug())
        return {"exit": False}

    @r.post("/learner/events")
    def learner_event(body: EventIn, who: Learner = Depends(learner)):
        ev(body.event, lang=_lang(body.lang), tier=_tier(body.tier), state=state_slug())
        return {"ok": True}

    # ---------------------------------------------------------------- ask
    def _respond(res: dict, events, lang: str, tier: str, want_audio: bool, input_kind: str) -> dict:
        for name, d1, d2 in events:
            ev(name, d1, d2, lang=lang, tier=tier, state=state_slug())
        if want_audio and res.get("type") in ("answer", "crisis", "out_of_scope", "unknown"):
            audio = container.voice.synthesize(res["text"], lang)
            if audio:
                res["audio_url"] = f"/v1/audio/{audio_cache.put(audio)}"
            elif input_kind == "voice":
                res["voice_fallback"] = True
                ev("voice_fallback", "tts", lang, lang=lang)
        res["footer"] = container.copy.t(("app", "not_medical_advice"), lang) if container.copy.raw("app", "not_medical_advice") else ""
        return res

    @r.post("/learner/ask")
    def ask(request: Request, body: AskIn, who: Learner = Depends(learner)):
        limit(request, "ask", s.rate_limit_ask_per_min, who.install_hash)
        lang, tier = _lang(body.lang), _tier(body.tier)
        res, events = eng.ask(body.question, lang, tier, "text")
        return _respond(res, events, lang, tier, body.want_audio, "text")

    @r.post("/learner/ask/voice")
    async def ask_voice(request: Request, audio: UploadFile = File(...), lang: str = Form("en"), tier: str = Form(""),
                        want_audio: bool = Form(True), who: Learner = Depends(learner)):
        limit(request, "ask", s.rate_limit_ask_per_min, who.install_hash)
        lang, tier = _lang(lang), _tier(tier)
        data = await audio.read(2_000_001)
        if len(data) > 2_000_000:
            raise HTTPException(413, "voice note too long")
        transcript = container.voice.transcribe(data, audio.content_type or "audio/m4a", lang)
        data = b""  # audio is never stored
        if not transcript:
            ev("voice_fallback", "stt", lang, lang=lang)
            return {"type": "voice_unavailable", "text": container.copy.t(("extra", "voice_unavailable"), lang)}
        res, events = eng.ask(transcript, lang, tier, "voice")
        res["transcript"] = transcript
        return _respond(res, events, lang, tier, want_audio, "voice")

    @r.get("/audio/{key}")
    def get_audio(key: str):
        data = audio_cache.get(key)
        if not data:
            raise HTTPException(404)
        return Response(content=data, media_type="audio/mpeg", headers={"Cache-Control": "no-store"})

    # ---------------------------------------------------------------- private check
    @r.get("/learner/check")
    def check_questions(lang: str = "en", who: Learner = Depends(learner)):
        lang = _lang(lang)
        qs = []
        for i, q in enumerate(eng.scorer.questions, start=1):
            qs.append({"id": q["id"], "n": i, "text": container.copy.t(("check", q["id"]), lang),
                       "answers": [{"value": a, "label": container.copy.t(("check", {"y": "btn_yes", "n": "btn_no", "ns": "btn_not_sure", "rn": "btn_rather_not"}[a]), lang)} for a in q["answers"]],
                       "source": q.get("source", "")})
        return {"intro": container.copy.t(("check", "intro"), lang), "questions": qs,
                "review_status": eng.scorer.cfg.get("review_status"), "tool_name": eng.scorer.cfg.get("tool_name")}

    @r.post("/learner/check")
    def check_submit(body: CheckIn, who: Learner = Depends(learner)):
        lang, tier = _lang(body.lang), _tier(body.tier)
        score, sti, safety = 0, False, False
        for q in eng.scorer.questions:
            a = body.answers.get(q["id"], "rn")
            if a not in q["answers"] and a != "rn":
                raise HTTPException(422, f"invalid answer for {q['id']}")
            score += eng.scorer.points(q["id"], a)
            sti = sti or eng.scorer.flag("sti_signs", q["id"], a)
            safety = safety or eng.scorer.flag("safeguarding", q["id"], a)
        band = eng.scorer.band(score)
        ev("check_completed", band, lang=lang, tier=tier, state=state_slug())
        out = {"band": band, "result_ref": ["check", "result_next" if band == "next" else "result_low"],
               "text": container.copy.t(("check", "result_next" if band == "next" else "result_low"), lang),
               "sti_text": container.copy.t(("check", "result_sti"), lang) if sti else "",
               "safeguarding": safety}
        if safety:
            ev("crisis_escalation", "sexual_violence", "check_q5", lang=lang, tier=tier, state=state_slug())
            out["crisis"] = eng.crisis_payload("sexual_violence", lang)
        return out  # answers are not stored

    # ---------------------------------------------------------------- services & referrals
    @r.get("/services")
    def services(state: str = "", lga: str = "", tier: str = "", who: Learner = Depends(learner)):
        items = [container.finder.to_public(x) for x in container.finder.list(state or None, lga or None, _tier(tier) or None)]
        return {"state": state or s.demo_state, "lgas": sorted({i["lga"] for i in items}), "services": items}

    @r.post("/referrals")
    def make_referral(request: Request, body: ReferralIn, who: Learner = Depends(learner)):
        svc = container.finder.by_id(body.service_id)
        if not svc or not container.finder.is_showable(svc):
            raise HTTPException(404, "service not found")
        lang, tier = _lang(body.lang), _tier(body.tier)
        setting = ""
        if body.session_code:
            fs = container.repo.get_fsession_by_code(body.session_code)
            if fs:
                setting = fs["setting"]
                container.repo.bump_fsession(fs["id"], "referral_cards")
        code = container.repo.create_referral(who.install_hash, svc.id, re.sub(r"[^a-z0-9_-]", "", svc.state.lower()),
                                              tier, lang, setting, s.referral_ttl_days)
        ev("referral_issued", "verified" if svc.verified else "demo", lang=lang, tier=tier,
           state=re.sub(r"[^a-z0-9_-]", "", svc.state.lower()), setting=setting)
        return {"code": code, "service": container.finder.to_public(svc), "demo": not svc.verified,
                "expires_in_days": s.referral_ttl_days}

    @r.get("/referrals/mine")
    def my_referrals(who: Learner = Depends(learner)):
        return {"referrals": [{"code": x["code"], "service_id": x["service_id"], "created_day": x["created_day"],
                               "confirmed": bool(x["confirmed_day"])} for x in container.repo.referrals_for_install(who.install_hash)]}

    @r.post("/learner/outcome")
    def outcome(body: OutcomeIn, who: Learner = Depends(learner)):
        lang, tier = _lang(body.lang), _tier(body.tier)
        dims = dict(lang=lang, tier=tier, state=state_slug())
        if body.outcome == "went":
            ev("visit_self_reported", **dims)
        elif body.outcome == "not_yet":
            ev("visit_not_yet", **dims)
        else:
            ev("followup_help", **dims)
            if body.barrier:
                ev("barrier_reported", body.barrier, **dims)
        res: dict = {"ok": True}
        if body.barrier == "blocked":
            ev("crisis_escalation", "violence", "followup_blocked", **dims)
            res["crisis"] = eng.crisis_payload("violence", lang)
        return res

    @r.delete("/learner/data")
    def delete_data(who: Learner = Depends(learner)):
        n = container.repo.delete_install(who.install_hash)
        ev("data_deleted")
        return {"deleted": True, "referrals_removed": n}

    return r
