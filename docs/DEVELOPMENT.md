# PNGSmith developer guide

This guide covers local builds, the command-line and JSON interfaces, tests, architecture, and releases. For the product overview, see the [README](../README.md).

## Requirements

- macOS 14 or newer
- Xcode 16 or newer
- Rust 1.85.1 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Build the macOS app

### Signed development install

The signed path enables Finder extensions and Services:

```sh
brew install xcodegen
./scripts/development-install.sh YOUR_APPLE_TEAM_ID
```

The installer builds the universal Rust framework, generates the Xcode project, signs every target, installs PNGSmith in `~/Applications`, registers it with LaunchServices, and opens it. Existing development builds are moved aside instead of deleted.

### Unsigned UI build

```sh
brew install xcodegen
./scripts/build-xcframework.sh

cd macos
xcodegen generate
xcodebuild \
  -project PNGSmith.xcodeproj \
  -scheme PNGSmith \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Unsigned builds cannot enable Finder extensions.

## CLI

```sh
cargo build --release --package pngsmith-cli --all-features

# Smart lossless; writes image_min.png.
target/release/pngsmith image.png

# Exact palette; fail if more than 64 colors are required.
target/release/pngsmith --mode exact --colors 64 --fallback error image.png

# Perceptual color reduction.
target/release/pngsmith --mode perceptual --colors 64 image.png

# Automatic palette search shared with the macOS app.
target/release/pngsmith --mode auto --auto-strategy balanced image.png

# Maximum lossless effort.
target/release/pngsmith minify --profile maximum-lossless image.png

# Machine-readable output.
target/release/pngsmith --json image.png
```

Built-in profiles are `smart-lossless`, `strict-lossless`, `exact-256`, `perceptual-256`, `auto-balanced`, `auto-smaller`, and `maximum-lossless`.

## JSON API and C ABI

The CLI and two-function C ABI share the same JSON contract. Run `pngsmith execute-json --request '{...}'`, or omit `--request` to read from standard input.

```json
{
  "inputs": ["/Users/alice/Desktop/example.png"],
  "mode": "exact_palette",
  "max_colors": 256,
  "fallback": "lossless",
  "automatic": {
    "strategy": "balanced"
  },
  "output": {
    "create_copy": true,
    "suffix": "_min",
    "only_if_smaller": false
  },
  "lossless": {
    "oxipng_level": 4,
    "zopfli": false,
    "metadata": "preserve",
    "preserve_transparent_rgb": true
  },
  "verify": {
    "decoded_pixels": true
  }
}
```

Unspecified fields receive safe defaults. C ABI callers must release returned strings with `pngsmith_string_free`.

## Safety model

- Lossless output is decoded and compared as normalized RGBA samples, including RGB beneath transparent pixels.
- Animated PNG output is verified frame by frame, including timing, placement, disposal, and blending.
- Unsupported animated edits fail instead of flattening the image.
- Crop and canvas edits are always written; smaller-only policy applies only to pure compression.
- Compatible color-profile and text metadata survives palette and crop transformations.
- Same-directory temporary files and atomic moves protect destination files.
- Decode limits apply at every entry point.

The core embeds [OxiPNG](https://github.com/shssoichiro/oxipng), [imagequant](https://github.com/ImageOptim/libimagequant), and optional Zopfli compression.

## Architecture

```text
macOS app · Finder · Services · Shortcuts · CLI
                       │
                 JSON request model
                       │
                 pngsmith-core
          compression · crop · verification
                       │
                 atomic PNG output
```

| Path | Responsibility |
|---|---|
| `crates/pngsmith-core` | Compression, crop/canvas composition, APNG handling, verification, metadata, and output policy |
| `crates/pngsmith-ffi` | Minimal C ABI over the JSON contract |
| `crates/pngsmith-cli` | Terminal and automation interface |
| `macos/PNGSmithApp` | SwiftUI app, crop workspace, App Intents, Services, and updates |
| `macos/PNGSmithQuickAction` | Finder Action Extensions |
| `macos/Shared` | Codable request model, FFI bridge, and preferences |
| `scripts` | Universal builds, installation, and release assembly |

## Tests

```sh
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features
```

```sh
./scripts/build-xcframework.sh
cd macos
xcodegen generate
xcodebuild \
  -project PNGSmith.xcodeproj \
  -scheme PNGSmith \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

GitHub Actions runs both paths on pushes and pull requests.

## Releases and automatic updates

`scripts/build-release.sh` archives the app and places the app plus standalone CLI in `dist/`. Signing settings can be passed as Xcode build arguments.

Sparkle update checks require both build settings:

```sh
PNGSMITH_UPDATE_FEED_URL="https://github.com/OWNER/REPOSITORY/releases/latest/download/appcast.xml"
PNGSMITH_SPARKLE_PUBLIC_KEY="BASE64_PUBLIC_KEY"
```

For tagged GitHub releases, configure `SPARKLE_PUBLIC_KEY` as a repository variable and `SPARKLE_PRIVATE_KEY` as a repository secret. The workflow signs the update archive, generates `appcast.xml`, and attaches both files to the release.

The checked-in workflow currently produces an unsigned app artifact. Public distribution still requires Developer ID signing and Apple notarization.
