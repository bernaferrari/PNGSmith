import Foundation

enum DashboardSavePipeline {
    static func request(
        item: WorkItem,
        mode: DashboardMode,
        variant: PreviewVariant,
        settings: PNGSmithSettings
    ) async throws -> PNGSmithRequest {
        var request = settings.request(inputs: [item.url])
        request.crop = nil
        request.canvas = variant.crop
        switch mode {
        case .auto:
            request.mode = "smart_lossless"
            request.maxColors = 256
            request.fallback = "lossless"
        case .shrink:
            if let automaticStrategy = variant.automaticStrategy {
                request.mode = "automatic_palette"
                request.maxColors = 256
                request.fallback = "lossless"
                request.automatic = AutomaticOptions(strategy: automaticStrategy)
            } else {
                let outcome = try await PreviewEngine.shared.preview(source: item.url, variant: variant)
                if outcome.actualMode == "exact_palette" {
                    request.mode = "exact_palette"
                    request.fallback = "error"
                } else {
                    request.mode = "perceptual"
                    request.fallback = "lossless"
                }
                request.maxColors = variant.maxColors
                request.perceptual = PerceptualOptions(
                    qualityMin: variant.qualityMin,
                    qualityMax: variant.qualityMax
                )
            }
        }
        return request
    }

    static func writePreview(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".pngsmith-\(UUID().uuidString).png")
        defer { try? fileManager.removeItem(at: staging) }

        try fileManager.copyItem(at: source, to: staging)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }
    }

    static func failure(for item: WorkItem, error: Error) -> PNGSmithResult {
        PNGSmithResult(
            input: item.url.path,
            output: nil,
            originalBytes: nil,
            outputBytes: nil,
            actualMode: nil,
            paletteEntries: nil,
            colorBudget: nil,
            pixelIdentical: nil,
            lossy: false,
            written: false,
            skippedReason: nil,
            error: error.localizedDescription
        )
    }
}
