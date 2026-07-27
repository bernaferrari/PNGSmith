import Foundation

enum WorkItemOrigin: Equatable, Sendable {
    case file
    case clipboard
}

struct WorkItem: Identifiable, Equatable, Sendable {
    var id: URL { url }
    let url: URL
    let securityScoped: Bool
    let originalBytes: UInt64
    let pixelWidth: Int
    let pixelHeight: Int
    let frameCount: Int
    let origin: WorkItemOrigin

    init(
        url: URL,
        securityScoped: Bool,
        originalBytes: UInt64,
        pixelWidth: Int,
        pixelHeight: Int,
        frameCount: Int,
        origin: WorkItemOrigin = .file
    ) {
        self.url = url
        self.securityScoped = securityScoped
        self.originalBytes = originalBytes
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.frameCount = frameCount
        self.origin = origin
    }

    var isAnimated: Bool { frameCount > 1 }
    var isClipboardItem: Bool { origin == .clipboard }

    func supportedMode(requested: DashboardMode) -> DashboardMode {
        isAnimated ? .auto : requested
    }
}

enum DocumentTabNavigation {
    static func reordered<Element: Equatable>(
        _ elements: [Element],
        moving: Element,
        to target: Element
    ) -> [Element] {
        guard moving != target,
              let sourceIndex = elements.firstIndex(of: moving),
              let targetIndex = elements.firstIndex(of: target)
        else { return elements }

        var reordered = elements
        let movingElement = reordered.remove(at: sourceIndex)
        reordered.insert(movingElement, at: min(targetIndex, reordered.endIndex))
        return reordered
    }

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

    var totalCount: Int { writtenCount + skippedCount + failedCount }

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

struct PreviewBatchStatus: Equatable {
    enum ItemState: Equatable {
        case pending
        case ready
        case failed
    }

    let totalCount: Int
    let readyCount: Int
    let pendingCount: Int
    let failedCount: Int

    init(states: [ItemState]) {
        totalCount = states.count
        readyCount = states.count { $0 == .ready }
        pendingCount = states.count { $0 == .pending }
        failedCount = states.count { $0 == .failed }
    }

    var canSave: Bool { totalCount > 0 && readyCount == totalCount }
    var isPending: Bool { pendingCount > 0 }
}

enum ReplacementRisk: Equatable {
    case none
    case crop
    case colorReduction
    case cropAndColorReduction

    init(hasCropEdits: Bool, hasLossyPreviews: Bool) {
        switch (hasCropEdits, hasLossyPreviews) {
        case (false, false): self = .none
        case (true, false): self = .crop
        case (false, true): self = .colorReduction
        case (true, true): self = .cropAndColorReduction
        }
    }
}

enum SaveDestination: Equatable {
    case copies
    case replace
    case saveAs
}

enum ComparisonLayout: String, CaseIterable, Identifiable, Sendable {
    case hold
    case divider
    case sideBySide
    case stacked

    var id: Self { self }

    var title: String {
        switch self {
        case .hold: "Hold"
        case .divider: "Divider"
        case .sideBySide: "Left and Right"
        case .stacked: "Top and Bottom"
        }
    }
}

enum DashboardWorkspaceMode: Equatable, Sendable {
    case image
    case batch
}

enum PaletteProtectionPolicy {
    static func canAffect(
        reduceColors: Bool,
        autoColors: Bool,
        mode: DashboardMode,
        sourceColors: Int?,
        sourceColorsAtLeast: Int?
    ) -> Bool {
        guard reduceColors, autoColors, mode == .shrink else { return false }
        if let sourceColors {
            return sourceColors <= 256
        }
        return sourceColorsAtLeast == nil
    }
}

enum CropToolState: Equatable, Sendable {
    case inactive
    case presented(URL)
    case dismissing(URL)

    var itemURL: URL? {
        switch self {
        case .inactive: nil
        case .presented(let url), .dismissing(let url): url
        }
    }

    var showsChrome: Bool {
        if case .presented = self { return true }
        return false
    }

    var isActive: Bool { itemURL != nil }

    mutating func present(_ url: URL) {
        self = .presented(url)
    }

    mutating func beginDismissal() {
        guard case .presented(let url) = self else { return }
        self = .dismissing(url)
    }

    mutating func close() {
        self = .inactive
    }
}

enum ColorReductionPreset: String, CaseIterable, Identifiable, Sendable {
    case balanced
    case smaller
    case manual

    var id: Self { self }

    var title: String {
        switch self {
        case .balanced: "Balanced"
        case .smaller: "Smaller"
        case .manual: "Manual"
        }
    }

    var help: String {
        switch self {
        case .balanced: "Reduce colors while protecting fine detail"
        case .smaller: "Push further for a smaller result"
        case .manual: "Choose an exact maximum color count"
        }
    }
}

enum AutoColorStrategy: String, CaseIterable, Identifiable, Codable, Sendable {
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

struct ImageOptimizationSettings: Equatable, Codable, Sendable {
    static let supportedColorRange = 2...256

    var reduceColors: Bool
    var maxColors: Int
    var autoColors: Bool
    var autoStrategy: AutoColorStrategy

    var mode: DashboardMode { reduceColors ? .shrink : .auto }

    var colorReductionPreset: ColorReductionPreset? {
        guard reduceColors else { return nil }
        guard autoColors else { return .manual }
        return autoStrategy == .balanced ? .balanced : .smaller
    }

    mutating func apply(_ preset: ColorReductionPreset) {
        reduceColors = true
        switch preset {
        case .balanced:
            autoColors = true
            autoStrategy = .balanced
        case .smaller:
            autoColors = true
            autoStrategy = .smaller
        case .manual:
            autoColors = false
        }
    }

    mutating func applyManualColorCount(_ count: Int) {
        reduceColors = true
        autoColors = false
        maxColors = Self.clampedColorCount(count)
    }

    static func clampedColorCount(_ count: Int) -> Int {
        min(max(count, supportedColorRange.lowerBound), supportedColorRange.upperBound)
    }
}

struct OptimizationGroupSummary: Equatable, Sendable {
    let colorReductionEnabled: Bool
    let preset: ColorReductionPreset?
    let manualColorCount: Int?
    let status: String?

    init(_ settings: [ImageOptimizationSettings]) {
        guard let first = settings.first else {
            colorReductionEnabled = false
            preset = nil
            manualColorCount = nil
            status = nil
            return
        }

        let allEnabled = settings.allSatisfy(\.reduceColors)
        colorReductionEnabled = allEnabled
        guard allEnabled else {
            preset = nil
            manualColorCount = nil
            status = settings.allSatisfy({ !$0.reduceColors }) ? nil : "Mixed"
            return
        }

        let candidatePreset = first.colorReductionPreset
        guard settings.allSatisfy({ $0.colorReductionPreset == candidatePreset }) else {
            preset = nil
            manualColorCount = nil
            status = "Mixed"
            return
        }

        preset = candidatePreset
        if candidatePreset == .manual {
            let commonCount = settings.allSatisfy({ $0.maxColors == first.maxColors })
                ? first.maxColors
                : nil
            manualColorCount = commonCount
            status = commonCount == nil ? "Mixed" : nil
        } else {
            manualColorCount = nil
            status = nil
        }
    }
}
