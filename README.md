<p align="center">
  <img src="docs/assets/readme-hero.png" alt="PNGSmith for macOS — compress PNGs and compare the exact result" width="100%">
</p>

<p align="center">
  A native macOS PNG compressor with exact before-and-after previews.<br>
  Lossless optimization, intelligent color reduction, and cropping all run privately on your Mac.
</p>

<p align="center">
  <img alt="macOS 14 or newer" src="https://img.shields.io/badge/macOS-14%2B-111316?style=flat-square&logo=apple&logoColor=white">
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-111316?style=flat-square"></a>
</p>

## Preview the real output

PNGSmith creates the optimized file before you save it. The preview and reported size come from that file—not an approximation.

- **Lossless compression** rewrites inefficient encoding while keeping decoded pixels identical.
- **Balanced, Smaller, and Manual** modes reduce oversized palettes.
- **Flexible comparisons** switch between hold-to-compare, a draggable divider, and horizontal or vertical pairs.
- **Crop and batch tools** handle one-off edits, multiple tabs, and entire folders.

## Choose the right compression

| Mode | What changes | Good for |
|---|---|---|
| **Lossless** | Encoding only; decoded pixels remain identical | Source images, screenshots, and UI assets |
| **Balanced** | Similar colors may be merged conservatively | Most web images |
| **Smaller** | Pushes color reduction further | Images where file size matters most |
| **Manual** | Uses an exact maximum of 2–256 colors | Deliberate palette control |

Animated PNGs are verified frame by frame. Crop and color reduction stay disabled rather than silently flattening them.

## At home on macOS

Drop in one image, several images, or an entire folder. Return to the previous session, or work through Finder Quick Actions, Services, Shortcuts, and the bundled CLI. Each image keeps its own settings.

Everything runs locally, metadata is preserved by default, and both Apple silicon and Intel Macs are supported.

## Install

PNGSmith currently builds from source. Sign in to Xcode, then run:

```sh
brew install xcodegen
./scripts/development-install.sh YOUR_APPLE_TEAM_ID
```

Requirements: macOS 14+, Xcode 16+, Rust 1.85.1+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The script installs a signed build in `~/Applications` with its Finder actions.

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

The app, Finder extensions, Services, Shortcuts action, CLI, and C ABI all use the same Rust compression core.

## Development

See the [developer guide](docs/DEVELOPMENT.md) for builds, tests, architecture, the JSON API, and releases. A [GitHub social preview](docs/assets/opengraph-image.jpg) is also included.

## License

[MIT](LICENSE)
