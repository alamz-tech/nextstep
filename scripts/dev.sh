#!/usr/bin/env bash
# Local dev server (no Docker). Demo mode and a local-only admin login unless overridden.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEMO_MODE="${DEMO_MODE:-true}"
export PLATFORM_ADMIN_USER="${PLATFORM_ADMIN_USER:-admin}"
export PLATFORM_ADMIN_PASSWORD="${PLATFORM_ADMIN_PASSWORD:-local-dev-password}"
exec .venv/bin/uvicorn app.main:app --host 127.0.0.1 --port "${PORT:-8077}"
