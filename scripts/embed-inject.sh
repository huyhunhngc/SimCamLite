#!/bin/bash
set -euo pipefail
ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CONFIG="${CONFIGURATION:-Debug}"
DERIVED="$ROOT/.build/inject"
DEST="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/Inject"
env -i PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="$HOME" DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}" \
  xcodebuild -project "$ROOT/SimCamLite.xcodeproj" -scheme SimCamLiteInject -sdk iphonesimulator \
  -configuration "$CONFIG" -derivedDataPath "$DERIVED" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build -quiet
PRODUCTS="$DERIVED/Build/Products/$CONFIG-iphonesimulator"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$PRODUCTS/SimCamLiteInject.framework" "$DEST/"
cp "$PRODUCTS/SimCamLiteLoader.dylib" "$DEST/"
rm -rf "$DEST/SimCamLiteInject.framework/Headers"
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
SIGN_FLAGS=(--force --sign "$IDENTITY" --options runtime)
if [ "$IDENTITY" != "-" ]; then
  SIGN_FLAGS+=(--timestamp)
fi
codesign "${SIGN_FLAGS[@]}" "$DEST/SimCamLiteLoader.dylib" "$DEST/SimCamLiteInject.framework" >/dev/null
