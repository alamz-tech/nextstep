"""Draft a knowledge-base chunk from the extracted guideline pages (extractive only).

    python scripts/draft_kb_from_sources.py --id prep-what-is-it --query "pre-exposure prophylaxis adolescent girls" [--lang en]

Writes content/kb/<lang>/<id>.md with the best-matching passages QUOTED VERBATIM and
cited by document + page. Nothing is paraphrased or generated: a writer and a
clinician do that next, without adding facts.
"""
import argparse
import math
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from app.retrieval.kb import tokenize  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("--id", required=True)
ap.add_argument("--query", required=True)
ap.add_argument("--lang", default="en")
ap.add_argument("--k", type=int, default=3)
a = ap.parse_args()

pages = []
for f in sorted((ROOT / "sources" / "extracts").glob("*/page-*.txt")):
    for para in re.split(r"\n\s*\n", f.read_text(encoding="utf-8")):
        if len(para.split()) >= 25:
            pages.append((f.parent.name, int(f.stem.split("-")[1]), " ".join(para.split())))
if not pages:
    sys.exit("No extracts. Run scripts/ingest_sources.py first.")
docs = [Counter(tokenize(p[2])) for p in pages]
df = Counter(t for d in docs for t in d)
n = len(docs)
q = tokenize(a.query)
scored = []
for (doc, page, text), tf in zip(pages, docs):
    s = sum(math.log(1 + (n - df[t] + 0.5) / (df[t] + 0.5)) * tf[t] for t in q if t in tf)
    scored.append((s, doc, page, text))
top = [x for x in sorted(scored, reverse=True)[: a.k] if x[0] > 0]
if not top:
    sys.exit("No matching passages. The sources may be silent on this: leave a TODO.")
cites = "; ".join(f"{d} p.{p}" for _, d, p, _ in top)
body = "\n\n".join(f"> {t}\n> — {d}, page {p}" for _, d, p, t in top)
out = ROOT / "content" / "kb" / a.lang / f"{a.id}.md"
out.write_text(f"""---
id: {a.id}
title: "TODO – plain-language title"
topic: {a.id.split('-')[0]}
lang: {a.lang}
age_tier: all
source_document: "{top[0][1]}"
source_section: "{cites}"
review_status: "draft – pending clinician review"
keywords: [{', '.join(sorted(set(q)))}]
buttons: [qa_find, qa_another, menu]
---
TODO – rewrite the quoted passages below in plain language for 15–24 year olds WITHOUT adding facts,
then delete the quotes. Until then this chunk is not served (body starts with TODO).

{body}
""", encoding="utf-8")
print(f"wrote {out.relative_to(ROOT)} from {cites}")
