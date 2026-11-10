"""FastAPI entry point: `uvicorn app.main:app`.

Mounts:
  /v1/...        learner, staff, clinic and dashboard API
  /app/          Flutter web build (learner app, student join page, facilitator & clinic screens)
  /dashboard     aggregate impact dashboard (sign in as platform/org admin)
  /webhook/whatsapp  only when FEATURE_WHATSAPP=true
  /sim           legacy chat simulator, only when SIM_ENABLED=true (testing tool)
"""
from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

from . import dashboard, followup
from .api import chat, learner, staff
from .api.auth import bootstrap_admin
from .api.ratelimit import RateLimiter
from .config import ROOT, get_settings
from .container import build
from .privacy import install_log_scrubbing

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("app")


def create_app(settings=None, repo=None) -> FastAPI:
    settings = settings or get_settings()
    container = build(settings, repo)
    install_log_scrubbing()
    bootstrap_admin(container)
    if settings.is_insecure_secret():
        log.warning("HMAC_SECRET is the development default. Set a long random secret before real use.")

    wa = None
    templates = {}
    if settings.feature_whatsapp:
        from .channels import whatsapp
        templates = whatsapp.load_templates(settings.config_dir)
        wa = whatsapp.make_router(container)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        task = asyncio.create_task(followup.run_forever(container, wa, templates)) if settings.scheduler_enabled else None
        yield
        if task:
            task.cancel()

    app = FastAPI(title="NextStep API", version="1.0.0", lifespan=lifespan, docs_url="/v1/docs" if settings.demo_mode else None,
                  redoc_url=None, openapi_url="/v1/openapi.json" if settings.demo_mode else None)
    app.state.container = container
    app.state.ratelimiter = RateLimiter()
    if settings.demo_mode:
        # Lets `flutter run -d chrome` (random localhost port) talk to the local API during development.
        app.add_middleware(CORSMiddleware, allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?",
                           allow_methods=["*"], allow_headers=["*"])

    @app.middleware("http")
    async def security_headers(request: Request, call_next):
        resp = await call_next(request)
        resp.headers.setdefault("X-Content-Type-Options", "nosniff")
        resp.headers.setdefault("Referrer-Policy", "no-referrer")
        if request.url.path.startswith("/v1/"):
            resp.headers.setdefault("Cache-Control", "no-store")
        elif request.url.path.startswith("/app/"):
            # Revalidate every time so a new web build reaches users immediately (ETag keeps it cheap).
            resp.headers.setdefault("Cache-Control", "no-cache")
        return resp

    app.mount("/static", StaticFiles(directory=ROOT / "app" / "static"), name="static")
    app.include_router(chat.make_router(container))
    app.include_router(learner.make_router(container))
    app.include_router(staff.make_router(container))
    app.include_router(dashboard.make_router(container))
    if wa is not None:
        app.include_router(wa)
    if settings.sim_enabled:
        from .channels import sim
        app.include_router(sim.make_router(container))

    web = settings.web_app_dir
    if (web / "index.html").exists():
        app.mount("/app", StaticFiles(directory=web, html=True), name="webapp")
    else:
        @app.get("/app/")
        def no_web():
            return HTMLResponse("<p>Flutter web build not found. Run <code>scripts/build_web.sh</code>.</p>", status_code=503)

    @app.get("/")
    def root():
        return RedirectResponse("/app/")

    @app.get("/healthz")
    def health():
        return {"ok": True, "llm": container.engine.llm.name, "voice": container.voice.name, "demo_mode": settings.demo_mode,
                "kb_served": sum(1 for c in container.kb.report() if c["served"]),
                "channels": {"whatsapp": settings.feature_whatsapp, "simulator": settings.sim_enabled}}

    return app


app = create_app()
