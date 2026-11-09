"""Group anonymous question-box submissions into themes.

Transparent by design: a question joins the theme of the knowledge-base chunk it
retrieves (BM25), so every theme with a suggested answer is grounded in reviewed
content with sources. Questions the knowledge base cannot answer are grouped by
their most common keyword and marked "no reviewed answer yet" — the facilitator
answers those from their own training or refers students to a service.
"""
from __future__ import annotations

from collections import Counter

from ..retrieval.kb import tokenize

OPEN_LABEL = {"en": "Questions about “{kw}” (no reviewed answer yet)",
              "pcm": "Questions about “{kw}” (no reviewed answer yet)"}
OTHER_LABEL = {"en": "Other questions (no reviewed answer yet)", "pcm": "Other questions (no reviewed answer yet)"}


def theme_for(kb, text: str, lang: str, tier: str | None) -> tuple[str, str]:
    hits = kb.search(text, lang, tier)
    if hits:
        c = hits[0].chunk
        return "kb:" + c.id, c.title
    return "open", ""


def regroup(kb, questions: list[dict], lang: str, tier: str | None) -> tuple[list[tuple[str, str, int]], dict[int, str]]:
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
