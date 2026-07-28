#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEAM_ID="${1:-${PNGSMITH_DEVELOPMENT_TEAM:-}}"
DERIVED_DATA_PATH="$ROOT_DIR/macos/build/DevelopmentSigned"
INSTALL_DIR="${PNGSMITH_INSTALL_DIR:-$HOME/Applications}"
APP_PATH="$INSTALL_DIR/PNG Smith.app"
LEGACY_APP_PATH="$INSTALL_DIR/PNGSmith.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ -z "$TEAM_ID" ]]; then
    echo "Usage: $0 TEAM_ID" >&2
    echo "Sign in to Xcode with your Apple Developer account, then pass its 10-character Team ID." >&2
    exit 2
fi

if ! security find-identity -v -p codesigning | rg -q '[1-9][0-9]* valid identities found'; then
    echo "No usable code-signing identity was found." >&2
    echo "Open Xcode → Settings → Accounts, sign in, then create or download an Apple Development certificate." >&2
    exit 1
fi

"$ROOT_DIR/scripts/build-xcframework.sh"
(cd "$ROOT_DIR/macos" && xcodegen generate)

xcodebuild \
    -project "$ROOT_DIR/macos/PNGSmith.xcodeproj" \
    -scheme PNGSmith \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -allowProvisioningUpdates \
    "DEVELOPMENT_TEAM=$TEAM_ID" \
    "PNGSMITH_DEVELOPMENT_TEAM=$TEAM_ID" \
    "CODE_SIGN_STYLE=Automatic" \
    build

mkdir -p "$INSTALL_DIR"
for EXISTING_APP_PATH in "$APP_PATH" "$LEGACY_APP_PATH"; do
    if [[ -e "$EXISTING_APP_PATH" ]]; then
        EXISTING_APP_NAME="$(basename "$EXISTING_APP_PATH" .app)"
        BACKUP_PATH="$INSTALL_DIR/$EXISTING_APP_NAME.previous.$(date +%Y%m%d%H%M%S).app"
        mv "$EXISTING_APP_PATH" "$BACKUP_PATH"
        echo "Previous copy moved to $BACKUP_PATH"
    fi
done

ditto "$DERIVED_DATA_PATH/Build/Products/Debug/PNG Smith.app" "$APP_PATH"
"$LSREGISTER" -f "$APP_PATH"
open "$APP_PATH"

echo "Installed signed development build at $APP_PATH"
echo "Enable the PNG Smith actions in System Settings → General → Login Items & Extensions → Finder."
