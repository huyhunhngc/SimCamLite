#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-Release}"
command -v xcodegen >/dev/null && xcodegen generate --spec "$ROOT/project.yml" --project "$ROOT" --quiet
xcodebuild -project "$ROOT/SimCamLite.xcodeproj" -scheme SimCamLite -configuration "$CONFIG" \
  -derivedDataPath "$ROOT/.build/app" build -quiet
APP="$ROOT/.build/app/Build/Products/$CONFIG/SimCamLite.app"
rm -rf "$ROOT/build/SimCamLite.app"
mkdir -p "$ROOT/build"
cp -R "$APP" "$ROOT/build/"
echo "$ROOT/build/SimCamLite.app"
echo "CLI: scripts/install-cli.sh or the app menu Install Command Line Tool… (symlinks simcam onto PATH)" >&2
