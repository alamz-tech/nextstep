"""Private-check scorer. Pluggable: the rules come from content/check.yaml so the
clinical team can swap in a validated tool without code changes."""
from __future__ import annotations

from pathlib import Path

import yaml


class CheckScorer:
    def __init__(self, path: Path):
        cfg = yaml.safe_load(path.read_text(encoding="utf-8"))
        self.cfg = cfg
        self.questions = cfg["questions"]
        self.scoring = cfg.get("scoring") or {}
        self.threshold = int(cfg.get("threshold_next", 2))
        self.flags = cfg.get("flags") or {}

    @property
    def n(self) -> int:
        return len(self.questions)

    def answers_for(self, i: int) -> list[str]:
        return self.questions[i - 1]["answers"]

    def points(self, qid: str, ans: str) -> int:
        if ans == "rn":
            return 0
        return int((self.scoring.get(qid) or {}).get(ans, 0))

    def flag(self, name: str, qid: str, ans: str) -> bool:
        cond = self.flags.get(name) or {}
        return cond.get(qid) == ans

    def band(self, score: int) -> str:
        return "next" if score >= self.threshold else "low"
