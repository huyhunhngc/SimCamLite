#!/bin/bash
# Archives, notarizes and publishes a SimCamLite release: DMG + Sparkle update on R2 and the GitHub Release.
#
# Usage: scripts/release-from-archive.sh [options]
#   --archive PATH           use an existing .xcarchive instead of archiving HEAD
#   --tag TAG                GitHub Release tag (default: v<MARKETING_VERSION>)
#   --keychain-account NAME  login Keychain account of the Sparkle EdDSA key (default: simcamlite)
#   --bucket NAME            Cloudflare R2 bucket (default: simcamupdates)
#   --no-layout              skip the DMG Finder layout (no Automation prompt)
#
# Before running: bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml, update
# .github/RELEASE_NOTES.md, push to main and let GitHub Actions create the draft release.
# Notarization reads SIMCAM_NOTARY_ISSUER_ID, SIMCAM_NOTARY_KEY_ID and SIMCAM_NOTARY_KEY_PATH from
# Config/Environment.xcconfig (environment variables of the same name win).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_CONFIG="$ROOT/Config/Environment.xcconfig"
NOTES="$ROOT/.github/RELEASE_NOTES.md"
ARCHIVE=""
TAG=""
ACCOUNT="simcamlite"
BUCKET="simcamupdates"
DMG_FLAGS=()

fail() { echo "error: $1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --archive) ARCHIVE="${2%/}"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --keychain-account) ACCOUNT="$2"; shift 2 ;;
    --bucket) BUCKET="$2"; shift 2 ;;
    --no-layout) DMG_FLAGS+=(--no-layout); shift ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fail "unknown option $1" ;;
  esac
done

xcconfig_value() {
  awk -v name="$1" 'index($0, "=") {
    key = substr($0, 1, index($0, "=") - 1); gsub(/^[ \t]+|[ \t]+$/, "", key)
    if (key == name) { value = substr($0, index($0, "=") + 1); gsub(/^[ \t]+|[ \t]+$/, "", value); result = value }
  } END { print result }' "$ENV_CONFIG" 2>/dev/null
}

NOTARY_ISSUER="${SIMCAM_NOTARY_ISSUER_ID:-$(xcconfig_value SIMCAM_NOTARY_ISSUER_ID)}"
NOTARY_KEY_ID="${SIMCAM_NOTARY_KEY_ID:-$(xcconfig_value SIMCAM_NOTARY_KEY_ID)}"
NOTARY_KEY="${SIMCAM_NOTARY_KEY_PATH:-$(xcconfig_value SIMCAM_NOTARY_KEY_PATH)}"
[[ -z "$NOTARY_KEY" || "$NOTARY_KEY" == /* ]] || NOTARY_KEY="$ROOT/$NOTARY_KEY"

# MARK: Preflight

[ -n "$NOTARY_ISSUER" ] && [ -n "$NOTARY_KEY_ID" ] && [ -f "$NOTARY_KEY" ] \
  || fail "set SIMCAM_NOTARY_ISSUER_ID, SIMCAM_NOTARY_KEY_ID and SIMCAM_NOTARY_KEY_PATH in Config/Environment.xcconfig"
command -v gh >/dev/null || fail "GitHub CLI (gh) not found"
command -v wrangler >/dev/null || fail "wrangler not found (npm i -g wrangler)"
[ -f "$NOTES" ] || fail ".github/RELEASE_NOTES.md is missing"
[ -z "$(git -C "$ROOT" status --porcelain)" ] || fail "the working tree must be clean"

ORIGIN="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
REPO="$(sed -E 's#^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)##; s#\.git$##' <<<"$ORIGIN")"
[[ -n "$ORIGIN" && "$REPO" != "$ORIGIN" && "$REPO" == */* ]] || fail "git remote 'origin' must be a GitHub repository"
gh auth status --hostname github.com >/dev/null

