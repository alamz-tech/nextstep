"""Session kits for facilitators, generated ONLY from the knowledge base in /content.

Nothing here is written from general knowledge: each lesson section is a reviewed
(or draft) chunk with its source; quiz items and myth cards exist only where a
chunk's front matter defines them. Review status is shown on every item.
"""
from __future__ import annotations

CURRICULUM_TODO = ("TODO: map each section to Nigeria's national Family Life and HIV Education (FLHE) curriculum "
                   "for the relevant class level. Needs an education adviser; not done in the prototype.")


def build_kits(kb) -> dict:
    out = {}
    for lang in ("en", "pcm"):
        chunks = [c for c in kb.all if c.lang == lang and kb._servable(c)]
        sections = [{"chunk_id": c.id, "title": c.title, "text": c.body, "source_document": c.source_document,
                     "source_section": c.source_section, "review_status": c.review_status} for c in chunks]
        quiz = [{"statement": q["statement"], "answer": bool(q["answer"]), "explanation": c.body if q.get("explain_from_body") else "",
                 "chunk_id": c.id, "review_status": c.review_status, "source_document": c.source_document}
                for c in chunks for q in c.quiz]
        myths = [{"myth": m["myth"], "fact": m["fact"], "chunk_id": c.id, "review_status": c.review_status,
                  "source_document": c.source_document} for c in chunks for m in c.myths]
        stubs = [c.title for c in kb.all if c.lang == lang and c.is_stub]
        out[lang] = {
            "lesson": {"title": "HIV prevention: questions young people ask", "duration_min": 40,
                       "outline": ["Ground rules: no names, questions are anonymous (5 min)",
                                   "Question box open: students scan the QR code (5 min)",
                                   *[f"{s['title']} (5–10 min)" for s in sections],
                                   "Where to get free, youth-friendly services; support contacts (5 min)"],
                       "sections": sections, "curriculum_alignment": CURRICULUM_TODO,
                       "missing_topics_todo": stubs},
            "quiz": quiz, "myths": myths,
        }
    return out
