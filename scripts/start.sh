#!/usr/bin/env sh
# Container entrypoint (Docker Compose and Cloud Run).
# In DEMO_MODE, seed clearly fake demo data if the database is empty (Cloud Run's disk resets on restart).
set -e
if [ "${DEMO_MODE:-true}" = "true" ] && [ "${SEED_DEMO_ON_START:-false}" = "true" ]; then
  python scripts/seed_demo.py --if-empty || echo "demo seed skipped"
fi
# --proxy-headers + forwarded-allow-ips: take the real client IP from the load balancer
# (needed so per-person rate limits work behind Cloud Run's proxy).
exec uvicorn app.main:app --host 0.0.0.0 --port "${PORT:-8077}" --no-access-log \
  --proxy-headers --forwarded-allow-ips="${FORWARDED_ALLOW_IPS:-127.0.0.1}"
