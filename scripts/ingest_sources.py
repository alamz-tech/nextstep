"""Extract text from every PDF in /sources into sources/extracts/<doc>/page-NNN.txt."""
import re
import sys
from pathlib import Path

from pypdf import PdfReader

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "sources"
pdfs = sorted(SRC.glob("*.pdf"))
if not pdfs:
    sys.exit("No PDFs in /sources. Add the WHO and Nigerian national guideline PDFs first.")
for pdf in pdfs:
    slug = re.sub(r"[^a-z0-9]+", "-", pdf.stem.lower()).strip("-")
    out = SRC / "extracts" / slug
    out.mkdir(parents=True, exist_ok=True)
    reader = PdfReader(str(pdf))
    for i, page in enumerate(reader.pages, start=1):
        (out / f"page-{i:03d}.txt").write_text(page.extract_text() or "", encoding="utf-8")
    print(f"{pdf.name}: {len(reader.pages)} pages -> {out.relative_to(ROOT)}")
