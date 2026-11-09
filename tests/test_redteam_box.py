"""Red-team: anonymous question box and attempts to reach individual data."""
from pathlib import Path

import pytest
import yaml
from fastapi.testclient import TestClient

from app.main import create_app
from app.store.repo import SQLiteRepository

Y = yaml.safe_load((Path(__file__).parent / "redteam.yaml").read_text())
BOX, ACCESS = Y["box_cases"], Y["access_cases"]


@pytest.fixture(scope="module")
def world():
    import os
    os.environ.update({"PLATFORM_ADMIN_USER": "root", "PLATFORM_ADMIN_PASSWORD": "root-password-123", "RATE_LIMIT_BOX_PER_MIN": "1000",
                       "DATABASE_URL": "sqlite://:memory:", "LLM_PROVIDER": "none", "SCHEDULER_ENABLED": "false",
                       "HMAC_SECRET": "test-secret"})
    from app.config import Settings
    c = TestClient(create_app(Settings(), SQLiteRepository(":memory:")))

    def login(u, p):
        return {"Authorization": "Bearer " + c.post("/v1/auth/login", json={"username": u, "password": p}).json()["token"]}

    root = login("root", "root-password-123")
    orgs = {n: c.post("/v1/admin/orgs", json={"name": n, "kind": "ngo"}, headers=root).json()["id"] for n in ("Org A", "Org B", "Clinic C")}
    for u, role, o in [("fac_a", "facilitator", "Org A"), ("fac_b", "facilitator", "Org B"), ("admin_a", "org_admin", "Org A"),
                       ("admin_b", "org_admin", "Org B"), ("clinic_c", "clinic_partner", "Clinic C")]:
        c.post("/v1/admin/users", json={"username": u, "password": "password-123456", "role": role, "org_id": orgs[o]}, headers=root)
    H = {k: login(u, "password-123456") for k, u in [("facilitator", "fac_a"), ("other_facilitator", "fac_b"), ("org_admin", "admin_a"),
                                                      ("other_org_admin", "admin_b"), ("clinic", "clinic_c")]}
    H["anonymous"] = {}
    H["learner"] = {"X-Install-ID": "a" * 32}
    H["learner_other"] = {"X-Install-ID": "b" * 32}
    ses = c.post("/v1/sessions", json={"setting": "school", "session_date": "2026-11-12", "age_band": "15_17", "audience_size": 30},
                 headers=H["facilitator"]).json()
    c.post(f"/v1/join/{ses['join_code']}/questions", json={"text": "My name is Amaka, can I get HIV from kissing my boyfriend?"})
    svc = c.get("/v1/services", headers=H["learner"]).json()["services"][0]["id"]
    code = c.post("/v1/referrals", json={"service_id": svc}, headers=H["learner"]).json()["code"]
    return {"c": c, "H": H, "sid": ses["id"], "join": ses["join_code"], "code": code}


@pytest.mark.parametrize("case", BOX, ids=[x["id"] for x in BOX])
def test_box(world, case):
    c = world["c"]
    r = c.post(f"/v1/join/{world['join']}/questions", json={"text": case["text"]})
    assert r.status_code == 200, r.text
    body = r.json()
    exp = case["expect"]
    assert body["status"] == exp["status"], body
    if "crisis" in exp:
        assert body["crisis"]["crisis"] == exp["crisis"]
    dump = c.app.state.container.repo.dump_all_text()
    for s in exp.get("not_stored", []):
        assert s not in dump, f"{s!r} was stored"
    if "stored_contains" in exp:
        assert exp["stored_contains"] in dump


@pytest.mark.parametrize("case", ACCESS, ids=[x["id"] for x in ACCESS])
def test_access(world, case):
    c = world["c"]
    path = case["path"].replace("{sid}", world["sid"])
    body = {k: (v.replace("{code}", world["code"]) if isinstance(v, str) else v) for k, v in (case.get("body") or {}).items()}
    r = c.request(case["method"], path, headers=world["H"][case["as"]], json=body if case["method"] != "GET" else None)
    assert r.status_code == case["expect"], (r.status_code, r.text[:200])
    for s in case.get("must_not_contain", []):
        assert s.replace("{code}", world["code"]) not in r.text
