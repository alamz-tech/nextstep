"""WhatsApp Cloud API channel: webhook verification, signature check, inbound
parsing, rendering engine messages to Graph API payloads, and template sends.

Nothing from a WhatsApp message (number, text, audio) is logged or stored. The
sender's number is hashed before it touches the repository; audio bytes are
held in memory only for transcription and then dropped.
"""
from __future__ import annotations

import hashlib
import hmac
import logging
from collections import OrderedDict
from typing import Any

import httpx
import yaml
from fastapi import APIRouter, BackgroundTasks, HTTPException, Request, Response

from ..engine.engine import Inbound

log = logging.getLogger("app.whatsapp")

SIM_ONLY_BUTTONS = {"sim_skip3", "ref_demo_loc", "say_hi"}
BODY_MAX = 1024


def verify_signature(app_secret: str, body: bytes, header: str | None) -> bool:
    if not app_secret or not header or not header.startswith("sha256="):
        return False
    expected = hmac.new(app_secret.encode(), body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, header.split("=", 1)[1])


def parse_inbound(payload: dict) -> list[dict]:
    """Return [{wa_id, msg_id, kind, text, button, media_id, mime}] for each user message."""
    out = []
    for entry in payload.get("entry") or []:
        for ch in entry.get("changes") or []:
            v = ch.get("value") or {}
            for m in v.get("messages") or []:
                item = {"wa_id": m.get("from", ""), "msg_id": m.get("id", ""), "kind": "text", "text": "", "button": "",
                        "media_id": "", "mime": ""}
                t = m.get("type")
                if t == "text":
                    item["text"] = (m.get("text") or {}).get("body", "")
                elif t == "interactive":
                    inter = m.get("interactive") or {}
                    rep = inter.get("button_reply") or inter.get("list_reply") or {}
                    item.update(kind="button", button=rep.get("id", ""))
                elif t == "button":  # quick reply on a template message
                    item.update(kind="button", button=(m.get("button") or {}).get("payload", ""))
                elif t == "audio":
                    a = m.get("audio") or {}
                    item.update(kind="voice", media_id=a.get("id", ""), mime=a.get("mime_type", "audio/ogg"))
                elif t == "location":
                    item.update(kind="location")
                else:
                    item.update(kind="text", text="")
                out.append(item)
    return out


class WhatsAppRenderer:
    def __init__(self, engine, copy):
        self.engine, self.copy = engine, copy

    def render(self, msg: dict, lang: str) -> dict | None:
        k = msg.get("kind")
        if k == "system":
            return None
        if k == "call":
            return {"type": "text", "text": {"body": msg["number"]}}
        if k == "url":
            return {"type": "interactive", "interactive": {
                "type": "cta_url", "body": {"text": self.copy.t(("referral", "intro"), lang)[:BODY_MAX]},
                "action": {"name": "cta_url", "parameters": {"display_text": self.copy.t(msg["ref"], lang)[:20], "url": msg["url"]}}}}
        body = self.engine.text_of(msg, lang)
        header = None
        if k == "card":
            c = msg["card"]
            lines = [c["name"], c["address"], c["hours_raw"]]
            if c.get("demo_tag_ref"):
                lines.insert(0, "⚠ " + self.copy.t(c["demo_tag_ref"], lang))
            lines += ["", self.copy.t(("referral", "expect_title"), lang), body]
            body = "\n".join(lines)
            header = {"type": "text", "text": self.copy.t(("referral", "card_image_label"), lang)[:60]}
        if msg.get("kicker"):
            body = self.copy.t(("check", "progress"), lang).replace("{n}", str(msg["kicker"])) + "\n" + body
        body = body[:BODY_MAX]
        buttons = [b for b in msg.get("buttons") or [] if b["id"] not in SIM_ONLY_BUTTONS][:3]
        if msg.get("list"):
            rows = [{"id": r["id"], "title": self.copy.t(r["ref"], lang)[:24],
                     "description": self.copy.t(r["desc_ref"], lang)[:72]} for r in msg["list"][:10]]
            return {"type": "interactive", "interactive": {
                "type": "list", "body": {"text": body},
                "action": {"button": self.copy.t(("global", "list_button"), lang)[:20],
                           "sections": [{"title": "NextStep", "rows": rows}]}}}
        if buttons:
            inter: dict[str, Any] = {"type": "button", "body": {"text": body}, "action": {"buttons": [
                {"type": "reply", "reply": {"id": b["id"], "title": self.copy.t(b["ref"], lang)[:20]}} for b in buttons]}}
            if header:
                inter["header"] = header
            return {"type": "interactive", "interactive": inter}
        if not body:
            return None
        return {"type": "text", "text": {"body": body}}


