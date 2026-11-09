#!/usr/bin/env bash
# Copy the design copy files into the Flutter app so it works offline on first launch.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p app_flutter/assets/content
cp content/copy.json content/copy_extra.json content/tokens.json app_flutter/assets/content/
