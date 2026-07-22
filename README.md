<p align="center">
  <img src="docs/assets/readme-hero.png" alt="PNGSmith for macOS — compress PNGs and compare the exact result" width="100%">
</p>

<p align="center">
  <strong>Compress PNGs without guessing what changed.</strong><br>
  A native macOS app for lossless optimization, intelligent color reduction, cropping, and exact before-and-after comparison.
</p>

<p align="center">
  <img alt="macOS 14 or newer" src="https://img.shields.io/badge/macOS-14%2B-111316?style=flat-square&logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-111316?style=flat-square&logo=swift&logoColor=F05138">
  <img alt="Rust" src="https://img.shields.io/badge/Rust-1.85.1%2B-111316?style=flat-square&logo=rust&logoColor=white">
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-111316?style=flat-square"></a>
</p>

## What it does

PNGSmith encodes the candidate result first, then shows those exact bytes in the preview. You see the final image and file size before anything is saved.

- **Lossless optimization** keeps every decoded pixel identical.
- **Color reduction** uses Auto or a manual 2–256 color budget for smaller files.
- **Live comparison** lets you drag the divider or hold for the original.
- **Built-in crop** supports freeform, Square, 4:3, 16:9, 2:1, and exact output sizes.
- **Private by design** keeps processing on-device and preserves metadata by default.

Save a copy, replace the original, or use **Save As…**. PNGSmith remembers your preferences and last image.

## Choose the trade-off

| | Lossless | Reduce colors |
|---|---|---|
| Pixels | Identical | Similar colors may blend |
| Best for | Source images and UI assets | Web graphics and oversized palettes |
| Control | Fast, Balanced, or Maximum | Auto (Balanced or Smaller), or 2–256 colors |
| Preview | Exact output | Exact output |

Animated PNGs are optimized and verified frame by frame. Cropping and color reduction stay unavailable for animations, so they can never be silently flattened.

## Native macOS workflow

PNGSmith works with drag and drop, Finder Quick Actions, Services, Shortcuts, and a bundled CLI. It supports Apple silicon and Intel Macs, plus Sparkle automatic updates.

## Build and install

PNGSmith currently builds from source. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen), sign in to Xcode, then run:

```sh
brew install xcodegen
./scripts/development-install.sh YOUR_APPLE_TEAM_ID
```

This installs a signed development build in `~/Applications` and enables the complete Finder workflow. Requirements: macOS 14+, Xcode 16+, and Rust 1.85.1+.

## CLI

```sh
cargo build --release --package pngsmith-cli --all-features

# Writes image_min.png using smart lossless optimization.
target/release/pngsmith image.png

# Reduce to at most 64 colors.
target/release/pngsmith --mode perceptual --colors 64 image.png

# Let the Rust core choose a balanced color budget.
target/release/pngsmith --mode auto --auto-strategy balanced image.png
```

The app, extensions, Services, Shortcuts action, CLI, and C ABI all use the same Rust compression core.

## Development

Build commands, tests, architecture, JSON API, and release instructions are in the [developer guide](docs/DEVELOPMENT.md).

The GitHub social-preview image is available at [`docs/assets/opengraph-image.png`](docs/assets/opengraph-image.png).

## License

[MIT](LICENSE)