notarize() {
  local file="$1" result
  echo "Notarizing $(basename "$file") (this can take a few minutes)…"
  result="$(xcrun notarytool submit "$file" --issuer "$NOTARY_ISSUER" --key-id "$NOTARY_KEY_ID" --key "$NOTARY_KEY" \
    --wait --timeout 1h --output-format plist)"
  local status
  status="$(plutil -extract status raw - <<<"$result")"
  [ "$status" = "Accepted" ] || { echo "$result" >&2; fail "notarization status: $status"; }
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# MARK: Archive

if [ -z "$ARCHIVE" ]; then
  command -v xcodegen >/dev/null && xcodegen generate --spec "$ROOT/project.yml" --project "$ROOT" --quiet
  [ -z "$(git -C "$ROOT" status --porcelain)" ] || fail "xcodegen changed the project; commit SimCamLite.xcodeproj first"
  ARCHIVE="$ROOT/build/archives/SimCamLite-$(date '+%Y%m%d-%H%M%S').xcarchive"
  echo "Archiving…"
  xcodebuild -project "$ROOT/SimCamLite.xcodeproj" -scheme SimCamLite -configuration Release \
    -destination "generic/platform=macOS" -archivePath "$ARCHIVE" archive -quiet
fi
[[ -d "$ARCHIVE" && "$ARCHIVE" == *.xcarchive ]] || fail "not an .xcarchive: $ARCHIVE"

ARCHIVED_APP="$ARCHIVE/Products/Applications/SimCamLite.app"
PLIST="$ARCHIVED_APP/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$PLIST")"
FEED="$(/usr/libexec/PlistBuddy -c 'Print SUFeedURL' "$PLIST" 2>/dev/null || true)"
TEAM="$(/usr/libexec/PlistBuddy -c 'Print ApplicationProperties:Team' "$ARCHIVE/Info.plist")"
[[ "$FEED" == https://* ]] || fail "the archive has no HTTPS SUFeedURL; fill in Config/Environment.xcconfig and archive again"
BASE_URL="${FEED%/*}"
TAG="${TAG:-v$VERSION}"

[ "$(sed -n '/[^[:space:]]/{p;q;}' "$NOTES")" = "# SimCam Lite $VERSION" ] \
  || fail ".github/RELEASE_NOTES.md must start with '# SimCam Lite $VERSION'"
gh release view "$TAG" --repo "$REPO" --json isDraft >/dev/null 2>&1 \
  || fail "GitHub Release $TAG does not exist; push the version bump to main and let CI create the draft"
echo "Releasing SimCam Lite $VERSION ($BUILD) as $TAG"

# MARK: Export and notarize the app

EXPORT_DIR="$ROOT/build/export/$VERSION-$BUILD"
rm -rf "$EXPORT_DIR"
cat > "$WORK/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
  <key>teamID</key><string>$TEAM</string>
</dict></plist>
EOF
echo "Exporting with Developer ID…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" -exportOptionsPlist "$WORK/ExportOptions.plist" -quiet
APP="$EXPORT_DIR/SimCamLite.app"
codesign --verify --deep --strict --verbose=2 "$APP"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/notarize.zip"
notarize "$WORK/notarize.zip"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# MARK: DMG

DMG="$("$ROOT/scripts/make-dmg.sh" "$APP" -o "$EXPORT_DIR" ${DMG_FLAGS[@]+"${DMG_FLAGS[@]}"} | tail -1)"
[ -f "$DMG" ] || fail "DMG was not created"
notarize "$DMG"
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"

# MARK: Sparkle update

"$ROOT/scripts/make-sparkle-update.sh" --app "$APP" --download-url-prefix "$BASE_URL/releases/" \
  --release-notes "$NOTES" --keychain-account "$ACCOUNT"
ZIP="$ROOT/build/sparkle-releases/SimCamLite-$VERSION.zip"
APPCAST="$ROOT/build/sparkle-releases/appcast.xml"
DMG_NAME="SimCamLite-$VERSION.dmg"

# MARK: Publish

echo "Uploading to GitHub Release $TAG…"
cp "$DMG" "$WORK/$DMG_NAME"
gh release upload "$TAG" "$ZIP" "$WORK/$DMG_NAME" --repo "$REPO" --clobber

echo "Uploading to R2 bucket $BUCKET…"
wrangler r2 object put "$BUCKET/releases/$(basename "$ZIP")" --file "$ZIP" --remote \
  --content-type "application/zip" --cache-control "public, max-age=31536000, immutable"
wrangler r2 object put "$BUCKET/releases/$DMG_NAME" --file "$WORK/$DMG_NAME" --remote \
  --content-type "application/x-apple-diskimage" --cache-control "public, max-age=31536000, immutable"
# Latest DMG under a stable name for the website's download button.
wrangler r2 object put "$BUCKET/SimCamLite.dmg" --file "$WORK/$DMG_NAME" --remote \
  --content-type "application/x-apple-diskimage" --cache-control "no-cache"
# The appcast goes last: clients only see the update once its archive is downloadable.
wrangler r2 object put "$BUCKET/appcast.xml" --file "$APPCAST" --remote \
  --content-type "application/rss+xml; charset=utf-8" --cache-control "no-cache, no-store, must-revalidate"

gh release edit "$TAG" --repo "$REPO" --title "SimCam Lite $VERSION" --notes-file "$NOTES" --draft=false --latest

echo
echo "Published SimCam Lite $VERSION"
echo "  Appcast: $BASE_URL/appcast.xml"
echo "  Update:  $BASE_URL/releases/$(basename "$ZIP")"
echo "  DMG:     $BASE_URL/releases/$DMG_NAME"
