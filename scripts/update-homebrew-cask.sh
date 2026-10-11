#!/bin/bash
# Renders homebrew/simcam-lite.rb for a release and commits it to the Homebrew tap.
#
# Usage: scripts/update-homebrew-cask.sh --version VERSION --dmg PATH [options]
#   --version VERSION   MARKETING_VERSION of the release (the DMG must be on the GitHub Release v<VERSION>)
#   --dmg PATH          the published SimCamLite-<VERSION>.dmg, used for the checksum
#   --tap REPO          GitHub repository of the tap (default: huyhunhngc/homebrew-tap)
#   --print             print the rendered cask instead of committing it
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$ROOT/homebrew/simcam-lite.rb"
CASK_PATH="Casks/simcam-lite.rb"
VERSION=""
DMG=""
TAP="huyhunhngc/homebrew-tap"
PRINT=0

fail() { echo "error: $1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --dmg) DMG="$2"; shift 2 ;;
    --tap) TAP="$2"; shift 2 ;;
    --print) PRINT=1; shift ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fail "unknown option $1" ;;
  esac
done

[[ "$VERSION" =~ ^[0-9A-Za-z][0-9A-Za-z.-]*$ ]] || fail "pass --version"
[ -f "$DMG" ] || fail "DMG not found: ${DMG:-<none>}"
[ -f "$TEMPLATE" ] || fail "cask template missing: $TEMPLATE"

SHA256="$(shasum -a 256 "$DMG" | awk '{print $1}')"
CASK="$(sed -e "s/{{VERSION}}/$VERSION/" -e "s/{{SHA256}}/$SHA256/" "$TEMPLATE")"

if [ "$PRINT" = 1 ]; then
  echo "$CASK"
  exit 0
fi

command -v gh >/dev/null || fail "GitHub CLI (gh) not found"
ENDPOINT="repos/$TAP/contents/$CASK_PATH"
CURRENT_SHA="$(gh api "$ENDPOINT" --jq .sha 2>/dev/null || true)"
if [ -n "$CURRENT_SHA" ] \
  && [ "$(gh api "$ENDPOINT" -H "Accept: application/vnd.github.raw" 2>/dev/null)" = "$CASK" ]; then
  echo "Homebrew cask in $TAP is already at $VERSION"
  exit 0
fi

ARGS=(-X PUT "$ENDPOINT" -f "message=simcam-lite $VERSION" -f "content=$(printf '%s\n' "$CASK" | base64 | tr -d '\n')")
[ -z "$CURRENT_SHA" ] || ARGS+=(-f "sha=$CURRENT_SHA")
gh api "${ARGS[@]}" --silent
echo "Updated $TAP/$CASK_PATH to $VERSION ($SHA256)"
