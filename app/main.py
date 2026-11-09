"""FastAPI entry point: `uvicorn app.main:app`."""
from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles

from .channels import sim, whatsapp
from .config import ROOT, get_settings
from .container import build
from . import dashboard, followup
from .privacy import install_log_scrubbing

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("app")


def create_app(settings=None, repo=None) -> FastAPI:
    settings = settings or get_settings()
    container = build(settings, repo)
    install_log_scrubbing()
    if settings.is_insecure_secret():
        log.warning("HMAC_SECRET is the development default. Set a long random secret before real use.")
    templates = whatsapp.load_templates(settings.config_dir)
    wa = whatsapp.make_router(container)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        task = None
        if settings.scheduler_enabled:
            task = asyncio.create_task(followup.run_forever(container, wa, templates))
        yield
        if task:
            task.cancel()

    app = FastAPI(title="NextStep", version="0.1.0", lifespan=lifespan, docs_url=None, redoc_url=None)
    app.state.container = container
    app.mount("/static", StaticFiles(directory=ROOT / "app" / "static"), name="static")
    app.include_router(wa)
    app.include_router(sim.make_router(container))
    app.include_router(dashboard.make_router(container))

    @app.get("/")
    def root():
        return RedirectResponse("/sim")

    @app.get("/healthz")
    def health():
        return {"ok": True, "llm": container.engine.llm.name, "voice": container.voice.name,
                "demo_mode": settings.demo_mode, "kb_served": sum(1 for c in container.kb.report() if c["served"])}

    return app


app = create_app()
