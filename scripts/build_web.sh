#!/usr/bin/env bash
# Build the Flutter web app served by the API at /app/.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/sync_flutter_assets.sh
cd app_flutter
flutter pub get
flutter build web --release --base-href /app/ --no-web-resources-cdn
echo "Built app_flutter/build/web (served at /app/)"
