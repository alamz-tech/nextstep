import hashlib
import hmac
import json
import time
import uuid

from app.copy_store import CopyStore
from app.dashboard import summarise
from app.engine.engine import Inbound
from app.engine.safety import post_check
from app.privacy import ReminderCipher, hash_id, scrub
from app.channels.whatsapp import parse_inbound, verify_signature
from conftest import ROOT, drive


def test_copy_valid_and_parity():
    c = CopyStore(ROOT / "content")
    assert c.validate() == []


def test_hmac_is_one_way_and_salted():
    a = hash_id("+2348012345678", "s1")
    assert a != hash_id("+2348012345678", "s2")
    assert "2348012345678" not in a and len(a) == 64


def test_log_scrubbing():
    s = scrub('received {"from": "2348012345678", "body": "I was raped"} from +234 801 234 5678')
    assert "2348012345678" not in s and "raped" not in s and "801" not in s


def test_no_message_text_persisted(container):
    uid = "u-" + uuid.uuid4().hex
    drive(container, uid, "menu")
    secret_phrase = "zebra-unique-question-about-kissing"
    container.process("sim", uid, Inbound("text", text=f"Can I get HIV from kissing {secret_phrase}"))
    container.process("sim", uid, Inbound("text", text="my boyfriend hit me and I feel bad xylophone"))
    dump = container.repo.dump_all_text()
    assert secret_phrase not in dump and "xylophone" not in dump and "boyfriend" not in dump
    assert uid not in dump  # raw session id never stored, only its HMAC


def test_stop_and_delete_erase_everything(container):
    for word in ("STOP", "DELETE"):
        uid = "u-" + uuid.uuid4().hex
        drive(container, uid, "menu")
        container.process("sim", uid, Inbound("button", button="menu_find"))
        container.process("sim", uid, Inbound("text", text="Yaba"))
        container.process("sim", uid, Inbound("button", button="ref_remind"))
        h = container.uid("sim", uid)
        assert container.repo.get_session(h) and container.repo.pending_reminders(h)
        container.process("sim", uid, Inbound("text", text=word))
        assert container.repo.get_session(h) is None
        assert container.repo.pending_reminders(h) == []


def test_under15_stores_nothing_but_aggregate(container):
    uid = "u-" + uuid.uuid4().hex
    drive(container, uid, "age")
    before = container.repo.count_rows("sessions")
    container.process("sim", uid, Inbound("button", button="age_under15"))
    assert container.repo.get_session(container.uid("sim", uid)) is None
    assert container.repo.count_rows("sessions") == before - 1
    rows = container.repo.event_rows(None)
    assert any(r["event"] == "age_tier_selected" and r["dim1"] == "under_15" for r in rows)


def test_crisis_runs_before_every_state(container):
    for setup in ("fresh", "consent", "age", "menu", "qa", "check", "loc"):
        uid = "u-" + uuid.uuid4().hex
        drive(container, uid, setup)
        res = container.process("sim", uid, Inbound("text", text="I want to kill myself"))
        assert any(e[0] == "crisis_escalation" for e in res.events), setup


def test_consent_required_before_anything(container):
    uid = "u-" + uuid.uuid4().hex
    res = container.process("sim", uid, Inbound("button", button="menu_find"))
    assert ["consent", "body"] in [m.get("ref") for m in res.messages]


def test_ttl_purge(container):
    uid = "u-" + uuid.uuid4().hex
    drive(container, uid, "menu")
    out = container.repo.purge_expired(session_ttl_s=3600, events_retention_days=365, now=int(time.time()) + 7200)
    assert out["sessions"] >= 1
    assert container.repo.get_session(container.uid("sim", uid)) is None


def test_events_reject_free_text(container):
    import pytest
    with pytest.raises(ValueError):
        container.repo.log_event("question_asked", "can i get hiv from kissing", "")
    with pytest.raises(ValueError):
        container.repo.log_event("made_up_event")


def test_post_check_blocks_dose_and_diagnosis():
    assert post_check("Take one tablet once a day for 28 days.") == "dose"
    assert post_check("You should take 300mg.") == "dose"
    assert post_check("From what you say, you have HIV.") == "diagnosis"
    assert post_check("You are HIV negative, don't worry.") == "diagnosis"
    assert post_check("Call 0800 123 4567 now") == "phone_number"
    assert post_check("HIV is not passed on by kissing.") is None


def test_reminder_cipher_roundtrip():
    from cryptography.fernet import Fernet
    c = ReminderCipher(Fernet.generate_key().decode())
    tok = c.encrypt("2348012345678")
    assert "2348012345678" not in tok and c.decrypt(tok) == "2348012345678"
    assert not ReminderCipher("").available


