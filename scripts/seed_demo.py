"""Seed CLEARLY FAKE demo data for recording the video.

Creates demo orgs and accounts, then runs scripted test traffic through the real
API in-process (so every dashboard number is produced by the actual code path,
not typed in). Refuses to run unless DEMO_MODE=true.

    python scripts/seed_demo.py            # uses DATABASE_URL (default data/nextstep.db)
    docker compose exec api python scripts/seed_demo.py

Prints the demo sign-ins at the end.
"""
from __future__ import annotations

import os
import random
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
os.environ.setdefault("SCHEDULER_ENABLED", "false")
os.environ.setdefault("RATE_LIMIT_PER_MIN", "100000")
os.environ.setdefault("RATE_LIMIT_ASK_PER_MIN", "100000")
os.environ.setdefault("RATE_LIMIT_BOX_PER_MIN", "100000")

import logging  # noqa: E402

from fastapi.testclient import TestClient  # noqa: E402

from app.api.auth import hash_password  # noqa: E402
from app.config import get_settings  # noqa: E402
from app.main import create_app  # noqa: E402

PW = os.environ.get("DEMO_PASSWORD", "demo-only-password")
ACCOUNTS = [("demo_admin", "org_admin", "ngo"), ("demo_facilitator", "facilitator", "ngo"), ("demo_clinic", "clinic_partner", "clinic")]

QUESTIONS = [  # fake student questions for the demo question box
    "Can you get HIV from kissing?", "can HIV pass if we share a cup", "is it true you get HIV from hugging",
    "How do condoms protect you?", "how can I protect myself from HIV", "what is PrEP?", "where can I get condoms for free",
    "is PrEP for girls too", "can I test without my parents knowing", "what happens at a clinic test",
    "My name is Demo Student, can I get HIV from kissing?",  # shows name redaction
]


def main() -> None:
    logging.getLogger("httpx").setLevel(logging.WARNING)
    s = get_settings()
    if not s.demo_mode:
        sys.exit("Refusing: DEMO_MODE is not true. Never seed fake data into a real deployment.")
    app = create_app(s)
    c = TestClient(app)
    repo = app.state.container.repo
    random.seed(7)

    # --- orgs & accounts (idempotent)
    orgs = {o["name"]: o["id"] for o in repo.list_orgs()}
    ngo = orgs.get("DEMO NGO (fake)") or repo.create_org("DEMO NGO (fake)", "ngo", "Lagos")
    clinic = orgs.get("DEMO Clinic (fake)") or repo.create_org("DEMO Clinic (fake)", "clinic", "Lagos")
    for user, role, kind in ACCOUNTS:
        if not repo.get_account_by_username(user):
            repo.create_account(user, hash_password(PW), role, ngo if kind == "ngo" else clinic)
    if not repo.get_account_by_username("demo_platform"):
        repo.create_account("demo_platform", hash_password(PW), "platform_admin", None)

    def login(u):
        return {"Authorization": "Bearer " + c.post("/v1/auth/login", json={"username": u, "password": PW}).json()["token"]}

    fac, cli = login("demo_facilitator"), login("demo_clinic")

    # --- scripted learners, through the same chat flow the app uses
    codes = []
    for i in range(60):
        h = {"X-Install-ID": uuid.uuid4().hex}

        def say(**body):
            return c.post("/v1/chat", json=body, headers=h).json()

        say(kind="text", text=random.choice(["Hi", "Hi", "How far"]))
        say(kind="button", button="consent_agree")
        tier = "age_under15" if i % 20 == 0 else random.choice(["age_18_24", "age_18_24", "age_15_17"])
        say(kind="button", button=tier)
        if tier == "age_under15":
            continue
        if random.random() < 0.5:
            c.post("/v1/chat/demo-voice", headers=h)
        elif random.random() < 0.5:
            say(kind="text", text="Can I get HIV from kissing?")
        if random.random() < 0.7:
            say(kind="button", button="check_start")
            for q, opts in [(1, "yn"), (2, "yn"), (3, "yn"), (4, "n"), (5, "n"), (6, "yn")]:
                say(kind="button", button=f"chk_{q}_{random.choice(opts)}")
            if random.random() < 0.7:
                say(kind="button", button="menu_find")
                r = say(kind="text", text=random.choice(["Yaba", "Surulere", "Ikeja"]))
                card = next((m["card"] for m in r["messages"] if m["kind"] == "card"), None)
                if card:
                    codes.append(card["code"])
                    if random.random() < 0.6:
                        say(kind="button", button="ref_remind")
                        say(kind="followup_due")
                        say(kind="button", button=random.choice(["fu_yes", "fu_not_yet"]))
    for code in codes:
        if random.random() < 0.45:
            c.post("/v1/clinic/confirm", json={"code": code}, headers=cli)

    # --- one finished facilitator session with a question box
    ses = c.post("/v1/sessions", json={"setting": "school", "session_date": "2026-11-09", "age_band": "15_17", "audience_size": 45, "lang": "en"},
                 headers=fac).json()
    for _ in range(14):
        c.post(f"/v1/join/{ses['join_code']}/hello")
    for q in QUESTIONS * 2:
        c.post(f"/v1/join/{ses['join_code']}/questions", json={"text": q})
    c.get(f"/v1/sessions/{ses['id']}/themes", headers=fac)

    print("Seeded CLEARLY FAKE demo data (DEMO NGO / DEMO Clinic, scripted test traffic).")
    print(f"  learners: 60 scripted installs, referral codes: {len(codes)}")
    print(f"  facilitator session join code: {ses['join_code']}")
    print("  sign-ins (password from DEMO_PASSWORD, default 'demo-only-password'):")
    for u in ("demo_platform", "demo_admin", "demo_facilitator", "demo_clinic"):
        print(f"    {u}")
    unconfirmed = [code for code in codes if not repo.get_referral(code)["confirmed_day"]]
    if unconfirmed:
        print(f"  an unconfirmed demo referral code for the clinic demo: {unconfirmed[0]}")


if __name__ == "__main__":
    main()
