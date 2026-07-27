<p align="center">
  <img src="docs/assets/readme-hero.png" alt="PNGSmith — PNG compression for macOS" width="100%">
</p>

<p align="center">
  A Mac app for smaller PNGs—without guessing.<br>
  Preview the exact output, compare it with the original, and keep all processing on your Mac.
</p>

<p align="center">
  <img alt="macOS 26 or newer" src="https://img.shields.io/badge/macOS-26%2B-111316?style=flat-square&logo=apple&logoColor=white">
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-111316?style=flat-square"></a>
</p>

## See exactly what you’ll save

<p align="center">
  <img src="docs/assets/app-preview.png" alt="PNGSmith reducing a PNG to 100 colors with an 80% size reduction" width="100%">
</p>

PNGSmith compresses the image first, then shows you that exact file. The preview and file size are never estimates.

- **Keep every pixel** with lossless compression.
- **Reduce colors when size matters** with Balanced, Smaller, or a manual color limit.
- **Compare before and after** by holding to reveal the original, dragging a divider, or viewing both images side by side.
- **Work on one image or a whole folder**, with cropping and per-image settings built in.

## Pick the right mode

| Mode | What changes | Good for |
|---|---|---|
| **Lossless** | Keeps every decoded pixel identical | Source images, screenshots, and UI assets |
| **Balanced** | Carefully combines similar colors | Most web images |
| **Smaller** | Reduces colors more aggressively | Images where file size matters most |
| **Manual** | Caps the palette at 2–256 colors | Precise palette control |

Balanced and Smaller are safe to run again. Once an image fits the chosen palette, later passes keep its colors and use lossless compression.

Animated PNGs stay animated. PNGSmith verifies every frame and disables cropping and color reduction when they could flatten the animation.

## From one image to an entire folder

Drop in a PNG, several PNGs, or a folder. Each image keeps its own settings, and PNGSmith reopens your previous session when you come back.

Prefer automation? The same compression engine is available through Finder Quick Actions, Services, Shortcuts, and the CLI.

All processing happens locally. Metadata is preserved by default, and PNGSmith supports both Apple silicon and Intel Macs.

## Install

PNGSmith is currently available as a source build. Sign in to Xcode, then run:

```sh
brew install xcodegen
./scripts/development-install.sh YOUR_APPLE_TEAM_ID
```

Requirements: macOS 26+, Xcode 26+, Rust 1.85.1+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The script installs a signed app in `~/Applications` and includes its Finder Quick Actions.

## CLI

```sh
cargo build --release --package pngsmith-cli --all-features

# Smart lossless → image_min.png
target/release/pngsmith image.png

# At most 64 colors
target/release/pngsmith --mode perceptual --colors 64 image.png

# Automatic balanced palette
target/release/pngsmith --mode auto --auto-strategy balanced image.png
```

The app, Finder integrations, Shortcuts action, and CLI all use the same Rust compression core. A C ABI is also available for other integrations.

## Development

See the [developer guide](docs/DEVELOPMENT.md) for builds, tests, architecture, the JSON API, and releases.
