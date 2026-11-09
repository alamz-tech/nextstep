"""Referral directory over data/services.csv. Area-name matching, no geolocation."""
from __future__ import annotations

import csv
import re
from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path


@dataclass
class Service:
    id: str
    name: str
    address: str
    area: str
    aliases: list[str]
    state: str
    lga: str
    days: str
    hours: str
    is_free: bool
    youth_friendly: bool
    accepts_under_18: bool
    services: list[str]
    verified: bool
    verified_at: date | None
    maps_url: str


def _b(v: str) -> bool:
    return str(v).strip().lower() in {"true", "1", "yes", "y"}


class ServiceFinder:
    def __init__(self, csv_path: Path, demo_mode: bool, max_age_days: int = 90, today: date | None = None):
        self.demo_mode = demo_mode
        self.max_age = timedelta(days=max_age_days)
        self.today = today
        self.rows: list[Service] = []
        with open(csv_path, newline="", encoding="utf-8") as f:
            for r in csv.DictReader(f):
                va = r.get("verified_at") or ""
                self.rows.append(Service(
                    id=r["id"], name=r["name"], address=r["address"], area=r["area"],
                    aliases=[a.strip().lower() for a in (r.get("area_aliases") or "").split("|") if a.strip()] + [r["area"].lower()],
                    state=r["state"], lga=r.get("lga") or "", days=r["days"], hours=r["hours"], is_free=_b(r["is_free"]),
                    youth_friendly=_b(r["youth_friendly"]), accepts_under_18=_b(r["accepts_under_18"]),
                    services=[s for s in (r.get("services") or "").split("|") if s], verified=_b(r["verified"]),
                    verified_at=date.fromisoformat(va) if va else None, maps_url=r.get("maps_url") or "",
                ))

    def is_showable(self, s: Service) -> bool:
        if s.verified and s.verified_at and (self.today or date.today()) - s.verified_at <= self.max_age:
            return True
        # Unverified (or stale) rows only appear in demo mode, always tagged as demo data.
        return self.demo_mode and not s.verified

    def find(self, area_text: str, tier: str | None) -> list[Service]:
        q = re.sub(r"[^a-z ]", " ", area_text.lower())
        words = set(q.split())
        out = []
        for s in self.rows:
            if not self.is_showable(s):
                continue
            if tier == "15_17" and not s.accepts_under_18:
                continue
            if any((a in q) if " " in a else (a in words) for a in s.aliases):
                out.append(s)
        out.sort(key=lambda s: (not s.verified, s.id))
        return out

    def demo_default(self, tier: str | None) -> list[Service]:
        """'Use demo location' in the simulator = Yaba (the design's sample area)."""
        return self.find("Yaba, Lagos", tier)

    def list(self, state: str | None, lga: str | None, tier: str | None) -> list[Service]:
        out = []
        for s in self.rows:
            if not self.is_showable(s):
                continue
            if state and s.state.lower() != state.lower():
                continue
            if lga and s.lga.lower() != lga.lower():
                continue
            if tier == "15_17" and not s.accepts_under_18:
                continue
            out.append(s)
        out.sort(key=lambda s: (not s.verified, s.lga, s.id))
        return out

    def to_public(self, s: Service) -> dict:
        return {"id": s.id, "name": s.name, "address": s.address, "area": s.area, "lga": s.lga, "state": s.state,
                "days": s.days, "hours": s.hours, "is_free": s.is_free, "youth_friendly": s.youth_friendly,
                "accepts_under_18": s.accepts_under_18, "services": s.services, "verified": s.verified,
                "verified_at": s.verified_at.isoformat() if s.verified_at else None, "demo": not s.verified,
                "maps_url": s.maps_url if s.verified else "", "aliases": s.aliases}

    def by_id(self, sid: str) -> Service | None:
        return next((s for s in self.rows if s.id == sid), None)
