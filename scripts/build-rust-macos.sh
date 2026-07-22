#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_NAME="${1:-aarch64-apple-darwin}"
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"

if ! rustup target list --installed | grep -qx "$TARGET_NAME"; then
    rustup target add "$TARGET_NAME"
fi

cargo build \
    --manifest-path "$ROOT_DIR/Cargo.toml" \
    --release \
    --target "$TARGET_NAME" \
    --package pngsmith-ffi \
    --package pngsmith-cli \
    --all-features
