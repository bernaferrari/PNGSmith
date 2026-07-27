import AppKit
import ImageIO
import SwiftUI

extension CompressionDashboard {
    // MARK: - Preview refresh

    var currentVariant: PreviewVariant {
        guard let item = selectedItem else {
            return PreviewVariant(
                mode: defaultOptimizationSettings.mode,
                maxColors: defaultOptimizationSettings.maxColors,
                settings: store.settings,
                protectExistingPalette: protectExistingPalette
            )
        }
        return previewVariant(
            for: item,
            optimization: optimization(for: item),
            settings: store.settings
        )
    }

    func previewVariant(
        for item: WorkItem,
        optimization: ImageOptimizationSettings,
        settings: PNGSmithSettings
    ) -> PreviewVariant {
        let supportedMode = item.supportedMode(requested: optimization.mode)
        return PreviewVariant(
            mode: supportedMode,
            maxColors: optimization.maxColors,
            settings: settings,
            automaticStrategy: supportedMode == .shrink && optimization.autoColors
                ? optimization.autoStrategy.rawValue
                : nil,
            protectExistingPalette: protectExistingPalette,
            crop: cropOptions(for: item)
        )
    }

    func cropOptions(for item: WorkItem) -> CanvasOptions? {
        cropSelections[item.url]?.pixelOptions(
            imageWidth: item.pixelWidth,
            imageHeight: item.pixelHeight
        )
    }

    func updateOptimizations(
        for targetItems: [WorkItem],
        debounced: Bool = false,
        _ update: (inout ImageOptimizationSettings) -> Void
    ) {
        guard !targetItems.isEmpty else { return }
        var firstUpdatedOptimization: ImageOptimizationSettings?

        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
            for item in targetItems {
                var optimization = optimization(for: item)
                update(&optimization)
                imageOptimizations[item.url] = optimization
                automaticColorBudgets[item.url] = nil
                if firstUpdatedOptimization == nil {
                    firstUpdatedOptimization = optimization
                }
            }
        }

        if let optimization = firstUpdatedOptimization {
            reduceColorsEnabled = optimization.reduceColors
            maxColorCount = optimization.maxColors
            autoColorsEnabled = optimization.autoColors
            autoColorStrategyRawValue = optimization.autoStrategy.rawValue
        }

