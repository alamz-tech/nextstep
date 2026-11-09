"""Background loop: sends due WhatsApp check-ins (template messages, 10:00–18:00 WAT)
and runs the TTL deletion sweep."""
from __future__ import annotations

import asyncio
import logging
import time
from datetime import datetime, timedelta, timezone

from .engine.engine import Inbound

log = logging.getLogger("app.followup")
WAT = timezone(timedelta(hours=1))


def in_send_window(templates: dict, now: datetime | None = None) -> bool:
    w = templates.get("send_window_wat") or {"start_hour": 10, "end_hour": 18}
    h = (now or datetime.now(WAT)).astimezone(WAT).hour
    return w["start_hour"] <= h < w["end_hour"]


async def tick(container, wa_router, templates: dict) -> dict:
    s = container.settings
    purged = container.repo.purge_expired(s.session_ttl_hours * 3600, s.events_retention_days,
                                          question_ttl_s=s.question_ttl_hours * 3600)
    sent = 0
    if wa_router is not None and wa_router.client.configured and in_send_window(templates):
        for rem in container.repo.due_reminders(int(time.time()), channel="whatsapp"):
            to = container.cipher.decrypt(rem.recipient_enc)
            container.repo.mark_reminder_sent(rem.id)  # once only, even if sending fails
            if not to:
                continue
            kind = rem.kind.split("|")[0]
            tpl = (templates.get("followup_checkin") or {}).get("day7" if kind == "day7" else "day3") or {}
            code = ((tpl.get("languages") or {}).get(rem.lang) or {}).get("code", "en")
            if await wa_router.client.send_template(to, tpl.get("name", ""), code):
                sent += 1
                # Put the session in follow-up state so the quick replies are handled.
                container.process("whatsapp", to, Inbound("followup_due", followup_kind=kind))
    return {"purged": purged, "sent": sent}


async def run_forever(container, wa_router, templates: dict) -> None:
    while True:
        try:
            await tick(container, wa_router, templates)
        except Exception:  # keep the loop alive; details stay out of logs
            log.exception("follow-up tick failed")
        await asyncio.sleep(container.settings.scheduler_interval_s)
