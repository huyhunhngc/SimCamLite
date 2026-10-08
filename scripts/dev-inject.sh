#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST=/Users/Shared/SimCamLite
xcodebuild -project "$ROOT/SimCamLite.xcodeproj" -scheme SimCamLiteInject -sdk iphonesimulator -arch arm64 \
  -configuration Debug -derivedDataPath "$ROOT/.build/inject" build -quiet
PRODUCTS="$ROOT/.build/inject/Build/Products/Debug-iphonesimulator"
mkdir -p "$DEST"
rm -rf "$DEST/SimCamLiteInject.framework"
cp -R "$PRODUCTS/SimCamLiteInject.framework" "$DEST/"
cp "$PRODUCTS/SimCamLiteLoader.dylib" "$DEST/"
codesign -fs - "$DEST/SimCamLiteLoader.dylib" "$DEST/SimCamLiteInject.framework" >/dev/null 2>&1
if [ $# -ge 1 ]; then
  SIMCTL_CHILD_DYLD_INSERT_LIBRARIES="$DEST/SimCamLiteLoader.dylib" xcrun simctl launch --terminate-running-process booted "$1"
fi
