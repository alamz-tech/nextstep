"""CopyStore: loads copy.json (+ copy_extra.json), resolves [flow, key] refs by language,
fills config-backed placeholders and validates WhatsApp limits.

Placeholders like [VERIFIED HELPLINE 1] are replaced ONLY from config/contacts.yaml.
If a value is not configured, the bracketed placeholder is shown as-is. Nothing is
ever invented here.
"""
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

import yaml

LANGS = ("en", "pcm")
PLACEHOLDER = re.compile(r"\[[A-Z][A-Z0-9 ,'’\-/]*(?:,[^\]]*)?\]")

LIMITS = {"button": 20, "row_title": 24, "row_desc": 72, "list_button": 20}


class CopyStore:
    def __init__(self, content_dir: Path, contacts_file: Path | None = None, retention_text: str | None = None):
        self.data: dict[str, Any] = json.loads((content_dir / "copy.json").read_text(encoding="utf-8"))
        extra_p = content_dir / "copy_extra.json"
        if extra_p.exists():
            extra = json.loads(extra_p.read_text(encoding="utf-8"))
            for k, v in extra.items():
                if not k.startswith("_"):
                    self.data[k] = v
        self.fills: dict[str, str] = {}
        if contacts_file and contacts_file.exists():
            raw = yaml.safe_load(contacts_file.read_text(encoding="utf-8")) or {}
            for k, v in (raw.get("placeholders") or {}).items():
                if v not in (None, ""):
                    self.fills[k.strip("[]")] = str(v)
        if retention_text:
            self.fills.setdefault("RETENTION PERIOD", retention_text)

    def raw(self, flow: str, key: str, lang: str = "en") -> str:
        f = self.data.get(flow) or {}
        return (f.get(lang) or {}).get(key) or (f.get("en") or {}).get(key) or ""

    def fill(self, text: str) -> str:
        def rep(m: re.Match) -> str:
            name = m.group(0)[1:-1]
            return self.fills.get(name, m.group(0))
        out = PLACEHOLDER.sub(rep, text)
        if "[VERIFIED " in out:
            # Never show an unconfirmed helpline: drop any line that still has one.
            out = "\n".join(line for line in out.split("\n") if "[VERIFIED " not in line)
            out = re.sub(r"\n{3,}", "\n\n", out).strip("\n")
        return out

    def t(self, ref: list[str] | tuple[str, str], lang: str = "en", **params: Any) -> str:
        text = self.fill(self.raw(ref[0], ref[1], lang))
        for k, v in params.items():
            text = text.replace("{" + k + "}", str(v))
        return text

    def is_draft(self, ref) -> bool:
        f = self.data.get(ref[0]) or {}
        return ref[1] in (f.get("_draft") or [])

    def public_json(self) -> dict[str, Any]:
        """Copy as served to the web simulator (placeholders filled from config)."""
        out: dict[str, Any] = {}
        for flow, v in self.data.items():
            if flow.startswith("_"):
                continue
            out[flow] = {"_draft": v.get("_draft", [])}
            for lang in LANGS:
                out[flow][lang] = {k: self.fill(s) for k, s in (v.get(lang) or {}).items()}
        return out

    # ---- validation (used by tests / CI) ----
    def validate(self) -> list[str]:
        errs: list[str] = []
        for flow, v in self.data.items():
            if flow.startswith("_") or flow == "sim":
                continue
            en, pcm = set((v.get("en") or {}).keys()), set((v.get("pcm") or {}).keys())
            if en != pcm:
                errs.append(f"{flow}: key parity en/pcm differs: {sorted(en ^ pcm)}")
            for d in v.get("_draft", []):
                if d not in en:
                    errs.append(f"{flow}: _draft key {d!r} missing")
            for lang in LANGS:
                for k, s in (v.get(lang) or {}).items():
                    if k.startswith("btn_") and len(s) > LIMITS["button"]:
                        errs.append(f"{flow}.{lang}.{k}: button >{LIMITS['button']} chars ({len(s)})")
                    if k.startswith("row_") and k.endswith("_desc") and len(s) > LIMITS["row_desc"]:
                        errs.append(f"{flow}.{lang}.{k}: row description >{LIMITS['row_desc']} chars")
                    elif k.startswith("row_") and not k.endswith("_desc") and len(s) > LIMITS["row_title"]:
                        errs.append(f"{flow}.{lang}.{k}: row title >{LIMITS['row_title']} chars ({len(s)})")
                    if k == "list_button" and len(s) > LIMITS["list_button"]:
                        errs.append(f"{flow}.{lang}.{k}: list button too long")
        return errs

    def unfilled_placeholders(self) -> set[str]:
        found: set[str] = set()
        for flow, v in self.data.items():
            if flow.startswith("_"):
                continue
            for lang in LANGS:
                for s in (v.get(lang) or {}).values():
                    for m in PLACEHOLDER.findall(self.fill(s)):
                        found.add(m)
        return found