def test_whatsapp_signature_and_parse():
    body = json.dumps({"entry": [{"changes": [{"value": {"messages": [
        {"from": "234800", "id": "m1", "type": "text", "text": {"body": "Hi"}},
        {"from": "234800", "id": "m2", "type": "interactive", "interactive": {"button_reply": {"id": "consent_agree"}}},
        {"from": "234800", "id": "m3", "type": "audio", "audio": {"id": "media1", "mime_type": "audio/ogg"}},
    ]}}]}]}).encode()
    sig = "sha256=" + hmac.new(b"appsecret", body, hashlib.sha256).hexdigest()
    assert verify_signature("appsecret", body, sig)
    assert not verify_signature("appsecret", body, "sha256=deadbeef")
    assert not verify_signature("", body, sig)
    items = parse_inbound(json.loads(body))
    assert [i["kind"] for i in items] == ["text", "button", "voice"]
    assert items[1]["button"] == "consent_agree"


def test_dashboard_small_cell_suppression():
    today = __import__("datetime").date(2026, 11, 9)
    base = dict(dim1="", dim2="", state="", tier="", lang="", setting="", org="")
    rows = [dict(base, day="2026-11-08", event="conversation_started", dim1="en", count=12),
            dict(base, day="2026-11-08", event="crisis_escalation", dim1="violence", count=2),
            dict(base, day="2026-11-08", event="check_completed", dim1="next", count=4)]
    d = summarise(rows, "7", today=today)
    kp = {k["key"]: k["v"] for k in d["kpis"]}
    assert kp["conversations"] == "12" and kp["crisis"] == "<5" and kp["checks"] == "<5"
    assert d["funnel"][1]["conv"].startswith("–")


def test_unverified_services_hidden_outside_demo(settings, monkeypatch):
    from app.services import ServiceFinder
    f = ServiceFinder(settings.services_csv, demo_mode=False)
    assert f.find("Yaba, Lagos", "18_24") == []
    f2 = ServiceFinder(settings.services_csv, demo_mode=True)
    assert f2.find("Yaba, Lagos", "18_24")
    assert all(s.accepts_under_18 for s in f2.find("Yaba", "15_17"))


def test_unreviewed_kb_not_served_in_production(settings):
    from app.retrieval.kb import KnowledgeBase
    kb = KnowledgeBase(settings.content_dir / "kb", require_approved=True)
    assert kb.search("can i get hiv from kissing", "en", "18_24") == []
    kb2 = KnowledgeBase(settings.content_dir / "kb", require_approved=False)
    assert kb2.search("can i get hiv from kissing", "en", "18_24")[0].chunk.id == "transmission-kissing"


def test_kb_chunks_have_required_metadata(settings):
    from app.retrieval.kb import KnowledgeBase
    kb = KnowledgeBase(settings.content_dir / "kb")
    for c in kb.all:
        assert c.source_document and c.source_section and c.review_status and c.lang in ("en", "pcm", "ha")


def test_followup_flow_logs_outcomes(container):
    uid = "u-" + uuid.uuid4().hex
    drive(container, uid, "menu")
    container.process("sim", uid, Inbound("button", button="menu_find"))
    container.process("sim", uid, Inbound("text", text="Surulere"))
    container.process("sim", uid, Inbound("button", button="ref_remind"))
    h = container.uid("sim", uid)
    assert len(container.repo.pending_reminders(h)) == 2
    res = container.process("sim", uid, Inbound("followup_due", followup_kind="day3"))
    assert ["followup", "ping"] in [m.get("ref") for m in res.messages]
    res = container.process("sim", uid, Inbound("button", button="fu_yes"))
    assert ("visit_confirmed", "", "") in res.events
    assert container.repo.pending_reminders(h) == []


def test_unverified_helplines_never_shown(tmp_path):
    """A line holding an empty [VERIFIED ...] placeholder is dropped, never shown."""
    contacts = tmp_path / "contacts.yaml"
    contacts.write_text('placeholders:\n  "[VERIFIED HELPLINE 1]": "0800 000 0000"\n  "[VERIFIED HELPLINE 2]": ""\n')
    c = CopyStore(ROOT / "content", contacts)
    text = c.t(("crisis", "violence"), "en")
    assert "0800 000 0000" in text and "[VERIFIED" not in text
    assert "[VERIFIED" not in c.t(("age", "under15"), "pcm")
    for flow in c.public_json().values():
        for lang in ("en", "pcm"):
            for v in (flow.get(lang) or {}).values():
                assert "[VERIFIED" not in v
