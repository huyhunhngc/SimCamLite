#!/bin/bash
# Packages SimCamLite.app into a drag-to-Applications DMG.
#
# Usage: scripts/make-dmg.sh [ARCHIVE.xcarchive | SimCamLite.app] [options]
#   (no input)              newest SimCamLite*.xcarchive in ~/Library/Developer/Xcode/Archives
#   -o, --output DIR        output folder (default: build/)
#   --sign IDENTITY         codesign the DMG (default: first "Developer ID Application" identity, "-" to skip)
#   --notarize PROFILE      notarize + staple the DMG with a notarytool keychain profile
#                           (create once: xcrun notarytool store-credentials PROFILE)
#   --no-layout             skip the Finder window layout (no Automation prompt)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="SimCamLite"
INPUT=""
OUTPUT_DIR="$ROOT/build"
SIGN_IDENTITY=""
NOTARY_PROFILE=""
LAYOUT=1

while [ $# -gt 0 ]; do
  case "$1" in
    -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
    --sign) SIGN_IDENTITY="$2"; shift 2 ;;
    --notarize) NOTARY_PROFILE="$2"; shift 2 ;;
    --no-layout) LAYOUT=0; shift ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "Unknown option $1" >&2; exit 1 ;;
    *) INPUT="$1"; shift ;;
  esac
done

if [ -z "$INPUT" ]; then
  INPUT="$(ls -td "$HOME/Library/Developer/Xcode/Archives"/*/"$APP_NAME"*.xcarchive 2>/dev/null | head -1 || true)"
  [ -n "$INPUT" ] || { echo "No $APP_NAME archive found; pass an .xcarchive or .app" >&2; exit 1; }
fi
INPUT="${INPUT%/}"
case "$INPUT" in
  *.xcarchive) APP="$INPUT/Products/Applications/$APP_NAME.app" ;;
  *.app) APP="$INPUT" ;;
  *) echo "Expected an .xcarchive or .app: $INPUT" >&2; exit 1 ;;
esac
[ -d "$APP" ] || { echo "App not found: $APP" >&2; exit 1; }
echo "App:      $APP"

# Sanity checks: a DMG for other Macs needs a Developer ID signature, the embedded CLI and the inject payload.
codesign --verify --deep --strict "$APP" || { echo "Code signature is invalid" >&2; exit 1; }
AUTHORITY="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
echo "Signed:   ${AUTHORITY:-ad-hoc}"
case "$AUTHORITY" in
  "Developer ID Application"*) ;;
  *) echo "warning: not signed with Developer ID; Gatekeeper will block it on other Macs" >&2 ;;
esac
for required in Contents/MacOS/simcam Contents/Resources/Inject/SimCamLiteLoader.dylib Contents/Resources/Inject/SimCamLiteInject.framework; do
  [ -e "$APP/$required" ] || { echo "Missing $required in the app bundle" >&2; exit 1; }
done
if xcrun stapler validate -q "$APP" 2>/dev/null; then
  echo "App:      notarization ticket stapled"
elif [ -z "$NOTARY_PROFILE" ]; then
  echo "warning: app is not notarized. Export it via Organizer › Distribute App › Direct Distribution, or pass --notarize" >&2
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")"
mkdir -p "$OUTPUT_DIR"
DMG="$OUTPUT_DIR/$APP_NAME-$VERSION-$BUILD.dmg"
VOLUME="$APP_NAME"

WORK="$(mktemp -d)"
MOUNT=""
cleanup() {
  [ -n "$MOUNT" ] && hdiutil detach "$MOUNT" -quiet -force 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

STAGING="$WORK/staging"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

RW="$WORK/rw.dmg"
hdiutil create -quiet -volname "$VOLUME" -srcfolder "$STAGING" -fs HFS+ -format UDRW -ov "$RW"

if [ "$LAYOUT" = 1 ]; then
  MOUNT="$(hdiutil attach "$RW" -readwrite -noverify -noautoopen | awk -F'\t' '/\/Volumes\//{print $NF; exit}')"
  if [ -n "$MOUNT" ]; then
    DISK="$(basename "$MOUNT")"
    osascript <<EOF || echo "warning: Finder layout skipped (allow Terminal to control Finder, or use --no-layout)" >&2
tell application "Finder"
  tell disk "$DISK"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 740, 480}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 13
    set position of item "$APP_NAME.app" of container window to {140, 170}
    set position of item "Applications" of container window to {400, 170}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
    sync
    hdiutil detach "$MOUNT" -quiet || hdiutil detach "$MOUNT" -quiet -force
    MOUNT=""
  fi
fi

rm -f "$DMG"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"

if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' | head -1)"
fi
if [ -n "$SIGN_IDENTITY" ] && [ "$SIGN_IDENTITY" != "-" ]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
  echo "DMG signed: $SIGN_IDENTITY"
fi

if [ -n "$NOTARY_PROFILE" ]; then
  echo "Notarizing (this can take a few minutes)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl -a -t open --context context:primary-signature -vv "$DMG" || true
fi

echo "$DMG"
