#!/bin/bash
# Zips a signed, notarized SimCamLite.app for Sparkle and regenerates the appcast.
#
# Usage: scripts/make-sparkle-update.sh --app SimCamLite.app --download-url-prefix URL [options]
#   --app PATH                 exported, notarized SimCamLite.app
#   --download-url-prefix URL  where the zips are served, e.g. https://simcamupdates.ifateam.dev/releases/
#   --archives-dir DIR         update history; every zip in it stays in the appcast (default: build/sparkle-releases)
#   --release-notes FILE       Markdown notes embedded in the appcast (default: .github/RELEASE_NOTES.md)
#   --generate-appcast PATH    Sparkle's generate_appcast (default: found in Xcode DerivedData)
#   --keychain-account NAME    login Keychain account of the EdDSA private key (default: simcamlite)
#   --allow-http               allow a non-HTTPS download prefix (local testing only)
#   --skip-gatekeeper-check    skip spctl for a local, non-notarized test build
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP=""
PREFIX=""
ARCHIVES_DIR="$ROOT/build/sparkle-releases"
NOTES="$ROOT/.github/RELEASE_NOTES.md"
GENERATE_APPCAST=""
ACCOUNT="simcamlite"
ALLOW_HTTP=0
GATEKEEPER=1

fail() { echo "error: $1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --app) APP="${2%/}"; shift 2 ;;
    --download-url-prefix) PREFIX="$2"; shift 2 ;;
    --archives-dir) ARCHIVES_DIR="$2"; shift 2 ;;
    --release-notes) NOTES="$2"; shift 2 ;;
    --generate-appcast) GENERATE_APPCAST="$2"; shift 2 ;;
    --keychain-account) ACCOUNT="$2"; shift 2 ;;
    --allow-http) ALLOW_HTTP=1; shift ;;
    --skip-gatekeeper-check) GATEKEEPER=0; shift ;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fail "unknown option $1" ;;
  esac
done

[[ -d "$APP" && "$APP" == *.app ]] || fail "--app must point to SimCamLite.app"
[ -n "$PREFIX" ] || fail "--download-url-prefix is required"
[[ "$PREFIX" == https://* || "$ALLOW_HTTP" == 1 ]] || fail "--download-url-prefix must use HTTPS"
[[ "$PREFIX" == */ ]] || PREFIX="$PREFIX/"
[ -f "$NOTES" ] || fail "release notes not found: $NOTES"

if [ -z "$GENERATE_APPCAST" ]; then
  GENERATE_APPCAST="$(find "$ROOT/.build" "$HOME/Library/Developer/Xcode/DerivedData" -type f -perm -111 \
    -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast' -print -quit 2>/dev/null || true)"
fi
[ -x "$GENERATE_APPCAST" ] || fail "generate_appcast not found; build the app once or pass --generate-appcast"

PLIST="$APP/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$PLIST")"
FEED="$(/usr/libexec/PlistBuddy -c 'Print SUFeedURL' "$PLIST" 2>/dev/null || true)"
KEY="$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$PLIST" 2>/dev/null || true)"
[[ "$FEED" == https://* || ( "$ALLOW_HTTP" == 1 && -n "$FEED" ) ]] \
  || fail "SUFeedURL is not an HTTPS URL; fill in Config/Environment.xcconfig and rebuild"
[ -n "$KEY" ] || fail "SUPublicEDKey is empty; fill in Config/Environment.xcconfig and rebuild"

TITLE="$(sed -n '/[^[:space:]]/{p;q;}' "$NOTES")"
[ "$TITLE" = "# SimCam Lite $VERSION" ] || fail "$(basename "$NOTES") must start with '# SimCam Lite $VERSION'"

# Sparkle replaces the whole bundle, so the update must carry the CLI and the inject payload too.
for required in Contents/MacOS/simcam Contents/Resources/Inject/SimCamLiteLoader.dylib \
                Contents/Resources/Inject/SimCamLiteInject.framework Contents/Frameworks/Sparkle.framework; do
  [ -e "$APP/$required" ] || fail "missing $required in the app bundle"
done

echo "Verifying SimCam Lite $VERSION ($BUILD)…"
codesign --verify --deep --strict --verbose=2 "$APP"
[ "$GATEKEEPER" = 0 ] || spctl --assess --type execute --verbose=4 "$APP"

mkdir -p "$ARCHIVES_DIR"
ZIP="$ARCHIVES_DIR/SimCamLite-$VERSION.zip"
[ ! -e "$ZIP" ] || fail "$ZIP already exists; bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
# generate_appcast embeds notes named like the archive.
cp "$NOTES" "$ARCHIVES_DIR/SimCamLite-$VERSION.md"

echo "Signing the update and writing appcast.xml (EdDSA key from the login Keychain)…"
"$GENERATE_APPCAST" \
  --account "$ACCOUNT" \
  --download-url-prefix "$PREFIX" \
  --embed-release-notes \
  --maximum-deltas 0 \
  -o "$ARCHIVES_DIR/appcast.xml" \
  "$ARCHIVES_DIR"

echo "$ZIP"
echo "$ARCHIVES_DIR/appcast.xml"
