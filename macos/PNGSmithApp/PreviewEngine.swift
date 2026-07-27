import Foundation

enum DashboardMode: String, CaseIterable, Sendable {
    case auto
    case shrink
}

/// Everything that changes the compressed bytes. Output options (copy/suffix)
/// are deliberately excluded so previews stay valid while they change.
struct PreviewVariant: Hashable, Sendable {
    var mode: DashboardMode
    var maxColors: Int
    var oxipngLevel: Int
    var zopfli: Bool
    var metadata: String
    var qualityMin: Int
    var qualityMax: Int
    var automaticStrategy: String?
    var protectExistingPalette: Bool
    var verifyPixels: Bool
    var crop: CanvasOptions?

    init(
        mode: DashboardMode,
        maxColors: Int,
        settings: PNGSmithSettings,
        automaticStrategy: String? = nil,
        protectExistingPalette: Bool = true,
        crop: CanvasOptions? = nil
    ) {
        self.mode = mode
        self.maxColors = mode == .auto || automaticStrategy != nil
            ? 256
            : min(max(maxColors, 2), 256)
        oxipngLevel = settings.oxipngLevel
        zopfli = settings.zopfli
        metadata = settings.metadata
        qualityMin = mode == .shrink ? 0 : settings.qualityMin
        qualityMax = mode == .shrink ? 100 : settings.qualityMax
        self.automaticStrategy = automaticStrategy
        self.protectExistingPalette = protectExistingPalette
        verifyPixels = settings.verifyPixels
        self.crop = crop
    }

    fileprivate func fileToken(coreMode: String) -> String {
        var token = ".preview-\(coreMode)-\(maxColors)-o\(oxipngLevel)"
        if zopfli { token += "z" }
        token += "-\(metadata)"
        if coreMode == "perceptual" { token += "-q\(qualityMin)-\(qualityMax)" }
        if let automaticStrategy { token += "-\(automaticStrategy)" }
        return token
    }

    fileprivate var cacheToken: String {
        "\(mode.rawValue)|\(maxColors)|\(oxipngLevel)|\(zopfli)|\(metadata)|\(qualityMin)|\(qualityMax)|\(automaticStrategy ?? "manual")|\(protectExistingPalette)|\(verifyPixels)|\(cropToken)"
    }

    private var cropToken: String {
        guard let crop else { return "full" }
        return "\(crop.width),\(crop.height),\(crop.imageScale),\(crop.imageOffsetX),\(crop.imageOffsetY)"
    }
}

struct PreviewOutcome: Equatable, Sendable {
    let outputURL: URL
    let comparisonSourceURL: URL
    let originalBytes: UInt64
    let outputBytes: UInt64
    let actualMode: String
    let paletteEntries: Int?
    let colorBudget: Int?
    let sourceColors: Int?
    let sourceColorsAtLeast: Int?
    let lossy: Bool
    let neededColors: Int?

    var savedBytes: Int64 { Int64(originalBytes) - Int64(outputBytes) }

    var savedFraction: Double {
        guard originalBytes > 0 else { return 0 }
        return max(0, 1 - Double(outputBytes) / Double(originalBytes))
    }
}

enum PreviewPhase: Equatable {
    case loading(previous: PreviewOutcome?)
    case ready(PreviewOutcome)
    case failed(String)

    var lastKnownOutcome: PreviewOutcome? {
        switch self {
        case .ready(let outcome): outcome
        case .loading(let previous): previous
        case .failed: nil
        }
    }

