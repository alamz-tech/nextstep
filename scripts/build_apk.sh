#!/usr/bin/env bash
# Build small per-ABI Android APKs. API_BASE must be reachable from the phone.
#   scripts/build_apk.sh https://nextstep.example.org
#   scripts/build_apk.sh http://10.0.2.2:8077      # Android emulator -> this machine
set -euo pipefail
API_BASE="${1:-http://10.0.2.2:8077}"
cd "$(dirname "$0")/.."
scripts/sync_flutter_assets.sh
cd app_flutter
flutter pub get
flutter build apk --release --split-per-abi --dart-define=API_BASE="$API_BASE"
ls -lh build/app/outputs/flutter-apk/*.apk
