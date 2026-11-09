import base64
import uuid

from fastapi.testclient import TestClient

from app.main import create_app
from app.store.repo import SQLiteRepository


def make(settings, monkeypatch, **env):
    for k, v in env.items():
        monkeypatch.setenv(k, v)
    from app.config import Settings
    return TestClient(create_app(Settings(), SQLiteRepository(":memory:")))


def test_sim_end_to_end(settings, monkeypatch):
    c = make(settings, monkeypatch)
    sid = uuid.uuid4().hex
    r = c.post("/sim/api/message", json={"sid": sid, "kind": "text", "text": "Hi"}).json()
    assert r["messages"][1]["ref"] == ["consent", "body"]
    c.post("/sim/api/message", json={"sid": sid, "kind": "button", "button": "consent_agree"})
    c.post("/sim/api/message", json={"sid": sid, "kind": "button", "button": "age_18_24"})
    r = c.post("/sim/api/message", json={"sid": sid, "kind": "voice", "text": "Can I get HIV from kissing?"}).json()
    assert r["messages"][0]["ref"] == ["extra", "heard_tpl"]
    assert r["messages"][1].get("voice_fallback") is True   # no TTS configured -> text only, logged
    r = c.post("/sim/api/advance", json={"sid": sid}).json()
    assert any(m.get("ref") == ["followup", "ping"] for m in r["messages"])


def test_dashboard_requires_auth(settings, monkeypatch):
    c = make(settings, monkeypatch, DASHBOARD_PASSWORD="pw-123")
    assert c.get("/dashboard/api/summary").status_code == 401
    tok = base64.b64encode(b"admin:pw-123").decode()
    r = c.get("/dashboard/api/summary?range=7", headers={"Authorization": "Basic " + tok})
    assert r.status_code == 200 and r.json()["range"] == "7"


def test_dashboard_disabled_without_password(settings, monkeypatch):
    c = make(settings, monkeypatch, DASHBOARD_PASSWORD="")
    assert c.get("/dashboard/api/summary").status_code == 503


def test_webhook_rejects_unsigned(settings, monkeypatch):
    c = make(settings, monkeypatch, WHATSAPP_APP_SECRET="s3cret", WHATSAPP_VERIFY_TOKEN="vt")
    assert c.post("/webhook/whatsapp", json={"entry": []}).status_code == 403
    assert c.get("/webhook/whatsapp", params={"hub.mode": "subscribe", "hub.verify_token": "bad", "hub.challenge": "x"}).status_code == 403
    r = c.get("/webhook/whatsapp", params={"hub.mode": "subscribe", "hub.verify_token": "vt", "hub.challenge": "abc"})
    assert r.status_code == 200 and r.text == "abc"
