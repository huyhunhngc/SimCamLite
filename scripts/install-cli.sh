#!/bin/bash
# Symlinks the simcam CLI embedded in SimCamLite.app onto PATH.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/SimCamLite.app}"
BINARY="$APP/Contents/MacOS/simcam"
[ -x "$BINARY" ] || { echo "simcam not found in $APP — run scripts/build.sh first" >&2; exit 1; }
DEST_DIR="/usr/local/bin"
if [ ! -w "$DEST_DIR" ]; then
  DEST_DIR="$HOME/.local/bin"
  mkdir -p "$DEST_DIR"
fi
ln -sf "$BINARY" "$DEST_DIR/simcam"
echo "Installed $DEST_DIR/simcam -> $BINARY"
case ":$PATH:" in
  *":$DEST_DIR:"*) ;;
  *) echo "Add $DEST_DIR to PATH, e.g. echo 'export PATH=\"$DEST_DIR:\$PATH\"' >> ~/.zshrc" ;;
esac
