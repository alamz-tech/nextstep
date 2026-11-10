"""/v1/chat — the learner app's chat, using the same design-flow engine as WhatsApp.

The app sends a random install ID (X-Install-ID). Conversation state lives in the
sessions table under an HMAC of that ID and expires after SESSION_TTL_HOURS. No
message text or audio is stored.
"""
from __future__ import annotations

import base64

from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile
from pydantic import BaseModel, Field

from ..engine.engine import Inbound, Result, new_state
from .learner import INSTALL_RE
from .ratelimit import limit

# Actions the app itself must carry out (local notifications, wiping the device).
CLIENT_ACTIONS = {"schedule_followups", "ensure_followup", "cancel_followups", "simulate_followup", "delete_user"}


class StartIn(BaseModel):
    lang: str = Field(default="en", pattern="^(en|pcm)$")
    tier: str = Field(pattern="^(15_17|18_24)$")


class ChatIn(BaseModel):
    kind: str = Field(pattern="^(text|button|followup_due)$")
    text: str = Field(default="", max_length=1000)
    button: str = Field(default="", max_length=64)


def install_id(request: Request) -> str:
    v = request.headers.get("x-install-id", "")
    if not INSTALL_RE.match(v):
        raise HTTPException(400, "X-Install-ID header required (random id generated on the device)")
    limit(request, "chat", request.app.state.container.settings.rate_limit_ask_per_min * 3, v)
    return v


def make_router(container) -> APIRouter:
    r = APIRouter(prefix="/v1")
    eng = container.engine

    def respond(res, voice_in: bool) -> dict:
        lang = (res.state or {}).get("lang", "en")
        msgs = []
        for m in res.messages:
            m = dict(m)
            if m.get("speak") and voice_in:
                audio = container.voice.synthesize(eng.text_of(m, lang), lang)
                if audio:
                    m["audio"] = "data:audio/mpeg;base64," + base64.b64encode(audio).decode()
                else:
                    container.repo.log_event("voice_fallback", "tts", lang, lang=lang)
            msgs.append(m)
        return {"messages": msgs, "lang": lang, "stage": (res.state or {}).get("stage", "idle"), "ended": res.delete,
                "actions": [a for a in res.actions if a["type"] in CLIENT_ACTIONS]}

    @r.get("/chat/copy")
    def copy():
        return container.copy.public_json()

    @r.post("/chat/start")
    def chat_start(body: StartIn, iid: str = Depends(install_id)):
        """Open "Ask a question". Consent and age were already given in the app's first-time
        setup (POST /v1/learner/onboard), so the chat starts at the Q&A prompt."""
        st = new_state(body.lang)
        st.update(consented=True, tier=body.tier, stage="qa")
        container.repo.save_session(container.uid("app", iid), st)
        res = Result(messages=[eng.m(("qa", "prompt"))], state=st)
        return respond(res, False)

    @r.post("/chat")
    def chat(body: ChatIn, iid: str = Depends(install_id)):
        if body.kind == "button":
            inp = Inbound("button", button=body.button)
        elif body.kind == "followup_due":
            inp = Inbound("followup_due", followup_kind="day3")
        else:
            inp = Inbound("text", text=body.text)
        return respond(container.process("app", iid, inp), False)

    @r.post("/chat/voice")
    async def chat_voice(audio: UploadFile = File(...), iid: str = Depends(install_id)):
        data = await audio.read(2_000_001)
        if len(data) > 2_000_000:
            raise HTTPException(413, "voice note too long")
        st = container.repo.get_session(container.uid("app", iid)) or {}
        transcript = container.voice.transcribe(data, audio.content_type or "audio/m4a", st.get("lang", "en"))
        data = b""  # never stored
        res = container.process("app", iid, Inbound("voice", text=transcript or "", transcript_ok=bool(transcript)))
        out = respond(res, True)
        out["transcript"] = transcript or ""
        return out

    @r.post("/chat/demo-voice")
    def chat_demo_voice(iid: str = Depends(install_id)):
        """Demo mode only: the design's sample voice note ("Can I get HIV from kissing?")."""
        if not container.settings.demo_mode:
            raise HTTPException(404)
        st = container.repo.get_session(container.uid("app", iid)) or {}
        t = container.copy.t(("qa", "user_voice"), st.get("lang", "en"))
        out = respond(container.process("app", iid, Inbound("voice", text=t)), True)
        out["transcript"] = t
        return out

    return r