class WhatsAppClient:
    def __init__(self, settings):
        self.s = settings
        self.base = f"https://graph.facebook.com/{settings.wa_graph_version}"

    @property
    def configured(self) -> bool:
        return bool(self.s.wa_access_token and self.s.wa_phone_number_id)

    def _h(self) -> dict:
        return {"Authorization": f"Bearer {self.s.wa_access_token}"}

    async def send(self, to: str, payload: dict) -> bool:
        if not self.configured:
            return False
        body = {"messaging_product": "whatsapp", "recipient_type": "individual", "to": to, **payload}
        async with httpx.AsyncClient(timeout=15) as http:
            r = await http.post(f"{self.base}/{self.s.wa_phone_number_id}/messages", json=body, headers=self._h())
        if r.status_code >= 300:
            log.warning("whatsapp send failed status=%s", r.status_code)
            return False
        return True

    async def download_media(self, media_id: str) -> bytes | None:
        if not self.configured or not media_id:
            return None
        async with httpx.AsyncClient(timeout=30) as http:
            meta = await http.get(f"{self.base}/{media_id}", headers=self._h())
            if meta.status_code >= 300:
                return None
            url = meta.json().get("url")
            if not url:
                return None
            data = await http.get(url, headers=self._h())
            return data.content if data.status_code < 300 else None

    async def upload_audio(self, audio: bytes) -> str | None:
        if not self.configured:
            return None
        async with httpx.AsyncClient(timeout=30) as http:
            r = await http.post(f"{self.base}/{self.s.wa_phone_number_id}/media", headers=self._h(),
                                data={"messaging_product": "whatsapp", "type": "audio/mpeg"},
                                files={"file": ("reply.mp3", audio, "audio/mpeg")})
        return r.json().get("id") if r.status_code < 300 else None

    async def send_template(self, to: str, name: str, lang_code: str) -> bool:
        return await self.send(to, {"type": "template", "template": {"name": name, "language": {"code": lang_code}}})


def load_templates(config_dir) -> dict:
    return yaml.safe_load((config_dir / "templates.yaml").read_text(encoding="utf-8"))


def make_router(container) -> APIRouter:
    router = APIRouter()
    s = container.settings
    client = WhatsAppClient(s)
    renderer = WhatsAppRenderer(container.engine, container.copy)
    seen: OrderedDict[str, None] = OrderedDict()  # in-memory de-duplication of retried deliveries

    @router.get("/webhook/whatsapp")
    async def verify(request: Request):
        q = request.query_params
        if s.wa_verify_token and q.get("hub.mode") == "subscribe" and hmac.compare_digest(q.get("hub.verify_token", ""), s.wa_verify_token):
            return Response(content=q.get("hub.challenge", ""), media_type="text/plain")
        raise HTTPException(status_code=403)

    @router.post("/webhook/whatsapp")
    async def receive(request: Request, bg: BackgroundTasks):
        raw = await request.body()
        if not verify_signature(s.wa_app_secret, raw, request.headers.get("X-Hub-Signature-256")):
            raise HTTPException(status_code=403)
        try:
            payload = await request.json()
        except ValueError:
            raise HTTPException(status_code=400)
        for item in parse_inbound(payload):
            if item["msg_id"] in seen:
                continue
            seen[item["msg_id"]] = None
            while len(seen) > 5000:
                seen.popitem(last=False)
            bg.add_task(handle_item, item)
        return {"ok": True}

    async def handle_item(item: dict) -> None:
        wa_id = item["wa_id"]
        uid = container.uid("whatsapp", wa_id)
        st = container.repo.get_session(uid) or {}
        lang = st.get("lang", "en")
        if item["kind"] == "voice":
            audio = await client.download_media(item["media_id"])
            transcript = container.voice.transcribe(audio, item["mime"], lang) if audio else None
            audio = None  # drop audio bytes immediately
            inp = Inbound("voice", text=transcript or "", transcript_ok=bool(transcript))
        elif item["kind"] == "button":
            inp = Inbound("button", button=item["button"])
        elif item["kind"] == "location":
            inp = Inbound("location")
        else:
            inp = Inbound("text", text=item["text"])
        res = container.process("whatsapp", wa_id, inp, recipient=wa_id)
        out_lang = (res.state or {}).get("lang", lang)
        await deliver(wa_id, res.messages, out_lang, voice_in=item["kind"] == "voice")

    async def deliver(to: str, messages: list[dict], lang: str, voice_in: bool = False) -> None:
        for msg in messages:
            if msg.get("speak") and voice_in:
                text = container.engine.text_of(msg, lang)
                audio = container.voice.synthesize(text, lang)
                if audio:
                    mid = await client.upload_audio(audio)
                    if mid:
                        await client.send(to, {"type": "audio", "audio": {"id": mid}})
                else:
                    container.repo.log_event("voice_fallback", "tts", lang)
            payload = renderer.render(msg, lang)
            if payload:
                await client.send(to, payload)

    router.deliver = deliver  # used by the follow-up scheduler
    router.client = client
    return router
