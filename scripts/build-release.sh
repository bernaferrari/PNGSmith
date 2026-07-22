#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
ARCHIVE_PATH="$ROOT_DIR/macos/build/PNGSmith.xcarchive"

"$ROOT_DIR/scripts/build-xcframework.sh"
(cd "$ROOT_DIR/macos" && xcodegen generate)

rm -rf "$ARCHIVE_PATH" "$DIST_DIR"
xcodebuild archive \
    -project "$ROOT_DIR/macos/PNGSmith.xcodeproj" \
    -scheme PNGSmith \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    "${@}"

mkdir -p "$DIST_DIR"
ditto "$ARCHIVE_PATH/Products/Applications/PNGSmith.app" "$DIST_DIR/PNGSmith.app"
install -m 755 "$ROOT_DIR/target/universal-apple-darwin/release/pngsmith" "$DIST_DIR/pngsmith"
mkdir -p "$DIST_DIR/PNGSmith.app/Contents/Resources/bin"
install -m 755 "$DIST_DIR/pngsmith" "$DIST_DIR/PNGSmith.app/Contents/Resources/bin/pngsmith"

echo "Release artifacts are in $DIST_DIR"

