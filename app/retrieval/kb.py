"""Knowledge base: markdown chunks with YAML front matter + transparent BM25 search.

Each chunk records: id, topic, lang, age_tier, source_document, source_section,
review_status, keywords, buttons. A chunk whose body is "TODO" is a stub and is
never served. When `require_approved` is on (production), only chunks whose
review_status starts with "approved" are served.
"""
from __future__ import annotations

import math
import re
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

import yaml

STOP = set("""a an the and or but if of to in on at for from by with as is are was were be been being am i me my
you your we our they them he she it its this that these those do does did can could should would will shall may
might must have has had not no yes so what when where which who why how there here just about into than then too very
dey na wey una dem go fit don abeg o e im di wetin""".split())
_TOKEN = re.compile(r"[a-z0-9]+")


def tokenize(text: str) -> list[str]:
    toks = _TOKEN.findall(text.lower())
    out = []
    for t in toks:
        if t in STOP or len(t) < 2:
            continue
        # very light stemming so "kissing"/"kissed" match "kiss"
        for suf in ("ing", "ed", "es", "s"):
            if len(t) > 4 and t.endswith(suf):
                t = t[: -len(suf)]
                break
        out.append(t)
    return out


@dataclass
class Chunk:
    id: str
    lang: str
    title: str
    topic: str
    age_tier: str
    source_document: str
    source_section: str
    review_status: str
    keywords: list[str]
    buttons: list[str]
    body: str
    path: str
    tokens: list[str] = field(default_factory=list)

    @property
    def is_stub(self) -> bool:
        return self.body.strip().upper().startswith("TODO") or not self.body.strip()

    @property
    def is_approved(self) -> bool:
        return self.review_status.lower().startswith("approved")

    @property
    def source_is_todo(self) -> bool:
        return "TODO" in self.source_document


def load_chunk(path: Path) -> Chunk:
    raw = path.read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", raw, re.S)
    if not m:
        raise ValueError(f"{path}: missing YAML front matter")
    meta = yaml.safe_load(m.group(1)) or {}
    required = ["id", "lang", "age_tier", "source_document", "source_section", "review_status"]
    missing = [k for k in required if not meta.get(k)]
    if missing:
        raise ValueError(f"{path}: missing metadata {missing}")
    return Chunk(
        id=meta["id"], lang=meta["lang"], title=str(meta.get("title") or meta["id"].replace("-", " ").capitalize()), topic=meta.get("topic", ""), age_tier=str(meta["age_tier"]),
        source_document=meta["source_document"], source_section=str(meta["source_section"]),
        review_status=meta["review_status"], keywords=[str(k) for k in meta.get("keywords") or []],
        buttons=meta.get("buttons") or ["qa_another", "menu"], body=m.group(2).strip(), path=str(path),
    )


@dataclass
class Hit:
    chunk: Chunk
    score: float
    matched: list[str]


class KnowledgeBase:
    def __init__(self, kb_dir: Path, require_approved: bool = False, k1: float = 1.5, b: float = 0.75):
        self.require_approved = require_approved
        self.all: list[Chunk] = [load_chunk(p) for p in sorted(kb_dir.rglob("*.md"))]
        self.k1, self.b = k1, b
        self._index: dict[str, list[Chunk]] = {}
        for lang in {c.lang for c in self.all}:
            docs = [c for c in self.all if c.lang == lang and self._servable(c)]
            for c in docs:
                # keywords are weighted x3: they are the reviewer-controlled routing signal
                c.tokens = tokenize(c.body) + tokenize(" ".join(c.keywords)) * 3
            self._index[lang] = docs
        self._stats = {lang: self._build_stats(docs) for lang, docs in self._index.items()}

    def _servable(self, c: Chunk) -> bool:
        if c.is_stub:
            return False
        return c.is_approved or not self.require_approved

    @staticmethod
    def _build_stats(docs: list[Chunk]):
        n = len(docs)
        df: Counter = Counter()
        for d in docs:
            df.update(set(d.tokens))
        avgdl = (sum(len(d.tokens) for d in docs) / n) if n else 0
        return n, df, avgdl

    def search(self, query: str, lang: str, tier: str | None, k: int = 3, min_score: float = 1.0) -> list[Hit]:
        langs = [lang] + (["en"] if lang != "en" else [])
        q = tokenize(query)
        if not q:
            return []
        for L in langs:
            docs = self._index.get(L, [])
            if not docs:
                continue
            n, df, avgdl = self._stats[L]
            hits: list[Hit] = []
            for d in docs:
                if tier and d.age_tier not in ("all", tier):
                    continue
                tf = Counter(d.tokens)
                kw = set(tokenize(" ".join(d.keywords)))
                score, matched = 0.0, []
                for t in q:
                    if t not in tf:
                        continue
                    idf = math.log(1 + (n - df[t] + 0.5) / (df[t] + 0.5))
                    f = tf[t]
                    score += idf * f * (self.k1 + 1) / (f + self.k1 * (1 - self.b + self.b * len(d.tokens) / (avgdl or 1)))
                    matched.append(t)
                # Require at least one reviewer keyword to match: transparent and auditable.
                if score >= min_score and kw.intersection(matched):
                    hits.append(Hit(d, round(score, 3), sorted(set(matched))))
            hits.sort(key=lambda h: -h.score)
            if hits:
                return hits[:k]
        return []

    def get(self, chunk_id: str, lang: str) -> Chunk | None:
        for L in (lang, "en"):
            for c in self._index.get(L, []):
                if c.id == chunk_id:
                    return c
        return None

    def report(self) -> list[dict]:
        return [
            {"id": c.id, "title": c.title, "lang": c.lang, "status": c.review_status, "stub": c.is_stub,
             "source": c.source_document, "served": self._servable(c)}
            for c in self.all
        ]
