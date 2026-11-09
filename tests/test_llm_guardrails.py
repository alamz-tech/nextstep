"""Guardrails around LLM output, using fake LLMs that misbehave on purpose."""
import json
import uuid

from app.engine.engine import Inbound
from conftest import drive


class FakeLLM:
    name = "fake"

    def __init__(self, compose=None, classify=None):
        self.compose, self.classify = compose, classify

    def complete(self, system, user, max_tokens=800, json_schema=None):
        if "safety classifier" in system:
            return json.dumps(self.classify or {"crisis": "none", "intent": "health"})
        return json.dumps(self.compose) if self.compose is not None else None


def answer_text(container, res, lang="en"):
    return "\n".join(container.engine.text_of(m, lang) for m in res.messages)


def test_composed_answer_with_dose_is_blocked(container):
    container.engine.llm = FakeLLM(compose={"answerable": True, "used_chunk_ids": ["transmission-kissing"],
                                            "answer": "No. Also take one tablet of PrEP once a day."})
    uid = "g-" + uuid.uuid4().hex
    drive(container, uid, "menu")
    res = container.process("sim", uid, Inbound("text", text="Can I get HIV from kissing?"))
    t = answer_text(container, res)
    assert "tablet" not in t and "HIV is not passed on by kissing" in t


def test_composed_answer_with_unretrieved_chunk_is_rejected(container):
    container.engine.llm = FakeLLM(compose={"answerable": True, "used_chunk_ids": ["made-up"], "answer": "Invented fact."})
    uid = "g-" + uuid.uuid4().hex
    drive(container, uid, "menu")
    res = container.process("sim", uid, Inbound("text", text="Can I get HIV from kissing?"))
    assert "Invented fact" not in answer_text(container, res)


def test_composed_answer_with_diagnosis_is_blocked(container):
    container.engine.llm = FakeLLM(compose={"answerable": True, "used_chunk_ids": ["transmission-kissing"],
                                            "answer": "You don't have HIV from kissing."})
    uid = "g-" + uuid.uuid4().hex
    drive(container, uid, "menu")
    res = container.process("sim", uid, Inbound("text", text="Can I get HIV from kissing?"))
    assert "You don't have HIV" not in answer_text(container, res)


def test_good_composed_answer_is_used(container):
    container.engine.llm = FakeLLM(compose={"answerable": True, "used_chunk_ids": ["transmission-kissing"],
                                            "answer": "No. Kissing does not pass on HIV."})
    uid = "g-" + uuid.uuid4().hex
    drive(container, uid, "menu")
    res = container.process("sim", uid, Inbound("text", text="Can I get HIV from kissing?"))
    assert "Kissing does not pass on HIV" in answer_text(container, res)


def test_llm_classifier_catches_what_keywords_miss(container):
    container.engine.llm = FakeLLM(classify={"crisis": "self_harm", "intent": "health"})
    uid = "g-" + uuid.uuid4().hex
    drive(container, uid, "menu")
    res = container.process("sim", uid, Inbound("text", text="I just want everything to stop forever"))
    assert any(e[0] == "crisis_escalation" and e[2] == "llm" for e in res.events)


def test_llm_failure_falls_back_safely(container):
    class Broken:
        name = "broken"
        def complete(self, *a, **k):
            return None
    container.engine.llm = Broken()
    uid = "g-" + uuid.uuid4().hex
    drive(container, uid, "menu")
    res = container.process("sim", uid, Inbound("text", text="Can I get HIV from kissing?"))
    assert "HIV is not passed on by kissing" in answer_text(container, res)
