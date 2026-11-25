#!/bin/bash
# Runs an iOS app build (Debug-iphoneos) on this Mac as "Designed for iPad" with SimCamLite injected.
# Usage: scripts/mac-inject.sh <path/to/Debug-iphoneos/App.app>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
NAME="$(basename "$APP" .app)"
DEST=/Users/Shared/SimCamLite/iphoneos
SHM=/Users/Shared/SimCamLite/frames.shm

# The newest process of the app running on this Mac, skipping simulator processes of the same name.
mac_pid() {
  for pid in $(pgrep -x "$NAME" | sort -rn); do
    ps -o comm= -p "$pid" | grep -q CoreSimulator || { echo "$pid"; return; }
  done
}

if [ -n "$(mac_pid)" ]; then
  echo "$NAME is already running. Quit it first." >&2
  exit 1
fi
[ -f "$SHM" ] || { echo "Open SimCamLite on this Mac first ($SHM is missing)." >&2; exit 1; }

xcodebuild -project "$ROOT/SimCamLite.xcodeproj" -scheme SimCamLiteInject -sdk iphoneos -arch arm64 \
  -configuration Debug -derivedDataPath "$ROOT/.build/inject" build -quiet
PRODUCTS="$ROOT/.build/inject/Build/Products/Debug-iphoneos"
mkdir -p "$DEST"
rm -rf "$DEST/SimCamLiteInject.framework"
cp -R "$PRODUCTS/SimCamLiteInject.framework" "$DEST/"
cp "$PRODUCTS/SimCamLiteLoader.dylib" "$DEST/"

WRAPPER="$(dirname "$APP")/.MacRun/$NAME.app"
rm -rf "$WRAPPER"
mkdir -p "$WRAPPER/Wrapper"
cp -R "$APP" "$WRAPPER/Wrapper/"
ln -s "Wrapper/$NAME.app" "$WRAPPER/WrappedBundle"

open --env DYLD_INSERT_LIBRARIES="$DEST/SimCamLiteLoader.dylib" --env SIMCAMLITE_FORCE=1 "$WRAPPER"

# The app is sandboxed on macOS and cannot read /Users/Shared, so the frame file is hard-linked into its container.
for _ in $(seq 1 20); do
  PID="$(mac_pid)"
  DATA="$([ -n "$PID" ] && lsof -p "$PID" -Fn 2>/dev/null | sed -n 's|^n\(.*/Library/Containers/[^/]*/Data\)/.*|\1|p' | head -1 || true)"
  if [ -n "$DATA" ]; then
    mkdir -p "$DATA/tmp/SimCamLite"
    ln -f "$SHM" "$DATA/tmp/SimCamLite/frames.shm"
    echo "$NAME (pid $PID) injected; frames linked into $DATA/tmp/SimCamLite"
    exit 0
  fi
  sleep 0.5
done
echo "Could not find the container of $NAME; no camera frames will arrive." >&2
exit 1
