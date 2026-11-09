#!/usr/bin/env bash
# Local dev server (no Docker). Uses a demo-only dashboard password unless one is set.
set -euo pipefail
cd "$(dirname "$0")/.."
export DASHBOARD_PASSWORD="${DASHBOARD_PASSWORD:-local-demo}"
exec .venv/bin/uvicorn app.main:app --host 127.0.0.1 --port "${PORT:-8077}"
