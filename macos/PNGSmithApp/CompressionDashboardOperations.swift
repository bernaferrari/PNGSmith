import AppKit
import ImageIO
import SwiftUI

extension CompressionDashboard {
    // MARK: - Preview refresh

    var currentVariant: PreviewVariant {
        guard let item = selectedItem else {
            return PreviewVariant(
                mode: mode,
                maxColors: effectiveColorBudget,
                settings: store.settings
            )
        }
        return previewVariant(
            for: item,
            colorBudget: effectiveColorBudget,
            settings: store.settings,
            useAutomaticColors: item.supportedMode(requested: mode) == .shrink && autoColorsEnabled
        )
    }

    func previewVariant(
        for item: WorkItem,
        colorBudget: Int,
        settings: PNGSmithSettings,
        useAutomaticColors: Bool
    ) -> PreviewVariant {
        let supportedMode = item.supportedMode(requested: mode)
        return PreviewVariant(
            mode: supportedMode,
            maxColors: colorBudget,
            settings: settings,
            automaticStrategy: supportedMode == .shrink && useAutomaticColors
                ? autoColorStrategy.rawValue
                : nil,
            crop: cropOptions(for: item)
        )
    }

    func cropOptions(for item: WorkItem) -> CanvasOptions? {
        cropSelections[item.url]?.pixelOptions(
            imageWidth: item.pixelWidth,
            imageHeight: item.pixelHeight
        )
    }

    func refreshPreviews() {
        guard !items.isEmpty else { return }
        generation += 1
        let currentGeneration = generation
        let useAutomaticColors = mode == .shrink && autoColorsEnabled
        let settings = store.settings
        let uiMode = mode
        let manualColorBudget = maxColorCount
        let automaticStrategy = autoColorStrategy.rawValue
        let crops = cropSelections
        var ordered = items.map(\.url)
        if let selected = selectedItem?.url, let index = ordered.firstIndex(of: selected) {
            ordered.remove(at: index)
            ordered.insert(selected, at: 0)
        }
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
                    let itemMode = item.supportedMode(requested: uiMode)
                    let usesAutomaticPalette = useAutomaticColors && itemMode == .shrink
                    let variant = PreviewVariant(
                        mode: itemMode,
                        maxColors: manualColorBudget,
                        settings: settings,
                        automaticStrategy: usesAutomaticPalette ? automaticStrategy : nil,
                        crop: crop
                    )
                    let outcome = try await PreviewEngine.shared.preview(source: url, variant: variant)
                    guard generation == currentGeneration else { return }
                    guard items.contains(where: { $0.url == url }) else { continue }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        if usesAutomaticPalette, let colorBudget = outcome.colorBudget {
                            automaticColorBudgets[url] = colorBudget
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

    @discardableResult
    func add(_ urls: [URL]) -> Bool {
        let pngs = urls.filter { $0.pathExtension.caseInsensitiveCompare("png") == .orderedSame }
        errorMessage = pngs.count == urls.count ? nil : "PNGSmith only accepts PNG files."
        var addedAny = false
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
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            addedAny = true
            firstAddedURL = firstAddedURL ?? url
        }
        if let firstAddedURL {
            selectedURL = firstAddedURL
        } else if selectedURL == nil {
            selectedURL = items.first?.url
        }
        if items.count > 1 { saveAsSelected = false }
        if addedAny {
            rememberOpenSession()
            refreshPreviews()
        }
        return addedAny
    }

    func remove(_ url: URL) {
        let nextSelection = DocumentTabNavigation.selection(
            afterRemoving: url,
            from: items.map(\.url),
            selected: selectedURL
        )
        if let item = items.first(where: { $0.url == url }), item.securityScoped {
            url.stopAccessingSecurityScopedResource()
        }
        items.removeAll { $0.url == url }
        previews[url] = nil
        automaticColorBudgets[url] = nil
        cropSelections[url] = nil
        if selectedURL == url { selectedURL = nextSelection }
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

    func moveImageTab(_ movingURL: URL, before targetURL: URL) {
        guard movingURL != targetURL,
              let sourceIndex = items.firstIndex(where: { $0.url == movingURL }),
              let targetIndex = items.firstIndex(where: { $0.url == targetURL })
        else { return }

        let item = items.remove(at: sourceIndex)
        let insertionIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        items.insert(item, at: insertionIndex)
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
        cropChromeActive = false
        cropEditorItem = nil
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

    var appDefaults: UserDefaults {
        UserDefaults(suiteName: PNGSmithSettingsStore.appGroup) ?? .standard
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
        guard !isSaving, !items.isEmpty else { return }
        if saveDestination == .saveAs {
            saveAs()
            return
        }
        if saveDestination == .replace && (mode == .shrink || !cropSelections.isEmpty) {
            showReplaceLossyConfirm = true
            return
        }
        performSave()
    }

    var replaceConfirmationTitle: String {
        if !cropSelections.isEmpty && mode == .shrink {
            return "Replace originals with these edits?"
        }
        if !cropSelections.isEmpty {
            return "Replace originals with cropped images?"
        }
        return "Replace originals with fewer colors?"
    }

    var replaceConfirmationMessage: String {
        if !cropSelections.isEmpty && mode == .shrink {
            return "Cropping removes pixels outside the frame, and reducing colors may change the retained pixels. Saving copies is the safer choice."
        }
        if !cropSelections.isEmpty {
            return "Cropping permanently removes pixels outside the selected frame. Saving copies is the safer choice."
        }
        return "Reducing colors may change pixels permanently. Saving copies is the safer choice."
    }

    func saveAs() {
        guard !isSaving, items.count == 1, let item = selectedItem else { return }

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
        let snapshot = items
        let settings = store.settings
        let uiMode = mode
        let useAutomaticColors = uiMode == .shrink && autoColorsEnabled
        let manualColorBudget = maxColorCount
        let automaticStrategy = autoColorStrategy.rawValue
        let crops = cropSelections
        Task.detached(priority: .userInitiated) {
            var results: [PNGSmithResult] = []
            for item in snapshot {
                do {
                    let itemMode = item.supportedMode(requested: uiMode)
                    let crop = crops[item.url]?.pixelOptions(
                        imageWidth: item.pixelWidth,
                        imageHeight: item.pixelHeight
                    )
                    let usesAutomaticPalette = useAutomaticColors && itemMode == .shrink
                    let variant = PreviewVariant(
                        mode: itemMode,
                        maxColors: manualColorBudget,
                        settings: settings,
                        automaticStrategy: usesAutomaticPalette ? automaticStrategy : nil,
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
                if summary.writtenCount > 0 || summary.skippedCount > 0 {
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