    var readyOutcome: PreviewOutcome? {
        if case .ready(let outcome) = self { return outcome }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var isInitialLoading: Bool {
        if case .loading(previous: nil) = self { return true }
        return false
    }

    var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// Computes exact size previews by running the real compression on a temporary
/// copy of each source file, so the numbers shown are the numbers saved.
actor PreviewEngine {
    static let shared = PreviewEngine()

    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pngsmith-previews-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    private var sourceCopies: [URL: URL] = [:]
    private var outcomes: [String: PreviewOutcome] = [:]
    private var cropSources: [String: URL] = [:]
    private var neededColors: [URL: Int] = [:]
    private var folderIndex = 0

    func preview(source: URL, variant: PreviewVariant) async throws -> PreviewOutcome {
        let key = "\(source.path)|\(variant.cacheToken)"
        if let cached = outcomes[key], FileManager.default.fileExists(atPath: cached.outputURL.path) {
            return cached
        }
        let copy = try sourceCopy(of: source)
        let comparisonSourceURL = try await comparisonSource(
            original: source,
            copy: copy,
            variant: variant
        )
        let outcome: PreviewOutcome
        switch variant.mode {
        case .auto:
            outcome = makeOutcome(
                try await run(copy: copy, coreMode: "smart_lossless", fallback: "lossless", variant: variant),
                source: source,
                comparisonSourceURL: comparisonSourceURL
            )
        case .shrink:
            if variant.automaticStrategy != nil {
                outcome = makeOutcome(
                    try await run(copy: copy, coreMode: "automatic_palette", fallback: "lossless", variant: variant),
                    source: source,
                    comparisonSourceURL: comparisonSourceURL
                )
            } else {
                do {
                    outcome = makeOutcome(
                        try await run(copy: copy, coreMode: "exact_palette", fallback: "error", variant: variant),
                        source: source,
                        comparisonSourceURL: comparisonSourceURL
                    )
                } catch {
                    if let needed = Self.colorsNeeded(in: error) { neededColors[source] = needed }
                    outcome = makeOutcome(
                        try await run(copy: copy, coreMode: "perceptual", fallback: "lossless", variant: variant),
                        source: source,
                        comparisonSourceURL: comparisonSourceURL
                    )
                }
            }
        }
        outcomes[key] = outcome
        return outcome
    }

    func forget(source: URL) {
        neededColors[source] = nil
        outcomes = outcomes.filter { !$0.key.hasPrefix("\(source.path)|") }
        cropSources = cropSources.filter { !$0.key.hasPrefix("\(source.path)|") }
        if let copy = sourceCopies.removeValue(forKey: source) {
            try? FileManager.default.removeItem(at: copy.deletingLastPathComponent())
        }
    }

    private func sourceCopy(of source: URL) throws -> URL {
        if let existing = sourceCopies[source], FileManager.default.fileExists(atPath: existing.path) {
            return existing
        }
        folderIndex += 1
        let directory = root.appendingPathComponent("item-\(folderIndex)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
        sourceCopies[source] = destination
        return destination
    }

    private func run(copy: URL, coreMode: String, fallback: String, variant: PreviewVariant) async throws -> PNGSmithResult {
        let request = PNGSmithRequest(
            inputs: [copy.path],
            crop: nil,
            canvas: variant.crop,
            mode: coreMode,
            maxColors: variant.maxColors,
            fallback: fallback,
            output: OutputOptions(createCopy: true, suffix: variant.fileToken(coreMode: coreMode), onlyIfSmaller: false),
            lossless: LosslessOptions(
                oxipngLevel: variant.oxipngLevel,
                zopfli: variant.zopfli,
                preserveMetadata: variant.metadata == "preserve",
                metadata: variant.metadata,
                preserveTransparentRGB: true,
                allowLosslessPalette: true,
                scale16Bit: false,
                maxDecompressedBytes: 512 * 1024 * 1024
            ),
            perceptual: PerceptualOptions(qualityMin: variant.qualityMin, qualityMax: variant.qualityMax),
            automatic: AutomaticOptions(
                strategy: variant.automaticStrategy ?? "balanced",
                protectExistingPalette: variant.protectExistingPalette
            ),
            verify: VerifyOptions(decodedPixels: variant.verifyPixels)
        )
        let response = try await PNGSmithCore.executeAsync(request)
        guard let result = response.results.first else {
            throw PNGSmithBridgeError.emptyResponse
        }
        return result
    }

    private func comparisonSource(
        original: URL,
        copy: URL,
        variant: PreviewVariant
    ) async throws -> URL {
        guard let crop = variant.crop else { return original }
        let key = "\(original.path)|\(crop.width),\(crop.height),\(crop.imageScale),\(crop.imageOffsetX),\(crop.imageOffsetY)"
        if let cached = cropSources[key], FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        let request = PNGSmithRequest(
            inputs: [copy.path],
            crop: nil,
            canvas: crop,
            mode: "lossless",
            maxColors: 256,
            fallback: "lossless",
            output: OutputOptions(
                createCopy: true,
                suffix: ".canvas-source-\(abs(key.hashValue))",
                onlyIfSmaller: false
            ),
            lossless: LosslessOptions(
                oxipngLevel: 0,
                zopfli: false,
                preserveMetadata: variant.metadata == "preserve",
                metadata: variant.metadata,
                preserveTransparentRGB: true,
                allowLosslessPalette: false,
                scale16Bit: false,
                maxDecompressedBytes: 512 * 1024 * 1024
            ),
            perceptual: PerceptualOptions(qualityMin: 0, qualityMax: 100),
            automatic: AutomaticOptions(strategy: "balanced", protectExistingPalette: true),
            verify: VerifyOptions(decodedPixels: false)
        )
        let response = try await PNGSmithCore.executeAsync(request)
        guard let result = response.results.first,
              let output = result.output
        else { throw PNGSmithBridgeError.emptyResponse }
        let url = URL(fileURLWithPath: output)
        cropSources[key] = url
        return url
    }

    private func makeOutcome(
        _ result: PNGSmithResult,
        source: URL,
        comparisonSourceURL: URL
    ) -> PreviewOutcome {
        PreviewOutcome(
            outputURL: URL(fileURLWithPath: result.output ?? ""),
            comparisonSourceURL: comparisonSourceURL,
            originalBytes: result.originalBytes ?? 0,
            outputBytes: result.outputBytes ?? 0,
            actualMode: result.actualMode ?? "lossless",
            paletteEntries: result.paletteEntries,
            colorBudget: result.colorBudget,
            sourceColors: result.sourceColors,
            sourceColorsAtLeast: result.sourceColorsAtLeast,
            lossy: result.lossy,
            neededColors: neededColors[source]
        )
    }

    private static func colorsNeeded(in error: Error) -> Int? {
        let message: String = if case .coreError(let detail)? = error as? PNGSmithBridgeError {
            detail
        } else {
            error.localizedDescription
        }
        guard let range = message.range(of: #"at least \d+ colors"#, options: .regularExpression) else { return nil }
        let digits = message[range].filter(\.isNumber)
        return Int(digits)
    }
}
