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
codesign -fs - "$DEST/SimCamLiteLoader.dylib" "$DEST/SimCamLiteInject.framework" >/dev/null
