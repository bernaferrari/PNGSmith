import AppIntents
import Foundation
import UniformTypeIdentifiers

enum PNGCompressionMode: String, AppEnum {
    case smartLossless, lossless, exactPalette, perceptual, automaticPalette

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "PNG Compression Mode")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .smartLossless: "Compress (Pixels Identical)",
        .lossless: "Compress Without Color Table (Pixels Identical)",
        .exactPalette: "Reduce Colors Only If Identical",
        .perceptual: "Reduce Colors (May Change Pixels)",
        .automaticPalette: "Reduce Colors Automatically"
    ]

    var coreValue: String {
        switch self {
        case .smartLossless: "smart_lossless"
        case .lossless: "lossless"
        case .exactPalette: "exact_palette"
        case .perceptual: "perceptual"
        case .automaticPalette: "automatic_palette"
        }
    }
}

enum PNGAutomaticStrategy: String, AppEnum {
    case balanced, smaller

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Automatic Strategy")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .balanced: "Balanced",
        .smaller: "Smaller"
    ]
}

struct CompressPNGIntent: AppIntent {
    static let title: LocalizedStringResource = "Compress PNG"
    static let description = IntentDescription("Compress PNG files with the embedded PNGSmith engine.")
    static let openAppWhenRun = false

    @Parameter(title: "PNG Files", supportedTypeIdentifiers: ["public.png"]) var files: [IntentFile]
    @Parameter(title: "Mode", default: .smartLossless) var mode: PNGCompressionMode
    @Parameter(title: "Maximum Colors", default: 256, inclusiveRange: (2, 256)) var maximumColors: Int
    @Parameter(title: "Automatic Strategy", default: .balanced) var automaticStrategy: PNGAutomaticStrategy
    @Parameter(title: "Create Copy", default: true) var createCopy: Bool
    @Parameter(title: "Filename Suffix", default: "_min") var suffix: String
    @Parameter(title: "Only Keep Smaller Results", default: false) var onlyIfSmaller: Bool

    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        let directory = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        var inputs: [URL] = []
        for file in files {
            let target = directory.appendingPathComponent(file.filename)
            if let source = file.fileURL {
                try FileManager.default.copyItem(at: source, to: target)
            } else {
                try file.data.write(to: target, options: .atomic)
            }
            inputs.append(target)
        }
        var settings = PNGSmithSettings()
        settings.mode = mode.coreValue
        settings.maxColors = maximumColors
        settings.fallback = mode == .exactPalette ? "error" : "lossless"
        settings.createCopy = createCopy
        settings.suffix = suffix
        settings.onlyIfSmaller = onlyIfSmaller
        if mode == .perceptual {
            settings.qualityMin = 0
            settings.qualityMax = 100
        }
        var request = settings.request(inputs: inputs)
        request.automatic = AutomaticOptions(strategy: automaticStrategy.rawValue)
        let response = try PNGSmithCore.execute(request)
        let outputs = response.results.compactMap(\.output).map { path in
            IntentFile(fileURL: URL(fileURLWithPath: path), type: .png)
        }
        return .result(value: outputs)
    }
}
