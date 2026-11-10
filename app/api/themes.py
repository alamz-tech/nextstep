"""Group anonymous question-box submissions into themes.

Transparent by design: a question joins the theme of the knowledge-base chunk it
retrieves (BM25), so every theme with a suggested answer is grounded in reviewed
content with sources. Questions the knowledge base cannot answer go to the LLM
(when one is configured): it may map a question to an existing chunk id, or group
similar questions under a short general label. Anything the LLM returns is
validated (known chunk ids and question ids only, labels redacted and length-capped);
if the LLM is off, fails or returns something invalid, the keyword grouping below is
used instead. Ungrounded groups are always marked "no reviewed answer yet".
Only redacted question text is sent to the LLM.
"""
from __future__ import annotations

import json
import logging
import re
from collections import Counter

from ..llm.base import parse_json
from ..retrieval.kb import tokenize
from .redact import redact

log = logging.getLogger("app.themes")
AI_LABEL = {"en": "{label} (no reviewed answer yet)", "pcm": "{label} (no reviewed answer yet)"}
GROUP_SYSTEM = """You group anonymous questions that students sent to a sexual-health educator.
Input: a JSON list of questions (id, text) and a catalogue of reviewed answers (chunk_id, title).
For each question decide:
- if one catalogue answer clearly answers it, put it in a group with that chunk_id;
- otherwise group it with similar questions under a short, general topic label (2 to 6 words).
Rules: labels describe the topic only. Never put names, places, phone numbers, quotes or personal
details in a label. Do not answer the questions. Use only chunk_ids from the catalogue. Every
question id must appear exactly once."""
GROUP_SCHEMA = {
    "type": "object",
    "properties": {"groups": {"type": "array", "items": {
        "type": "object",
        "properties": {"chunk_id": {"type": "string"}, "label": {"type": "string"},
                       "question_ids": {"type": "array", "items": {"type": "integer"}}},
        "required": ["chunk_id", "label", "question_ids"], "additionalProperties": False}}},
    "required": ["groups"], "additionalProperties": False,
}

OPEN_LABEL = {"en": "Questions about “{kw}” (no reviewed answer yet)",
              "pcm": "Questions about “{kw}” (no reviewed answer yet)"}
OTHER_LABEL = {"en": "Other questions (no reviewed answer yet)", "pcm": "Other questions (no reviewed answer yet)"}


def theme_for(kb, text: str, lang: str, tier: str | None) -> tuple[str, str]:
    hits = kb.search(text, lang, tier)
    if hits:
        c = hits[0].chunk
        return "kb:" + c.id, c.title
    return "open", ""


def _clean_label(label: str) -> str:
    label, _ = redact(re.sub(r"\s+", " ", str(label)).strip(" .\"'“”"))
    label = re.sub(r"\[[A-Z ]+\]", "", label).strip()
    return label[:60]


def _slug(label: str) -> str:
    return "-".join(tokenize(label))[:40] or "other"


def ai_group(llm, kb, open_qs: list[dict], lang: str, tier: str | None) -> dict[int, tuple[str, str]] | None:
    """{question_id: (theme_key, label)} from the LLM, or None to fall back to keywords."""
    if llm is None or getattr(llm, "name", "none") == "none" or not open_qs:
        return None
    catalogue = [{"chunk_id": c.id, "title": c.title} for c in kb._index.get(lang, []) or kb._index.get("en", [])
                 if (not tier or c.age_tier in ("all", tier))]
    user = json.dumps({"questions": [{"id": q["id"], "text": q["text_redacted"]} for q in open_qs],
                       "catalogue": catalogue}, ensure_ascii=False)
    out = parse_json(llm.complete(GROUP_SYSTEM, user, max_tokens=1500, json_schema=GROUP_SCHEMA))
    if not out or not isinstance(out.get("groups"), list):
        return None
    valid_ids = {q["id"] for q in open_qs}
    known = {c["chunk_id"] for c in catalogue}
    res: dict[int, tuple[str, str]] = {}
    for g in out["groups"]:
        cid = str(g.get("chunk_id") or "").strip()
        label = _clean_label(g.get("label") or "")
        for qid in g.get("question_ids") or []:
            if qid not in valid_ids or qid in res:
                continue
            if cid in known:
                c = kb.get(cid, lang)
                res[qid] = ("kb:" + cid, c.title if c else label)
            elif label:
                res[qid] = ("ai:" + _slug(label), AI_LABEL.get(lang, AI_LABEL["en"]).format(label=label))
    if set(res) != valid_ids:  # incomplete or invalid answer: don't trust any of it
        log.warning("ai grouping incomplete (%d of %d); keyword fallback", len(res), len(valid_ids))
        return None
    return res


def regroup(kb, questions: list[dict], lang: str, tier: str | None, llm=None) -> tuple[list[tuple[str, str, int]], dict[int, str]]:
    """Return ([(theme_key, label, count)], {question_id: theme_key})."""
    assign: dict[int, str] = {}
    labels: dict[str, str] = {}
    open_qs: list[dict] = []
    for q in questions:
        key, label = theme_for(kb, q["text_redacted"], lang, tier)
        if key == "open":
            open_qs.append(q)
        else:
            assign[q["id"]] = key
            labels[key] = label
    ai = ai_group(llm, kb, open_qs, lang, tier)
    if ai is not None:
        for qid, (key, label) in ai.items():
            assign[qid] = key
            labels[key] = label
        open_qs = []
    # Cluster the rest by their most frequent shared keyword (words seen in >=2 questions).
    toks = {q["id"]: [t for t in set(tokenize(q["text_redacted"])) if t not in {"name", "number", "hiv"} and len(t) > 2] for q in open_qs}
    freq = Counter(t for ts in toks.values() for t in ts)
    for q in open_qs:
        shared = sorted((t for t in toks[q["id"]] if freq[t] >= 2), key=lambda t: (-freq[t], t))
        if shared:
            key = "open:" + shared[0]
            labels[key] = OPEN_LABEL.get(lang, OPEN_LABEL["en"]).format(kw=shared[0])
        else:
            key = "open:other"
            labels[key] = OTHER_LABEL.get(lang, OTHER_LABEL["en"])
        assign[q["id"]] = key
    counts = Counter(assign.values())
    themes = [(k, labels[k], n) for k, n in counts.most_common()]
    return themes, assign


def suggested_answer(kb, theme_key: str, lang: str) -> dict | None:
    if not theme_key.startswith("kb:"):
        return None
    c = kb.get(theme_key[3:], lang)
    if not c:
        return None
    return {"text": c.body, "draft": not c.is_approved, "sources": [
        {"chunk_id": c.id, "source_document": c.source_document, "source_section": c.source_section,
         "review_status": c.review_status}]}
