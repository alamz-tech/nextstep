# /sources — guideline PDFs (not committed)

Put the WHO and Nigerian national HIV prevention guideline PDFs here. They are the
**only** permitted source for knowledge-base content. PDFs are git-ignored because of
their size and licences; record each one in `MANIFEST.yaml` instead (title, publisher,
year, URL you downloaded it from, licence).

Workflow:

1. `python scripts/ingest_sources.py` – extracts text page by page into `sources/extracts/<doc>/page-NNN.txt`.
2. `python scripts/draft_kb_from_sources.py --id prep-what-is-it --query "pre-exposure prophylaxis adolescent girls"`
   – finds the best-matching pages and writes a **draft** chunk to `content/kb/en/<id>.md` quoting those
   passages verbatim with document + page in the metadata.
3. A writer turns the quoted passage into plain language **without adding facts**, keeps the citation,
   and a clinician changes `review_status` to `approved – <name>, <date>` after checking it.

If the sources are silent on something, leave `TODO` in the chunk body. It will not be served.
