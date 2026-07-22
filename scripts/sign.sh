#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 'Developer ID Application: Name (TEAMID)' /path/to/PNGSmith.app" >&2
    exit 2
fi

IDENTITY="$1"
APP_PATH="$2"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_ENTITLEMENTS="$ROOT_DIR/macos/PNGSmithApp/PNGSmith.entitlements"
EXTENSION_ENTITLEMENTS="$ROOT_DIR/macos/PNGSmithQuickAction/PNGSmithQuickAction.entitlements"

if [[ ! -d "$APP_PATH" ]]; then
    echo "App bundle not found: $APP_PATH" >&2
    exit 2
fi

codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP_PATH/Contents/Resources/bin/pngsmith"

shopt -s nullglob
extensions=("$APP_PATH"/Contents/PlugIns/*.appex)
if [[ ${#extensions[@]} -eq 0 ]]; then
    echo "No app extensions found in $APP_PATH" >&2
    exit 2
fi

for extension in "${extensions[@]}"; do
    codesign --force --options runtime --timestamp --entitlements "$EXTENSION_ENTITLEMENTS" --sign "$IDENTITY" "$extension"
done

codesign --force --options runtime --timestamp --entitlements "$APP_ENTITLEMENTS" --sign "$IDENTITY" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