        rememberImageOptimizations()
        saveSummary = nil
        sliderDebounce?.cancel()
        if debounced {
            sliderDebounce = Task {
                try? await Task.sleep(for: .milliseconds(260))
                guard !Task.isCancelled else { return }
                refreshPreviews()
            }
        } else {
            refreshPreviews()
        }
    }

    func refreshPreviews() {
        guard !items.isEmpty else { return }
        showingOriginal = false
        generation += 1
        let currentGeneration = generation
        var ordered = items.map(\.url)
        if let selected = selectedItem?.url, let index = ordered.firstIndex(of: selected) {
            ordered.remove(at: index)
            ordered.insert(selected, at: 0)
        }
        schedulePreviews(for: ordered, generation: currentGeneration)
    }

    func refreshPreviews(for urls: [URL]) {
        let openURLs = Set(items.map(\.url))
        var seen = Set<URL>()
        let ordered = urls.filter { openURLs.contains($0) && seen.insert($0).inserted }
        guard !ordered.isEmpty else { return }
        schedulePreviews(for: ordered, generation: generation)
    }

    private func schedulePreviews(for ordered: [URL], generation currentGeneration: Int) {
        let settings = store.settings
        let defaults = defaultOptimizationSettings
        let optimizations = imageOptimizations
        let crops = cropSelections
        let paletteProtection = protectExistingPalette
        for url in ordered {
            previews[url] = .loading(previous: previews[url]?.lastKnownOutcome)
        }
        saveSummary = nil
        Task {
            for url in ordered {
                guard generation == currentGeneration else { return }
                guard let item = items.first(where: { $0.url == url }) else { continue }
                let crop = crops[url]?.pixelOptions(
                    imageWidth: item.pixelWidth,
                    imageHeight: item.pixelHeight
                )
                do {
                    let optimization = optimizations[url] ?? defaults
                    let itemMode = item.supportedMode(requested: optimization.mode)
                    let usesAutomaticPalette = optimization.autoColors && itemMode == .shrink
                    let variant = PreviewVariant(
                        mode: itemMode,
                        maxColors: optimization.maxColors,
                        settings: settings,
                        automaticStrategy: usesAutomaticPalette ? optimization.autoStrategy.rawValue : nil,
                        protectExistingPalette: paletteProtection,
                        crop: crop
                    )
                    let outcome = try await PreviewEngine.shared.preview(source: url, variant: variant)
                    guard generation == currentGeneration else { return }
                    guard items.contains(where: { $0.url == url }) else { continue }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        if usesAutomaticPalette {
                            automaticColorBudgets[url] = outcome.colorBudget
                        }
                        previews[url] = .ready(outcome)
                    }
                } catch {
                    guard generation == currentGeneration else { return }
                    guard items.contains(where: { $0.url == url }) else { continue }
                    previews[url] = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - File management

    func expandedPNGURLs(from urls: [URL]) -> (urls: [URL], containsDirectory: Bool, rejectedCount: Int) {
        var results: [URL] = []
        var containsDirectory = false
        var rejectedCount = 0

        for url in urls {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            guard isDirectory else {
                if url.pathExtension.caseInsensitiveCompare("png") == .orderedSame {
                    results.append(url)
                } else {
                    rejectedCount += 1
                }
                continue
            }

            containsDirectory = true
            if !scopedDirectoryURLs.contains(url), url.startAccessingSecurityScopedResource() {
                scopedDirectoryURLs.insert(url)
            }

            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                rejectedCount += 1
                continue
            }

            var directoryPNGs: [URL] = []
            for case let childURL as URL in enumerator {
                guard childURL.pathExtension.caseInsensitiveCompare("png") == .orderedSame,
                      (try? childURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                else { continue }
                directoryPNGs.append(childURL)
            }
            if directoryPNGs.isEmpty { rejectedCount += 1 }
            results.append(contentsOf: directoryPNGs.sorted {
                $0.path.localizedStandardCompare($1.path) == .orderedAscending
            })
        }

        var seen = Set<URL>()
        return (
            results.filter { seen.insert($0.standardizedFileURL).inserted },
            containsDirectory,
            rejectedCount
        )
    }

    @discardableResult
    func add(_ urls: [URL]) -> Bool {
        let expansion = expandedPNGURLs(from: urls)
        let pngs = expansion.urls
        if pngs.isEmpty {
            errorMessage = expansion.containsDirectory
                ? "No PNG files were found in that folder."
                : "PNGSmith only accepts PNG files."
            return false
        }
        errorMessage = expansion.rejectedCount == 0 ? nil : "Some items did not contain PNG files."
        let defaults = defaultOptimizationSettings
        var addedAny = false
        var addedURLs: [URL] = []
        var firstAddedURL: URL?
        for url in pngs {
            if items.contains(where: { $0.url == url }) {
                if pngs.count == 1 { selectedURL = url }
                continue
            }
            let scoped = url.startAccessingSecurityScopedResource()
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let bytes = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
            let properties = Self.imageProperties(at: url)
            items.append(WorkItem(
                url: url,
                securityScoped: scoped,
                originalBytes: bytes,
                pixelWidth: properties.width,
                pixelHeight: properties.height,
                frameCount: properties.frameCount
            ))
            imageOptimizations[url] = rememberedOptimization(for: url) ?? defaults
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            addedAny = true
            addedURLs.append(url)
            firstAddedURL = firstAddedURL ?? url
        }
        if let firstAddedURL {
            selectedURL = firstAddedURL
        } else if selectedURL == nil {
            selectedURL = items.first?.url
        }
        if items.count > 1 { saveAsSelected = false }
        if expansion.containsDirectory {
            workspaceMode = .batch
        }
        if addedAny {
            rememberOpenSession()
            refreshPreviews(for: addedURLs)
        }
        return addedAny
    }

    func remove(_ url: URL) {
        let nextSelection = DocumentTabNavigation.selection(
            afterRemoving: url,
            from: items.map(\.url),
            selected: selectedURL
        )
        if cropToolState.itemURL == url {
            cropToolState.close()
        }
        if let item = items.first(where: { $0.url == url }), item.securityScoped {
            url.stopAccessingSecurityScopedResource()
        }
        items.removeAll { $0.url == url }
        previews[url] = nil
        automaticColorBudgets[url] = nil
        cropSelections[url] = nil
        imageOptimizations[url] = nil
        if selectedURL == url { selectedURL = nextSelection }
        if items.count < 2 { workspaceMode = .image }
        if items.isEmpty {
            forgetOpenSession()
        } else {
            rememberOpenSession()
        }
        Task { await PreviewEngine.shared.forget(source: url) }
    }

    func selectImage(offset: Int) {
        selectedURL = DocumentTabNavigation.selection(
            offset: offset,
            from: items.map(\.url),
            selected: selectedURL
        )
    }

    func removeSelectedImage() {
        guard let selectedURL else { return }
        remove(selectedURL)
    }

    func presentReplacementPicker(for item: WorkItem) {
        replacementTargetURL = item.url
        isReplacementImporterPresented = true
    }

    func replaceImage(at currentURL: URL, with replacementURL: URL) {
        let replacementURL = replacementURL.standardizedFileURL
        guard replacementURL.pathExtension.caseInsensitiveCompare("png") == .orderedSame else {
            errorMessage = "PNGSmith only accepts PNG files."
            return
        }
        guard let index = items.firstIndex(where: { $0.url == currentURL }) else { return }
        guard replacementURL != currentURL.standardizedFileURL else { return }
        guard !items.contains(where: { $0.url.standardizedFileURL == replacementURL }) else {
            errorMessage = "That PNG is already open."
            return
        }

        let previousItem = items[index]
        let scoped = replacementURL.startAccessingSecurityScopedResource()
        let attributes = try? FileManager.default.attributesOfItem(atPath: replacementURL.path)
        let bytes = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        let properties = Self.imageProperties(at: replacementURL)
        let previousOptimization = imageOptimizations[currentURL] ?? defaultOptimizationSettings

        if cropToolState.itemURL == currentURL {
            cropToolState.close()
        }
        if previousItem.securityScoped {
            currentURL.stopAccessingSecurityScopedResource()
        }

        items[index] = WorkItem(
            url: replacementURL,
            securityScoped: scoped,
            originalBytes: bytes,
            pixelWidth: properties.width,
            pixelHeight: properties.height,
            frameCount: properties.frameCount
        )
        previews[currentURL] = nil
        automaticColorBudgets[currentURL] = nil
        cropSelections[currentURL] = nil
        imageOptimizations[currentURL] = nil
        imageOptimizations[replacementURL] = previousOptimization
        selectedURL = replacementURL
        workspaceMode = .image
        hoveredReplaceURL = nil
        saveSummary = nil
        errorMessage = nil

        NSDocumentController.shared.noteNewRecentDocumentURL(replacementURL)
        rememberImageOptimizations()
        rememberOpenSession()
        refreshPreviews(for: [replacementURL])
        Task { await PreviewEngine.shared.forget(source: currentURL) }
    }

    func moveImageTab(_ movingURL: URL, to targetURL: URL) {
        guard movingURL != targetURL,
              let movingItem = items.first(where: { $0.url == movingURL }),
              let targetItem = items.first(where: { $0.url == targetURL })
        else { return }

        items = DocumentTabNavigation.reordered(items, moving: movingItem, to: targetItem)
        rememberOpenSession()
    }

    func clear() {
        for item in items where item.securityScoped {
            item.url.stopAccessingSecurityScopedResource()
        }
        let urls = items.map(\.url)
        items.removeAll()
        previews.removeAll()
        automaticColorBudgets.removeAll()
        cropSelections.removeAll()
        imageOptimizations.removeAll()
        for directory in scopedDirectoryURLs {
            directory.stopAccessingSecurityScopedResource()
        }
        scopedDirectoryURLs.removeAll()
        workspaceMode = .image
        cropToolState.close()
        selectedURL = nil
        saveAsSelected = false
        saveSummary = nil
        errorMessage = nil
        generation += 1
        forgetOpenSession()
        Task {
            for url in urls { await PreviewEngine.shared.forget(source: url) }
        }
    }

    // MARK: - Open session

    static let lastImageBookmarkKey = "last-image-bookmark-v1"
    static let openImageBookmarksKey = "open-image-bookmarks-v1"
    static let selectedOpenImagePathKey = "selected-open-image-path-v1"
    static let imageOptimizationsKey = "image-optimizations-v1"

    var appDefaults: UserDefaults {
        UserDefaults(suiteName: PNGSmithSettingsStore.appGroup) ?? .standard
    }

    func rememberedOptimization(for url: URL) -> ImageOptimizationSettings? {
        guard let data = appDefaults.data(forKey: Self.imageOptimizationsKey),
              let values = try? JSONDecoder().decode([String: ImageOptimizationSettings].self, from: data)
        else { return nil }
        return values[url.standardizedFileURL.path]
    }

    func rememberImageOptimizations() {
        var values: [String: ImageOptimizationSettings] = [:]
        if let data = appDefaults.data(forKey: Self.imageOptimizationsKey),
           let existing = try? JSONDecoder().decode([String: ImageOptimizationSettings].self, from: data) {
            values = existing
        }
        for (url, optimization) in imageOptimizations {
            values[url.standardizedFileURL.path] = optimization
        }
        if let data = try? JSONEncoder().encode(values) {
            appDefaults.set(data, forKey: Self.imageOptimizationsKey)
        }
    }

    func rememberOpenSession() {
        guard !items.isEmpty else {
            forgetOpenSession()
            return
        }
        let bookmarks = items.compactMap { item in
            try? item.url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        appDefaults.set(bookmarks, forKey: Self.openImageBookmarksKey)
        appDefaults.set(selectedURL?.path, forKey: Self.selectedOpenImagePathKey)
        appDefaults.removeObject(forKey: Self.lastImageBookmarkKey)
    }

    func restoreOpenSession() {
        guard items.isEmpty else { return }
        var bookmarks = appDefaults.array(forKey: Self.openImageBookmarksKey) as? [Data] ?? []
        if bookmarks.isEmpty, let legacy = appDefaults.data(forKey: Self.lastImageBookmarkKey) {
            bookmarks = [legacy]
        }

        var restoredURLs: [URL] = []
        var containsStaleBookmark = false
        for bookmark in bookmarks {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ),
                  FileManager.default.fileExists(atPath: url.path),
                  url.pathExtension.caseInsensitiveCompare("png") == .orderedSame,
                  !restoredURLs.contains(url)
            else { continue }
            restoredURLs.append(url)
            containsStaleBookmark = containsStaleBookmark || isStale
        }

        guard !restoredURLs.isEmpty else {
            forgetOpenSession()
            return
        }

        let selectedPath = appDefaults.string(forKey: Self.selectedOpenImagePathKey)
        add(restoredURLs)
        if let selectedPath,
           let restoredSelection = restoredURLs.first(where: { $0.path == selectedPath }) {
            selectedURL = restoredSelection
        }
        if containsStaleBookmark { rememberOpenSession() }
    }

    func forgetOpenSession() {
        appDefaults.removeObject(forKey: Self.lastImageBookmarkKey)
        appDefaults.removeObject(forKey: Self.openImageBookmarksKey)
        appDefaults.removeObject(forKey: Self.selectedOpenImagePathKey)
    }

    // MARK: - Saving

    func save() {
        guard !isSaving, activePreviewStatus.canSave else { return }
        if saveDestination == .saveAs {
            saveAs()
            return
        }
        if saveDestination == .replace && replacementRisk != .none {
            showReplaceLossyConfirm = true
            return
        }
        performSave()
    }

    var replaceConfirmationTitle: String {
        switch replacementRisk {
        case .cropAndColorReduction: "Replace originals with these edits?"
        case .crop: "Replace originals with cropped images?"
        case .colorReduction: "Replace originals with fewer colors?"
        case .none: "Replace originals?"
        }
    }

    var replaceConfirmationMessage: String {
        switch replacementRisk {
        case .cropAndColorReduction:
            "Cropping removes pixels outside the frame, and reducing colors may change the retained pixels. Saving copies is the safer choice."
        case .crop:
            "Cropping permanently removes pixels outside the selected frame. Saving copies is the safer choice."
        case .colorReduction:
            "Reducing colors may change pixels permanently. Saving copies is the safer choice."
        case .none:
            "The selected files will be changed in place."
        }
    }

    func saveAs() {
        guard !isSaving, activeSaveItems.count == 1, let item = activeSaveItems.first else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = item.url.deletingLastPathComponent()
        panel.nameFieldStringValue = item.url.deletingPathExtension().lastPathComponent
            + store.settings.suffix
            + ".png"

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let destination = panel.url else { return }
            performSaveAs(item: item, destination: destination)
        }

        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    func performSaveAs(item: WorkItem, destination: URL) {
        saveConfirmationTask?.cancel()
        isSaving = true
        saveSummary = nil
        errorMessage = nil
        let variant = currentVariant
        Task.detached(priority: .userInitiated) {
            do {
                let outcome = try await PreviewEngine.shared.preview(source: item.url, variant: variant)
                try DashboardSavePipeline.writePreview(from: outcome.outputURL, to: destination)
                let result = PNGSmithResult(
                    input: item.url.path,
                    output: destination.path,
                    originalBytes: outcome.originalBytes,
                    outputBytes: outcome.outputBytes,
                    actualMode: outcome.actualMode,
                    paletteEntries: outcome.paletteEntries,
                    colorBudget: outcome.colorBudget,
                    sourceColors: outcome.sourceColors,
                    sourceColorsAtLeast: outcome.sourceColorsAtLeast,
                    pixelIdentical: !outcome.lossy,
                    lossy: outcome.lossy,
                    written: true,
                    skippedReason: nil,
                    error: nil
                )
                let summary = SaveSummary(results: [result])
                await MainActor.run {
                    isSaving = false
                    saveSummary = summary
                    scheduleSaveConfirmationReset()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func performSave() {
        saveConfirmationTask?.cancel()
        isSaving = true
        saveSummary = nil
        errorMessage = nil
        let snapshot = activeSaveItems
        let settings = store.settings
        let defaults = defaultOptimizationSettings
        let optimizations = imageOptimizations
        let crops = cropSelections
        let paletteProtection = protectExistingPalette
        Task.detached(priority: .medium) {
            var results: [PNGSmithResult] = []
            for item in snapshot {
                do {
                    let optimization = optimizations[item.url] ?? defaults
                    let itemMode = item.supportedMode(requested: optimization.mode)
                    let crop = crops[item.url]?.pixelOptions(
                        imageWidth: item.pixelWidth,
                        imageHeight: item.pixelHeight
                    )
                    let usesAutomaticPalette = optimization.autoColors && itemMode == .shrink
                    let variant = PreviewVariant(
                        mode: itemMode,
                        maxColors: optimization.maxColors,
                        settings: settings,
                        automaticStrategy: usesAutomaticPalette ? optimization.autoStrategy.rawValue : nil,
                        protectExistingPalette: paletteProtection,
                        crop: crop
                    )
                    let request = try await DashboardSavePipeline.request(
                        item: item,
                        mode: itemMode,
                        variant: variant,
                        settings: settings
                    )
                    let response = try PNGSmithCore.execute(request)
                    results.append(contentsOf: response.results)
                } catch {
                    results.append(DashboardSavePipeline.failure(for: item, error: error))
                }
            }
            let summary = SaveSummary(results: results)
            let firstError = results.compactMap(\.error).first
            await MainActor.run {
                isSaving = false
                saveSummary = summary
                if summary.totalCount > 0 {
                    scheduleSaveConfirmationReset()
                }
                if let firstError {
                    errorMessage = summary.failedCount > 1
                        ? "\(summary.failedCount) files failed. First error: \(firstError)"
                        : firstError
                }
                if !settings.createCopy && summary.writtenCount > 0 {
                    reloadReplacedItems()
                }
            }
        }
    }

    func scheduleSaveConfirmationReset() {
        saveConfirmationTask?.cancel()
        saveConfirmationTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                saveSummary = nil
            }
        }
    }

    func reloadReplacedItems() {
        let urls = items.map(\.url)
        generation += 1
        previews.removeAll()
        cropSelections.removeAll()
        items = items.map { item in
            let attributes = try? FileManager.default.attributesOfItem(atPath: item.url.path)
            let bytes = (attributes?[.size] as? NSNumber)?.uint64Value ?? item.originalBytes
            let properties = Self.imageProperties(at: item.url)
            return WorkItem(
                url: item.url,
                securityScoped: item.securityScoped,
                originalBytes: bytes,
                pixelWidth: properties.width,
                pixelHeight: properties.height,
                frameCount: properties.frameCount
            )
        }
        Task {
            for url in urls { await PreviewEngine.shared.forget(source: url) }
            await MainActor.run { refreshPreviews() }
        }
    }

    // MARK: - Helpers

    func applyCrop(_ crop: CanvasEdit, to item: WorkItem) {
        if crop.isIdentity {
            cropSelections[item.url] = nil
        } else {
            cropSelections[item.url] = crop
        }
        automaticColorBudgets[item.url] = nil
        saveSummary = nil
        refreshPreviews()
    }

    func resetCrop(for item: WorkItem) {
        cropSelections[item.url] = nil
        automaticColorBudgets[item.url] = nil
        saveSummary = nil
        refreshPreviews()
    }

    nonisolated static func imageProperties(at url: URL) -> (width: Int, height: Int, frameCount: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else { return (1, 1, 1) }
        return (
            max(width.intValue, 1),
            max(height.intValue, 1),
            max(CGImageSourceGetCount(source), 1)
        )
    }

    func percentText(_ outcome: PreviewOutcome) -> String {
        let percent = Int((outcome.savedFraction * 100).rounded())
        return percent > 0 ? "−\(percent)%" : "±0%"
    }

    static func byteText(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    func errorPanel(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(.orange.opacity(0.22))
        }
    }
}
