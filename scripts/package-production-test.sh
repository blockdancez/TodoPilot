#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIGURATION="${CONFIGURATION:-Release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ENTITLEMENTS_PATH="$APP_DIR/TodoPilot/Resources/TodoPilot.entitlements"
BUILD_ROOT="$APP_DIR/.build/production-test"
DERIVED_DATA_PATH="$BUILD_ROOT/DerivedData"
PACKAGE_ROOT="$BUILD_ROOT/package"
APP_SOURCE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/TodoPilot.app"
APP_DEST="$PACKAGE_ROOT/TodoPilot.app"
ZIP_PATH="$BUILD_ROOT/TodoPilot-free-production-test.zip"

rm -rf "$BUILD_ROOT"
mkdir -p "$PACKAGE_ROOT"

xcodebuild \
  -project "$APP_DIR/TodoPilot.xcodeproj" \
  -scheme TodoPilot \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  clean build \
  CODE_SIGNING_ALLOWED=NO

ditto "$APP_SOURCE" "$APP_DEST"
codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS_PATH" --sign "$SIGN_IDENTITY" "$APP_DEST"

rm -f "$ZIP_PATH"
(
  cd "$PACKAGE_ROOT"
  ditto -c -k --keepParent "TodoPilot.app" "$ZIP_PATH"
)

echo "Packaged offline edition: $ZIP_PATH"
echo "Signature: $SIGN_IDENTITY"
