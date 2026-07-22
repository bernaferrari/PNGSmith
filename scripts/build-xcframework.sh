#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FRAMEWORK_DIR="$ROOT_DIR/macos/Frameworks"
UNIVERSAL_DIR="$ROOT_DIR/target/universal-apple-darwin/release"

"$ROOT_DIR/scripts/build-rust-macos.sh" aarch64-apple-darwin
"$ROOT_DIR/scripts/build-rust-macos.sh" x86_64-apple-darwin

mkdir -p "$UNIVERSAL_DIR" "$FRAMEWORK_DIR"
lipo -create \
    "$ROOT_DIR/target/aarch64-apple-darwin/release/libpngsmith_core.a" \
    "$ROOT_DIR/target/x86_64-apple-darwin/release/libpngsmith_core.a" \
    -output "$UNIVERSAL_DIR/libpngsmith_core.a"
lipo -create \
    "$ROOT_DIR/target/aarch64-apple-darwin/release/pngsmith" \
    "$ROOT_DIR/target/x86_64-apple-darwin/release/pngsmith" \
    -output "$UNIVERSAL_DIR/pngsmith"

rm -rf "$FRAMEWORK_DIR/PNGSmithCore.xcframework"
xcodebuild -create-xcframework \
    -library "$UNIVERSAL_DIR/libpngsmith_core.a" \
    -headers "$ROOT_DIR/macos/Headers" \
    -output "$FRAMEWORK_DIR/PNGSmithCore.xcframework"

echo "Created $FRAMEWORK_DIR/PNGSmithCore.xcframework"

