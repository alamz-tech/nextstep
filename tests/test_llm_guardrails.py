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
    assert "tablet" not in t and "do not carry a real risk of HIV" in t


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
    assert "do not carry a real risk of HIV" in answer_text(container, res)


# ---------------- AI grouping of question-box questions ----------------
from app.api.themes import regroup  # noqa: E402


class GroupLLM:
    name = "fake"

    def __init__(self, out):
        self.out, self.calls = out, []

    def complete(self, system, user, max_tokens=800, json_schema=None):
        self.calls.append(user)
        return json.dumps(self.out) if self.out is not None else None


QS = [{"id": 1, "text_redacted": "Can I get HIV from kissing?"},
      {"id": 2, "text_redacted": "is it normal to feel sad after a breakup"},
      {"id": 3, "text_redacted": "how do i stop thinking about my ex"},
      {"id": 4, "text_redacted": "periods hurt a lot is that normal"}]


def test_ai_groups_questions_bm25_cannot_place(container):
    llm = GroupLLM({"groups": [
        {"chunk_id": "", "label": "Breakups and feelings", "question_ids": [2, 3]},
        {"chunk_id": "", "label": "Period pain, call 08031234567", "question_ids": [4]}]})
    themes, assign = regroup(container.kb, QS, "en", None, llm=llm)
    assert assign[1] == "kb:transmission-kissing"           # BM25 still decides grounded matches
    assert "from kissing" not in llm.calls[0]                     # only the unplaced questions go to the LLM
    assert assign[2] == assign[3] and assign[2].startswith("ai:")
    labels = {k: l for k, l, _ in themes}
    assert "no reviewed answer yet" in labels[assign[2]]
    assert "0803" not in labels[assign[4]]                     # labels are redacted


def test_ai_grouping_rejects_unknown_ids_and_falls_back(container):
    llm = GroupLLM({"groups": [{"chunk_id": "", "label": "Feelings", "question_ids": [2, 99]}]})  # 3 and 4 missing
    themes, assign = regroup(container.kb, QS, "en", None, llm=llm)
    assert not any(k.startswith("ai:") for k in assign.values())
    assert all(k.startswith(("kb:", "open:")) for k in assign.values())


def test_ai_grouping_failure_uses_keywords(container):
    themes, assign = regroup(container.kb, QS, "en", None, llm=GroupLLM(None))
    assert assign[1] == "kb:transmission-kissing" and not any(k.startswith("ai:") for k in assign.values())
