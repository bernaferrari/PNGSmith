#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 KEYCHAIN_PROFILE '/path/to/PNG Smith.app'" >&2
    exit 2
fi

PROFILE="$1"
APP_PATH="$2"
ZIP_PATH="${APP_PATH%/}.zip"

ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
