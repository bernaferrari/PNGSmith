import AppKit
import SwiftUI

extension CompressionDashboard {
    // MARK: - Toolbar

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                isImporterPresented = true
            } label: {
                Label("Add PNGs", systemImage: "plus")
            }
            .help("Add PNG files (Command-O)")
            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Advanced settings")
        }
    }

    // MARK: - Workspace

    @ViewBuilder
    var content: some View {
        if selectedItem == nil {
            dropPanel
                .padding(18)
                .transition(.opacity)
        } else {
            VStack(spacing: 0) {
                if items.count > 1 {
                    documentTabBar
                        .frame(height: WorkspaceMetrics.documentTabBarHeight)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color(nsColor: .separatorColor))
                                .frame(height: 1)
                                .allowsHitTesting(false)
                        }
                        .opacity(cropToolState.showsChrome ? 0.62 : 1)
                        .allowsHitTesting(!cropToolState.isActive)
                        .animation(toolChromeAnimation, value: cropToolState.showsChrome)
                }

                ZStack {
                    activeWorkspace
                        .allowsHitTesting(!cropToolState.isActive)
                        .accessibilityHidden(cropToolState.isActive)

                    if let cropItem = cropEditorItem {
                        CropEditorWorkspace(
                            item: cropItem,
                            initial: cropSelections[cropItem.url] ?? .full,
                            comparisonDividerPosition: dividerPosition,
                            comparisonDividerVisible: previews[cropItem.url]?.lastKnownOutcome != nil
                                && !showingOriginal
                                && comparisonLayout == .divider,
                            onDismissalStarted: {
                                withAnimation(toolChromeAnimation) {
                                    beginCropEditorDismissal()
                                }
                            },
                            onCancel: { closeCropEditor() },
                            onApply: { crop in
                                applyCrop(crop, to: cropItem)
                                closeCropEditor()
                            }
                        )
                        .id(cropItem.url)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    var activeWorkspace: some View {
        let showsBatch = workspaceMode == .batch && items.count > 1
        return HStack(spacing: 0) {
            ZStack {
                if showsBatch {
                    batchReviewMainArea
                        .transition(workspaceModeTransition)
                } else {
                    mainArea
                        .transition(workspaceModeTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            ZStack {
                if showsBatch {
                    batchReviewSidebar
                        .transition(workspaceModeTransition)
                } else {
                    sidebar
                        .transition(workspaceModeTransition)
                }
            }
            .frame(width: 330)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var batchReviewMainArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Batch Review")
                        .font(.title2.weight(.semibold))
                    Text("Compare every result, then save the set together.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 300, maximum: 430), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(items) { item in
                        batchReviewCard(item)
                    }
                }
            }
            .padding(18)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    var batchReviewSidebar: some View {
        let summary = batchOptimizationSummary
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "rectangle.grid.2x2.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 42, height: 42)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(items.count) Images")
                            .font(.headline)
                        Text(batchStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 14) {
                    ColorReductionSelector(
                        isEnabled: summary.colorReductionEnabled,
                        selectedPreset: summary.preset,
                        status: summary.status,
                        setEnabled: setBatchColorReductionEnabled,
                        select: applyBatchColorReductionPreset
                    )

                    if summary.colorReductionEnabled {
                        batchColorCountControl
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: summary.colorReductionEnabled)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
            sidebarFooter
        }
        .background(WorkspaceSurface.inspector)
        .frame(width: 330)
    }

    var batchStatusText: String {
        let status = previewBatchStatus
        if status.failedCount > 0 {
            return "\(status.failedCount) preview\(status.failedCount == 1 ? "" : "s") need attention"
        }
        if status.pendingCount > 0 {
            return "Preparing \(status.pendingCount) preview\(status.pendingCount == 1 ? "" : "s")…"
        }
        return "All previews are ready"
    }

    var batchOptimizationSummary: OptimizationGroupSummary {
        OptimizationGroupSummary(items.map { optimization(for: $0) })
    }

    var batchColorCountControl: some View {
        let summary = batchOptimizationSummary
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Colors")
                        .font(.subheadline.weight(.medium))
                    Text(summary.preset == .manual
                         ? "Same limit for every image"
                         : "Automatically selected for each image")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button {
                    batchColorInput = String(summary.manualColorCount ?? 256)
                    showBatchColorEditor = true
                } label: {
                    Text(summary.manualColorCount.map(String.init) ?? "Set…")
                        .font(summary.manualColorCount == nil
                              ? .subheadline.weight(.medium)
                              : .system(size: 22, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .frame(minWidth: 66, minHeight: 40)
                        .background(
                            Color.primary.opacity(0.065),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showBatchColorEditor, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Colors for all images")
                            .font(.headline)
                        HStack(spacing: 8) {
                            TextField("2–256", text: $batchColorInput)
                                .textFieldStyle(.roundedBorder)
                                .focused($batchColorInputFocused)
                                .onSubmit(commitBatchColorInput)
                                .frame(width: 90)
                            Button("Apply") { commitBatchColorInput() }
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                    .padding(14)
                    .onAppear { batchColorInputFocused = true }
                }
                .help("Set one maximum color count for every image")
                .accessibilityLabel("Maximum colors for all images")
            }

            if summary.preset == .manual {
                Slider(
                    value: Binding(
                        get: { Double(batchOptimizationSummary.manualColorCount ?? 256) },
                        set: { applyBatchManualColorCount(Int($0.rounded()), debounced: true) }
                    ),
                    in: Double(ImageOptimizationSettings.supportedColorRange.lowerBound)...Double(ImageOptimizationSettings.supportedColorRange.upperBound)
                )
                .accessibilityLabel("Maximum colors for all images")
                .accessibilityValue("\(summary.manualColorCount ?? 256)")
            }
        }
    }

    var batchPaletteProtectionControl: some View {
        let knownOutcomes = items.compactMap { previews[$0.url]?.lastKnownOutcome }
        let protectedCount = knownOutcomes.count {
            ($0.sourceColors ?? 257) <= 256
        }
        let detail = knownOutcomes.count == items.count && protectedCount > 0
            ? "\(protectedCount) of \(items.count) already use 256 colors or fewer."
            : "Keep existing colors when an image uses 256 or fewer."

        return Toggle(isOn: $protectExistingPalette) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(protectExistingPalette ? Color.green : Color.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Protect optimized images")
                        .font(.subheadline.weight(.medium))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.numericText())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .help("Prevent repeated automatic color reduction in folder-wide runs")
    }

    func setBatchColorReductionEnabled(_ isEnabled: Bool) {
        updateOptimizations(for: items) { $0.reduceColors = isEnabled }
    }

    func applyBatchColorReductionPreset(_ preset: ColorReductionPreset) {
        updateOptimizations(for: items) { $0.apply(preset) }
    }

    func commitBatchColorInput() {
        guard let value = Int(batchColorInput.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            batchColorInput = String(batchOptimizationSummary.manualColorCount ?? 256)
            return
        }
        applyBatchManualColorCount(value)
        showBatchColorEditor = false
    }

    func applyBatchManualColorCount(_ count: Int, debounced: Bool = false) {
        let clamped = ImageOptimizationSettings.clampedColorCount(count)
        batchColorInput = String(clamped)
        updateOptimizations(for: items, debounced: debounced) {
            $0.applyManualColorCount(clamped)
        }
    }

    func batchReviewCard(_ item: WorkItem) -> some View {
        let phase = previews[item.url]
        let outcome = phase?.lastKnownOutcome
        let sourceSize = cropSelections[item.url].map {
            let options = $0.pixelOptions(imageWidth: item.pixelWidth, imageHeight: item.pixelHeight)
            return CGSize(width: options.width, height: options.height)
        } ?? CGSize(width: item.pixelWidth, height: item.pixelHeight)

        return Button {
            withAnimation(workspaceTransitionAnimation) {
                selectedURL = item.url
                workspaceMode = .image
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 1) {
                    batchReviewThumbnail(
                        url: outcome?.comparisonSourceURL ?? item.url,
                        sourceSize: sourceSize,
                        title: "Before"
                    )
                    batchReviewThumbnail(
                        url: outcome?.outputURL,
                        sourceSize: sourceSize,
                        title: "After",
                        isLoading: phase?.isInitialLoading == true,
                        failed: phase?.failureMessage != nil
                    )
                }
                .frame(height: 190)
                .background { WorkspaceImageStage() }

                HStack(spacing: 10) {
                    WorkspaceThumbnailImage(url: item.url)
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.url.lastPathComponent)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(batchCardDetail(item: item, phase: phase))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(outcome?.savedBytes ?? 0 > 0 ? Color.green : Color.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(11)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09))
        }
        .contextMenu {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                    remove(item.url)
                }
            } label: {
                Label("Remove", systemImage: "xmark")
            }
        }
        .accessibilityLabel("Review \(item.url.lastPathComponent)")
    }

    func batchReviewThumbnail(
        url: URL?,
        sourceSize: CGSize,
        title: String,
        isLoading: Bool = false,
        failed: Bool = false
    ) -> some View {
        GeometryReader { proxy in
            let frame = CropGeometry.imageRect(
                source: sourceSize,
                available: proxy.size,
                allowsOutsideImage: false,
                marginScale: 0.08
            )
            ZStack {
                if url != nil { WorkspaceImageBackdrop(frame: frame) }
                if let url {
                    WorkspaceFileImage(url: url, frame: frame)
                } else if isLoading {
                    ProgressView().controlSize(.small)
                } else if failed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                VStack {
                    HStack {
                        Text(title)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.regularMaterial, in: Capsule())
                        Spacer()
                    }
                    Spacer()
                }
                .padding(8)
            }
        }
    }

    func batchCardDetail(item: WorkItem, phase: PreviewPhase?) -> String {
        switch phase {
        case .ready(let outcome):
            if outcome.savedBytes == 0 {
                return "\(Self.byteText(outcome.outputBytes)) · Same size"
            }
            return "\(Self.byteText(item.originalBytes)) → \(Self.byteText(outcome.outputBytes)) (\(percentText(outcome)))"
        case .failed:
            return "Preview unavailable"
        case .loading, nil:
            return "Optimizing…"
        }
    }

    func closeCropEditor() {
        cropToolState.close()
    }

    var cropEditorItem: WorkItem? {
        guard let url = cropToolState.itemURL else { return nil }
        return items.first { $0.url == url }
    }

    var cropChromeActive: Bool { cropToolState.showsChrome }

    func presentCropEditor(for item: WorkItem) {
        cropToolState.present(item.url)
    }

    func beginCropEditorDismissal() {
        cropToolState.beginDismissal()
    }

    var mainArea: some View {
        VStack(spacing: 12) {
            if selectedItem != nil {
                comparison
            } else {
                dropPanel
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let item = selectedItem {
                        inspectorFileHeader(item)
                        Divider().padding(.vertical, 16)
                    }
                    modeSection
                    if store.settings.zopfli {
                        Divider().padding(.vertical, 16)
                        fasterSuggestion
                    }
                }
                .padding(18)
            }
            .frame(maxHeight: .infinity)
            .opacity(cropChromeActive ? 0 : 1)
            .offset(x: cropChromeActive ? -14 : 0)
            .scaleEffect(cropChromeActive ? 0.985 : 1, anchor: .trailing)
            .animation(toolChromeAnimation, value: cropChromeActive)

            if selectedItem != nil {
                sidebarFooter
                    .opacity(cropChromeActive ? 0 : 1)
                    .offset(y: cropChromeActive ? 18 : 0)
                    .scaleEffect(cropChromeActive ? 0.98 : 1, anchor: .bottom)
                    .animation(toolChromeAnimation, value: cropChromeActive)
            }
        }
        .background(WorkspaceSurface.inspector)
        .frame(width: 330)
    }

    var dropPanel: some View {
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.14) : Color.accentColor.opacity(0.08))
                    .frame(width: 88, height: 88)
                Image(systemName: isDropTargeted ? "arrow.down" : "photo.on.rectangle.angled")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.bounce, value: isDropTargeted)
            }
            VStack(spacing: 8) {
                Text(isDropTargeted ? "Drop to start" : "Make PNGs lighter")
                    .font(.system(size: 26, weight: .semibold))
                Text("Drop one or more images to preview the exact result\nbefore PNGSmith writes a single byte.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            Button {
                isImporterPresented = true
            } label: {
                Label("Choose PNGs…", systemImage: "plus")
                    .padding(.horizontal, 6)
            }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("o", modifiers: .command)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            isDropTargeted ? Color.accentColor.opacity(0.055) : Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.08),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: isDropTargeted ? [] : [7, 6])
                )
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isDropTargeted)
    }

    func inspectorFileHeader(_ item: WorkItem) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 12) {
                Button {
                    presentReplacementPicker(for: item)
                } label: {
                    WorkspaceThumbnailImage(url: item.url)
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.black.opacity(hoveredReplaceURL == item.url ? 0.24 : 0))

                            Image(systemName: "rectangle.2.swap")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.black.opacity(0.52), in: Circle())
                                .opacity(hoveredReplaceURL == item.url ? 1 : 0)
                                .allowsHitTesting(false)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08))
                        }
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .onHover { hovering in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: hovering ? 0.14 : 0.09)) {
                        hoveredReplaceURL = hovering ? item.url : nil
                    }
                }
                .help("Replace image…")
                .accessibilityLabel("Replace \(item.url.lastPathComponent)")
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.url.lastPathComponent)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Text(inspectorMetadata(for: item))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    remove(item.url)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(
                            hoveredRemoveURL == item.url ? Color.primary.opacity(0.09) : Color.clear,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(hoveredRemoveURL == item.url ? .primary : .secondary)
                .contentShape(Circle())
                .onHover { hovering in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                        hoveredRemoveURL = hovering ? item.url : nil
                    }
                }
                .help("Remove \(item.url.lastPathComponent)")
                .accessibilityLabel("Remove image")
            }

            HStack(spacing: 8) {
                Button {
                    withAnimation(toolChromeAnimation) {
                        presentCropEditor(for: item)
                    }
                } label: {
                    Label("Crop", systemImage: "crop")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(
                            Color.primary.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .disabled(item.isAnimated)
                .help(item.isAnimated
                      ? "Animated PNGs are kept intact and cannot be cropped yet"
                      : "Crop this image before compression")

                if cropSelections[item.url] != nil {
                    Spacer()
                    Button("Reset") {
                        resetCrop(for: item)
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .help("Remove crop")
                } else {
                    Spacer()
                }

                HStack(spacing: 2) {
                    ForEach(ComparisonLayout.allCases) { layout in
                        Button {
                            comparisonLayoutBinding.wrappedValue = layout
                        } label: {
                            ComparisonLayoutIcon(
                                layout: layout,
                                isSelected: comparisonLayout == layout
                            )
                                .frame(width: 19, height: 14)
                                .frame(width: 30, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(comparisonLayout == layout ? Color.white : Color.secondary)
                        .background(
                            comparisonLayout == layout ? Color.accentColor : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                        .help(layout.title)
                        .accessibilityLabel(layout.title)
                        .accessibilityAddTraits(comparisonLayout == layout ? .isSelected : [])
                    }
                }
                .padding(2)
                .background(
                    Color.primary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .help("Choose hold, divider, left-and-right, or top-and-bottom comparison")
            }
        }
    }

    func inspectorMetadata(for item: WorkItem) -> String {
        var components: [String] = []
        if items.count > 1 {
            components.append("\((items.firstIndex(of: item) ?? 0) + 1) of \(items.count)")
        }
        components.append(Self.byteText(item.originalBytes))
        let dimensions = cropSelections[item.url]?.pixelOptions(
            imageWidth: item.pixelWidth,
            imageHeight: item.pixelHeight
        )
        let width = dimensions?.width ?? item.pixelWidth
        let height = dimensions?.height ?? item.pixelHeight
        components.append("\(width) × \(height) (\(roundedAspectRatio(width: width, height: height)))")
        if item.isAnimated {
            components.append("\(item.frameCount) frames")
        }
        return components.joined(separator: " · ")
    }

    func roundedAspectRatio(width: Int, height: Int) -> String {
        guard width > 0, height > 0 else { return "—" }
        let ratio = Double(width) / Double(height)
        let candidates = [
            (1, 1), (5, 4), (4, 3), (3, 2), (16, 10), (16, 9), (2, 1), (21, 10),
            (4, 5), (3, 4), (2, 3), (10, 16), (9, 16), (1, 2), (10, 21)
        ]
        let closest = candidates.min {
            abs(Double($0.0) / Double($0.1) - ratio)
                < abs(Double($1.0) / Double($1.1) - ratio)
        } ?? (1, 1)
        return "\(closest.0):\(closest.1)"
    }

    var selectedItem: WorkItem? {
        items.first { $0.url == selectedURL } ?? items.first
    }

    var defaultOptimizationSettings: ImageOptimizationSettings {
        ImageOptimizationSettings(
            reduceColors: reduceColorsEnabled,
            maxColors: maxColorCount,
            autoColors: autoColorsEnabled,
            autoStrategy: AutoColorStrategy(rawValue: autoColorStrategyRawValue) ?? .balanced
        )
    }

    func optimization(for item: WorkItem) -> ImageOptimizationSettings {
        imageOptimizations[item.url] ?? defaultOptimizationSettings
    }

    var selectedOptimization: ImageOptimizationSettings {
        selectedItem.map { optimization(for: $0) } ?? defaultOptimizationSettings
    }

    var mode: DashboardMode { selectedOptimization.mode }

    var maxColors: Double { Double(selectedOptimization.maxColors) }

    var comparisonLayout: ComparisonLayout {
        ComparisonLayout(rawValue: comparisonLayoutRawValue) ?? .hold
    }

    var comparisonLayoutBinding: Binding<ComparisonLayout> {
        Binding(
            get: { comparisonLayout },
            set: { layout in
                guard layout != comparisonLayout else { return }

                withAnimation(comparisonTransitionAnimation) {
                    showingOriginal = false
                    comparisonLayoutRawValue = layout.rawValue
                }
            }
        )
    }

    var comparisonTransitionAnimation: Animation? {
        reduceMotion
            ? nil
            : .timingCurve(0.77, 0, 0.175, 1, duration: 0.24)
    }

    var workspaceTransitionAnimation: Animation? {
        reduceMotion
            ? nil
            : .easeInOut(duration: 0.18)
    }

    var workspaceModeTransition: AnyTransition {
        reduceMotion
            ? .identity
            : .opacity.combined(with: .scale(scale: 0.99, anchor: .center))
    }

    var previewBatchStatus: PreviewBatchStatus {
        PreviewBatchStatus(states: items.map { item in
            switch previews[item.url] {
            case .ready: .ready
            case .failed: .failed
            case .loading, nil: .pending
            }
        })
    }

    var activeSaveItems: [WorkItem] {
        if workspaceMode == .batch { return items }
        return selectedItem.map { [$0] } ?? []
    }

    var activePreviewStatus: PreviewBatchStatus {
        PreviewBatchStatus(states: activeSaveItems.map { item in
            switch previews[item.url] {
            case .ready: .ready
            case .failed: .failed
            case .loading, nil: .pending
            }
        })
    }

    var activeEstimateAvailable: Bool {
        !activeSaveItems.isEmpty && activeSaveItems.allSatisfy {
            previews[$0.url]?.lastKnownOutcome != nil
        }
    }

    var replacementRisk: ReplacementRisk {
        ReplacementRisk(
            hasCropEdits: activeSaveItems.contains { cropSelections[$0.url] != nil },
            hasLossyPreviews: activeSaveItems.contains { previews[$0.url]?.readyOutcome?.lossy == true }
        )
    }

    var toolChromeAnimation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.08)
    }

}
