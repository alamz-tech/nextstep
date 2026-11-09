"""Web demo simulator API. Same engine as WhatsApp; works with no credentials.

The browser holds a random session id per tab. It is hashed like a phone number.
"""
from __future__ import annotations

import base64
import time
import uuid

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from ..config import ROOT
from ..engine.engine import Inbound

STATIC = ROOT / "app" / "static"


class SimIn(BaseModel):
    sid: str = Field(min_length=8, max_length=64)
    kind: str = Field(pattern="^(text|button|voice)$")
    text: str = Field(default="", max_length=2000)
    button: str = Field(default="", max_length=64)


class SimSid(BaseModel):
    sid: str = Field(min_length=8, max_length=64)


def make_router(container) -> APIRouter:
    r = APIRouter()
    eng = container.engine

    def out(res, voice_in: bool, lang: str) -> dict:
        msgs = []
        for m in res.messages:
            m = dict(m)
            if m.get("speak") and voice_in:
                text = eng.text_of(m, lang)
                audio = container.voice.synthesize(text, lang)
                if audio:
                    m["audio"] = "data:audio/mpeg;base64," + base64.b64encode(audio).decode()
                else:
                    m["voice_fallback"] = True
                    if container.settings.sim_record_events:
                        container.repo.log_event("voice_fallback", "tts", lang)
            msgs.append(m)
        st = res.state or {}
        return {"messages": msgs, "events": [e[0] for e in res.events], "lang": st.get("lang", lang),
                "stage": st.get("stage", "idle"), "ended": res.delete,
                "voice": {"tts": container.voice.tts_enabled_for(lang), "provider": container.voice.name}}

    def advance(sid: str) -> dict:
        uid = container.uid("sim", sid)
        st = container.repo.get_session(uid)
        if not st or not st.get("consented"):
            return {"messages": [eng.sys("Demo: no active chat to follow up. Say Hi first.")], "events": [], "stage": "idle", "lang": "en", "ended": False}
        pending = container.repo.pending_reminders(uid)
        kind = "day3"
        if pending:
            kind = pending[0].kind.split("|")[0]
            container.repo.mark_reminder_sent(pending[0].id)
        res = container.process("sim", sid, Inbound("followup_due", followup_kind=kind))
        return out(res, False, st.get("lang", "en"))

    @r.get("/sim")
    def page():
        if not container.settings.sim_enabled:
            raise HTTPException(404)
        return FileResponse(STATIC / "sim" / "index.html")

    @r.get("/sim/api/copy")
    def copy():
        return container.copy.public_json()

    @r.get("/sim/api/new")
    def new():
        return {"sid": uuid.uuid4().hex}

    @r.post("/sim/api/message")
    def message(body: SimIn):
        if not container.settings.sim_enabled:
            raise HTTPException(404)
        st = container.repo.get_session(container.uid("sim", body.sid)) or {}
        lang = st.get("lang", "en")
        if body.kind == "button":
            inp = Inbound("button", button=body.button)
        elif body.kind == "voice":
            # The simulator sends a scripted demo voice note; its transcript is
            # provided by the page (no real audio, no STT call).
            inp = Inbound("voice", text=body.text, transcript_ok=bool(body.text))
        else:
            inp = Inbound("text", text=body.text)
        res = container.process("sim", body.sid, inp)
        data = out(res, body.kind == "voice", (res.state or {}).get("lang", lang))
        if any(a["type"] == "simulate_followup" for a in res.actions):
            more = advance(body.sid)
            data["messages"] += more["messages"]
            data["events"] += more["events"]
            data["stage"] = more["stage"]
        return data

    @r.post("/sim/api/advance")
    def adv(body: SimSid):
        return advance(body.sid)

    @r.post("/sim/api/restart")
    def restart(body: SimSid):
        container.repo.delete_user(container.uid("sim", body.sid))
        return {"ok": True, "t": int(time.time())}

    return r
