import Foundation

struct PNGSmithRequest: Codable, Sendable {
    var inputs: [String]
    var crop: CropOptions?
    var canvas: CanvasOptions?
    var mode: String
    var maxColors: Int?
    var fallback: String
    var output: OutputOptions
    var lossless: LosslessOptions
    var perceptual: PerceptualOptions
    var automatic: AutomaticOptions
    var verify: VerifyOptions

    enum CodingKeys: String, CodingKey {
        case inputs, crop, canvas, mode, fallback, output, lossless, perceptual, automatic, verify
        case maxColors = "max_colors"
    }
}

struct CropOptions: Codable, Hashable, Sendable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
}

struct CanvasOptions: Codable, Hashable, Sendable {
    var width: Int
    var height: Int
    var imageScale: Double
    var imageOffsetX: Int
    var imageOffsetY: Int

    enum CodingKeys: String, CodingKey {
        case width, height
        case imageScale = "image_scale"
        case imageOffsetX = "image_offset_x"
        case imageOffsetY = "image_offset_y"
    }
}

struct OutputOptions: Codable, Sendable {
    var createCopy: Bool
    var suffix: String
    var onlyIfSmaller: Bool

    enum CodingKeys: String, CodingKey {
        case suffix
        case createCopy = "create_copy"
        case onlyIfSmaller = "only_if_smaller"
    }
}

struct LosslessOptions: Codable, Sendable {
    var oxipngLevel: Int
    var zopfli: Bool
    var preserveMetadata: Bool
    var metadata: String
    var preserveTransparentRGB: Bool
    var allowLosslessPalette: Bool
    var scale16Bit: Bool
    var maxDecompressedBytes: Int

    enum CodingKeys: String, CodingKey {
        case zopfli, metadata
        case oxipngLevel = "oxipng_level"
        case preserveMetadata = "preserve_metadata"
        case preserveTransparentRGB = "preserve_transparent_rgb"
        case allowLosslessPalette = "allow_lossless_palette"
        case scale16Bit = "scale_16_bit"
        case maxDecompressedBytes = "max_decompressed_bytes"
    }
}

struct PerceptualOptions: Codable, Sendable {
    var qualityMin: Int
    var qualityMax: Int

    enum CodingKeys: String, CodingKey {
        case qualityMin = "quality_min"
        case qualityMax = "quality_max"
    }
}

struct AutomaticOptions: Codable, Sendable {
    var strategy: String
}

struct VerifyOptions: Codable, Sendable {
    var decodedPixels: Bool
    enum CodingKeys: String, CodingKey { case decodedPixels = "decoded_pixels" }
}

struct PNGSmithResponse: Codable, Sendable {
    let ok: Bool
    let error: String?
    let results: [PNGSmithResult]
}

struct PNGSmithResult: Codable, Sendable {
    let input: String
    let output: String?
    let originalBytes: UInt64?
    let outputBytes: UInt64?
    let actualMode: String?
    let paletteEntries: Int?
    let colorBudget: Int?
    let pixelIdentical: Bool?
    let lossy: Bool
    let written: Bool
    let skippedReason: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case input, output, lossy, written, error
        case originalBytes = "original_bytes"
        case outputBytes = "output_bytes"
        case actualMode = "actual_mode"
        case paletteEntries = "palette_entries"
        case colorBudget = "color_budget"
        case pixelIdentical = "pixel_identical"
        case skippedReason = "skipped_reason"
    }
}

struct PNGSmithSettings: Codable, Sendable, Equatable {
    var mode = "smart_lossless"
    var maxColors = 256
    var fallback = "lossless"
    var createCopy = true
    var suffix = "_min"
    var onlyIfSmaller = true
    var oxipngLevel = 4
    var zopfli = false
    var metadata = "preserve"
    var qualityMin = 90
    var qualityMax = 100
    var verifyPixels = true

    /// Maps a Finder button onto the user's saved settings. "compress" keeps
    /// every pixel identical; "reduce-256" blends into at most 256 colors and
    /// must never fail on a quality gate, so it uses the full quality range.
    mutating func apply(finderAction: String?) {
        if finderAction == "reduce-256" {
            mode = "perceptual"
            maxColors = 256
            fallback = "lossless"
            qualityMin = 0
            qualityMax = 100
        } else {
            mode = "smart_lossless"
        }
    }

    func request(inputs: [URL]) -> PNGSmithRequest {
        PNGSmithRequest(
            inputs: inputs.map(\.path),
            crop: nil,
            canvas: nil,
            mode: mode,
            maxColors: maxColors,
            fallback: fallback,
            output: OutputOptions(createCopy: createCopy, suffix: suffix, onlyIfSmaller: onlyIfSmaller),
            lossless: LosslessOptions(
                oxipngLevel: oxipngLevel,
                zopfli: zopfli,
                preserveMetadata: metadata == "preserve",
                metadata: metadata,
                preserveTransparentRGB: true,
                allowLosslessPalette: true,
                scale16Bit: false,
                maxDecompressedBytes: 512 * 1024 * 1024
            ),
            perceptual: PerceptualOptions(qualityMin: qualityMin, qualityMax: qualityMax),
            automatic: AutomaticOptions(strategy: "balanced"),
            verify: VerifyOptions(decodedPixels: verifyPixels)
        )
    }
}
