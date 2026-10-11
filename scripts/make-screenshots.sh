#!/bin/bash
# Captures the README screenshots from the running SimCamLite window and the booted simulator.
#
# Usage: scripts/make-screenshots.sh
# Before running: open the main window, stream into a camera app on a booted simulator, and install the CLI so
# Settings shows no warning. The script switches the sidebar section and restores it afterwards.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOMAIN="dev.ifateam.simcamlite"
RAW="$(mktemp -d)"
trap 'rm -rf "$RAW"' EXIT

WINDOW="$(swift - <<'EOF'
import CoreGraphics
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let main = windows.first {
  ($0[kCGWindowLayer as String] as? Int) == 0 && ($0[kCGWindowOwnerName as String] as? String) == "SimCam Lite"
    && ($0[kCGWindowName as String] as? String) == "SimCamLite"
}
print(main?[kCGWindowNumber as String] as? Int ?? 0)
EOF
)"
[ "$WINDOW" != 0 ] || { echo "error: open the SimCamLite main window first" >&2; exit 1; }

PREVIOUS="$(defaults read "$DOMAIN" mainSection 2>/dev/null || echo camera)"
for section in camera simulator settings; do
  defaults write "$DOMAIN" mainSection "$section"
  sleep 1.5
  screencapture -o -l "$WINDOW" "$RAW/$section.png"
done
defaults write "$DOMAIN" mainSection "$PREVIOUS"

xcrun simctl io booted screenshot --type=png "$RAW/iphone.png" 2>/dev/null
python3 -I "$ROOT/scripts/compose-screenshots.py" "$RAW" "$ROOT/assets/screenshots"
echo "$ROOT/assets/screenshots"
