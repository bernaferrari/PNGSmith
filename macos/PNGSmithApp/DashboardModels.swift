import Foundation

struct WorkItem: Identifiable, Equatable, Sendable {
    var id: URL { url }
    let url: URL
    let securityScoped: Bool
    let originalBytes: UInt64
    let pixelWidth: Int
    let pixelHeight: Int
    let frameCount: Int

    var isAnimated: Bool { frameCount > 1 }

    func supportedMode(requested: DashboardMode) -> DashboardMode {
        isAnimated ? .auto : requested
    }
}

enum DocumentTabNavigation {
    static func selection(
        afterRemoving removed: URL,
        from orderedURLs: [URL],
        selected: URL?
    ) -> URL? {
        guard let removedIndex = orderedURLs.firstIndex(of: removed) else {
            return selected ?? orderedURLs.first
        }
        guard selected == removed else { return selected }
        if removedIndex + 1 < orderedURLs.count {
            return orderedURLs[removedIndex + 1]
        }
        if removedIndex > 0 {
            return orderedURLs[removedIndex - 1]
        }
        return nil
    }

    static func selection(
        offset: Int,
        from orderedURLs: [URL],
        selected: URL?
    ) -> URL? {
        guard !orderedURLs.isEmpty else { return nil }
        let index = selected.flatMap { orderedURLs.firstIndex(of: $0) } ?? 0
        let destination = (index + offset % orderedURLs.count + orderedURLs.count)
            % orderedURLs.count
        return orderedURLs[destination]
    }
}

struct SaveSummary: Equatable, Sendable {
    let writtenCount: Int
    let skippedCount: Int
    let failedCount: Int
    let savedBytes: Int64
    let firstOutput: String?

    init(results: [PNGSmithResult]) {
        writtenCount = results.filter(\.written).count
        failedCount = results.filter { $0.error != nil }.count
        skippedCount = results.filter { $0.error == nil && !$0.written }.count
        savedBytes = results.reduce(0) { total, result in
            guard result.written,
                  let original = result.originalBytes,
                  let output = result.outputBytes,
                  original > output
            else { return total }
            return total + Int64(original - output)
        }
        firstOutput = results.compactMap(\.output).first
    }
}

enum SaveDestination: Equatable {
    case copies
    case replace
    case saveAs
}

enum AutoColorStrategy: String, CaseIterable, Identifiable {
    case balanced
    case smaller

    var id: Self { self }

    var title: String {
        switch self {
        case .balanced: "Balanced"
        case .smaller: "Smaller"
        }
    }

    var help: String {
        switch self {
        case .balanced: "Reduces size while protecting fine detail."
        case .smaller: "Pushes further and may soften subtle detail."
        }
    }
}
