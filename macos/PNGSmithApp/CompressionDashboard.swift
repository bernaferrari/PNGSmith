import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct CompressionDashboard: View {
    @EnvironmentObject var store: PNGSmithSettingsStore
    @EnvironmentObject var openFiles: OpenFileRouter

    @State var items: [WorkItem] = []
    @State var selectedURL: URL?
    @AppStorage(
        PNGSmithSettingsStore.reduceColorsKey,
        store: UserDefaults(suiteName: PNGSmithSettingsStore.appGroup) ?? .standard
    ) var reduceColorsEnabled = true
    @AppStorage(
        PNGSmithSettingsStore.maxColorsKey,
        store: UserDefaults(suiteName: PNGSmithSettingsStore.appGroup) ?? .standard
    ) var maxColorCount = 256
    @AppStorage(
        PNGSmithSettingsStore.autoColorsKey,
        store: UserDefaults(suiteName: PNGSmithSettingsStore.appGroup) ?? .standard
    ) var autoColorsEnabled = true
    @AppStorage(
        PNGSmithSettingsStore.autoStrategyKey,
        store: UserDefaults(suiteName: PNGSmithSettingsStore.appGroup) ?? .standard
    ) var autoColorStrategyRawValue = AutoColorStrategy.balanced.rawValue
    @State var colorInput = "256"
    @State var showColorEditor = false
    @State var batchColorInput = "256"
    @State var showBatchColorEditor = false
    @State var previews: [URL: PreviewPhase] = [:]
    @State var automaticColorBudgets: [URL: Int] = [:]
    @State var generation = 0
    @State var sliderDebounce: Task<Void, Never>?
    @State var isImporterPresented = false
    @State var isReplacementImporterPresented = false
    @State var replacementTargetURL: URL?
    @State var isDropTargeted = false
    @State var isSaving = false
    @State var saveSummary: SaveSummary?
    @State var saveConfirmationTask: Task<Void, Never>?
    @AppStorage(
        PNGSmithSettingsStore.saveAsSelectedKey,
        store: UserDefaults(suiteName: PNGSmithSettingsStore.appGroup) ?? .standard
    ) var saveAsSelected = false
    @State var errorMessage: String?
    @State var showReplaceLossyConfirm = false
    @State var dividerPosition: CGFloat = 0.5
    @State var showingOriginal = false
    @State var didRestoreOpenSession = false
    @State var hoveredRemoveURL: URL?
    @State var hoveredReplaceURL: URL?
    @State var hoveredTabURL: URL?
    @State var hoveredTabCloseURL: URL?
    @State var draggingTabURL: URL?
    @State var tabDropTargetURL: URL?
    @State var tabDropIndicatorOnTrailingEdge = false
    @State var cropSelections: [URL: CanvasEdit] = [:]
    @State var imageOptimizations: [URL: ImageOptimizationSettings] = [:]
    @State var workspaceMode: DashboardWorkspaceMode = .image
    @State var scopedDirectoryURLs: Set<URL> = []
    @AppStorage("comparison-layout-v2") var comparisonLayoutRawValue = ComparisonLayout.hold.rawValue
    @State var cropToolState = CropToolState.inactive
    @FocusState var colorInputFocused: Bool
    @FocusState var batchColorInputFocused: Bool
    @Environment(\.openSettings) var openSettings
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            content
            if let errorMessage {
                errorPanel(errorMessage)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
            }
        }
        .navigationTitle("PNGSmith")
        .toolbar { toolbarContent }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 900, minHeight: 640)
        .focusedSceneValue(
            \.pngsmithDocumentActions,
            PNGSmithDocumentActions(
                canCycle: items.count > 1 && !cropToolState.isActive,
                canClose: selectedItem != nil && !cropToolState.isActive,
                selectPrevious: { selectImage(offset: -1) },
                selectNext: { selectImage(offset: 1) },
                closeSelected: { removeSelectedImage() }
            )
        )
        .task {
            guard !didRestoreOpenSession else { return }
            didRestoreOpenSession = true
            colorInput = String(maxColorCount)
            let pendingURLs = openFiles.takePendingURLs()
            if pendingURLs.isEmpty {
                restoreOpenSession()
            } else {
                add(pendingURLs)
            }
        }
        .onChange(of: openFiles.revision) { _, _ in
            let pendingURLs = openFiles.takePendingURLs()
            if !pendingURLs.isEmpty { add(pendingURLs) }
        }
        .onChange(of: selectedURL) { _, newURL in
            dividerPosition = 0.5
            showingOriginal = false
            showColorEditor = false
            if let newURL,
               let item = items.first(where: { $0.url == newURL }) {
                colorInput = String(optimization(for: item).maxColors)
                rememberOpenSession()
            } else if items.isEmpty {
                forgetOpenSession()
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.png, .folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { add(urls) }
        }
        .fileImporter(
            isPresented: $isReplacementImporterPresented,
            allowedContentTypes: [.png],
            allowsMultipleSelection: false
        ) { result in
            defer { replacementTargetURL = nil }
            switch result {
            case .success(let urls):
                guard let replacementTargetURL, let replacementURL = urls.first else { return }
                replaceImage(at: replacementTargetURL, with: replacementURL)
            case .failure(let error):
                let cocoaError = error as NSError
                if cocoaError.code != NSUserCancelledError {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            add(urls)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .onOpenURL { url in
            add([url])
        }
        .confirmationDialog(
            replaceConfirmationTitle,
            isPresented: $showReplaceLossyConfirm
        ) {
            Button("Replace Originals", role: .destructive) { performSave() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(replaceConfirmationMessage)
        }
        .onChange(of: store.settings) { oldValue, newValue in
            saveSummary = nil
            let before = PreviewVariant(mode: mode, maxColors: Int(maxColors), settings: oldValue)
            let after = PreviewVariant(mode: mode, maxColors: Int(maxColors), settings: newValue)
            if before != after { refreshPreviews() }
        }
    }

}

extension CompressionDashboard {
    // MARK: - Document Tabs

    var documentTabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    batchOverviewTab

                    ForEach(items) { item in
                        documentTab(item)
                            .id(item.url)
                    }

                    Button {
                        isImporterPresented = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .foregroundStyle(.secondary)
                    .background(Color.primary.opacity(0.055), in: Circle())
                    .help("Add PNGs")
                    .accessibilityLabel("Add PNGs")
                    .padding(.leading, 2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .onChange(of: selectedURL) { _, url in
                guard let url else { return }
                proxy.scrollTo(url, anchor: .center)
            }
        }
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    var batchOverviewTab: some View {
        let selected = workspaceMode == .batch
        return Button {
            withAnimation(workspaceTransitionAnimation) {
                workspaceMode = .batch
                saveAsSelected = false
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "rectangle.grid.2x2")
                Text("All Images")
                Text("\(items.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))
            .frame(width: 120, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .foregroundStyle(selected ? Color.primary : Color.secondary)
        .background(
            selected ? Color.primary.opacity(0.09) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    func documentTab(_ item: WorkItem) -> some View {
        let phase = previews[item.url]
        let selected = workspaceMode == .image && item.url == selectedItem?.url
        let hovered = hoveredTabURL == item.url
        return HStack(spacing: 4) {
            Button {
                withAnimation(workspaceTransitionAnimation) {
                    selectedURL = item.url
                    workspaceMode = .image
                }
            } label: {
                HStack(spacing: 8) {
                    WorkspaceThumbnailImage(url: item.url)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08))
                        }

                    Text(item.url.lastPathComponent)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(selected ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    tabStatus(phase)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()

            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                    remove(item.url)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .foregroundStyle(.secondary)
            .background(
                hoveredTabCloseURL == item.url ? Color.primary.opacity(0.09) : Color.clear,
                in: Circle()
            )
            .opacity(selected || hovered ? 1 : 0)
            .allowsHitTesting(selected || hovered)
            .onHover { hovering in
                hoveredTabCloseURL = hovering ? item.url : nil
            }
            .help("Close \(item.url.lastPathComponent)")
            .accessibilityLabel("Close \(item.url.lastPathComponent)")
        }
        .frame(width: 190, height: 36)
        .padding(.horizontal, 6)
        .background(
            selected
                ? Color.primary.opacity(0.09)
                : hovered ? Color.primary.opacity(0.045) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay(alignment: tabDropIndicatorOnTrailingEdge ? .trailing : .leading) {
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 3, height: 28)
                .shadow(color: Color.accentColor.opacity(0.55), radius: 3)
                .opacity(tabDropTargetURL == item.url ? 1 : 0)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.1)) {
                hoveredTabURL = hovering ? item.url : nil
            }
            if !hovering, hoveredTabCloseURL == item.url {
                hoveredTabCloseURL = nil
            }
        }
        .draggable(item.url) {
            Label(item.url.lastPathComponent, systemImage: "photo")
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .onAppear {
                    draggingTabURL = item.url
                }
                .onDisappear {
                    if draggingTabURL == item.url {
                        draggingTabURL = nil
                    }
                }
        }
        .dropDestination(for: URL.self) { urls, _ in
            if let movingURL = urls.first,
               items.contains(where: { $0.url == movingURL }) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                    moveImageTab(movingURL, to: item.url)
                }
                draggingTabURL = nil
                tabDropTargetURL = nil
                return true
            }
            let added = add(urls)
            draggingTabURL = nil
            tabDropTargetURL = nil
            return added
        } isTargeted: { targeted in
            if targeted {
                tabDropTargetURL = item.url
                if let draggingTabURL,
                   let sourceIndex = items.firstIndex(where: { $0.url == draggingTabURL }),
                   let targetIndex = items.firstIndex(where: { $0.url == item.url }) {
                    tabDropIndicatorOnTrailingEdge = sourceIndex < targetIndex
                } else {
                    tabDropIndicatorOnTrailingEdge = false
                }
            } else if tabDropTargetURL == item.url {
                tabDropTargetURL = nil
            }
        }
        .accessibilityLabel(item.url.lastPathComponent)
        .accessibilityValue(selected ? "Selected" : tabAccessibilityStatus(phase))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu {
            Button("Close") { remove(item.url) }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
    }

    func tabAccessibilityStatus(_ phase: PreviewPhase?) -> String {
        switch phase {
        case .ready(let outcome): percentText(outcome)
        case .failed: "Preview failed"
        case .loading(let previous):
            previous.map { "Updating preview, \(percentText($0))" } ?? "Calculating preview"
        case nil: "Calculating preview"
        }
    }

    @ViewBuilder
    func tabStatus(_ phase: PreviewPhase?) -> some View {
        switch phase {
        case .ready(let outcome):
            Text(percentText(outcome))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(outcome.savedBytes > 0 ? Color.green : Color.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
        case .loading(let previous):
            if let previous {
                Text(percentText(previous))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(previous.savedBytes > 0 ? Color.green : Color.secondary)
            } else {
                ProgressView().controlSize(.mini)
            }
        case nil:
            ProgressView().controlSize(.mini)
        }
    }


    // MARK: - Comparison

    var comparison: some View {
        let item = selectedItem
        let phase = item.flatMap { previews[$0.url] }
        // Keep the last exact preview on screen while its replacement is
        // calculated. Dropping it here briefly exposed Before and removed the
        // comparison controls whenever a compression preset changed.
        let outcome = phase?.lastKnownOutcome
        return unifiedComparisonCanvas(item: item, phase: phase, outcome: outcome)
            .animation(comparisonTransitionAnimation, value: comparisonLayout)
    }

    func unifiedComparisonCanvas(
        item: WorkItem?,
        phase: PreviewPhase?,
        outcome: PreviewOutcome?
    ) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let isPaired = comparisonLayout == .sideBySide || comparisonLayout == .stacked
            let panels: (before: CGRect, after: CGRect) = {
                switch comparisonLayout {
                case .hold, .divider:
                    let full = CGRect(origin: .zero, size: proxy.size)
                    return (full, full)
                case .sideBySide:
                    let panelWidth = max(0, width / 2)
                    return (
                        CGRect(x: 0, y: 0, width: panelWidth, height: height),
                        CGRect(
                            x: panelWidth,
                            y: 0,
                            width: max(0, width - panelWidth),
                            height: height
                        )
                    )
                case .stacked:
                    let panelHeight = max(0, height / 2)
                    return (
                        CGRect(x: 0, y: 0, width: width, height: panelHeight),
                        CGRect(
                            x: 0,
                            y: panelHeight,
                            width: width,
                            height: max(0, height - panelHeight)
                        )
                    )
                }
            }()
            let sourceSize = item.map { item in
                if let crop = cropSelections[item.url] {
                    let output = crop.pixelOptions(
                        imageWidth: item.pixelWidth,
                        imageHeight: item.pixelHeight
                    )
                    return CGSize(width: output.width, height: output.height)
                }
                return CGSize(width: item.pixelWidth, height: item.pixelHeight)
            } ?? .zero
            let imageFrame: (CGRect) -> CGRect = { panel in
                CropGeometry.imageRect(
                    source: sourceSize,
                    available: panel.size,
                    allowsOutsideImage: false,
                    // Split panels already have a separator. Even the former
                    // fractional margin rounded to a visible one-pixel seam
                    // between the image surface and that separator.
                    marginScale: 0
                )
                .offsetBy(dx: panel.minX, dy: panel.minY)
            }
            let beforeImageFrame = imageFrame(panels.before)
            let afterImageFrame = imageFrame(panels.after)
            let beforeVisible = comparisonLayout != .hold || showingOriginal || outcome == nil
            let beforeLabelVisible = comparisonLayout == .divider
                || isPaired
                || (comparisonLayout == .hold && (showingOriginal || outcome == nil))
            let afterLabelVisible = outcome != nil
                && (comparisonLayout != .hold || !showingOriginal)

            ZStack {
                Color(nsColor: .underPageBackgroundColor)

                if item != nil {
                    WorkspaceImageBackdrop(frame: afterImageFrame)
                        .opacity(outcome == nil ? 0 : 1)
                    WorkspaceImageBackdrop(frame: beforeImageFrame)
                        .opacity(isPaired || outcome == nil ? 1 : 0)
                }

                if let outputURL = outcome?.outputURL {
                    WorkspaceFileImage(url: outputURL, frame: afterImageFrame)
                }

                if let item {
                    WorkspaceFileImage(
                        url: outcome?.comparisonSourceURL ?? item.url,
                        frame: beforeImageFrame
                    )
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(
                                width: comparisonLayout == .divider
                                    ? width * dividerPosition
                                    : width,
                                height: height
                            )
                    }
                    .opacity(beforeVisible ? 1 : 0)
                }

                // The separator belongs to the destination layout, not to the
                // shared image motion. Keeping it alive prevents SwiftUI from
                // morphing a newly inserted rectangle through the center.
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.72))
                    .frame(
                        width: comparisonLayout == .sideBySide ? 1 : width,
                        height: comparisonLayout == .stacked ? 1 : height
                    )
                    .position(x: width / 2, y: height / 2)
                    .opacity(isPaired ? 1 : 0)
                    .allowsHitTesting(false)
                    .transaction { transaction in
                        transaction.animation = nil
                    }

                if let item {
                    VStack {
                        HStack {
                            overlayChip(
                                cropSelections[item.url] == nil
                                    ? "Before · \(Self.byteText(item.originalBytes))"
                                    : "Before"
                            )
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(12)
                    .frame(width: panels.before.width, height: panels.before.height)
                    .position(x: panels.before.midX, y: panels.before.midY)
                    .opacity(beforeLabelVisible ? 1 : 0)
                    .allowsHitTesting(false)
                }

                if let outcome {
                    VStack {
                        HStack {
                            Spacer()
                            overlayChip(
                                "After · \(Self.byteText(outcome.outputBytes)) (\(percentText(outcome)))",
                                tint: outcome.savedBytes > 0 ? .green : .secondary
                            )
                        }
                        Spacer()
                    }
                    .padding(12)
                    .frame(width: panels.after.width, height: panels.after.height)
                    .position(x: panels.after.midX, y: panels.after.midY)
                    .opacity(afterLabelVisible ? 1 : 0)
                    .allowsHitTesting(false)
                }

                if comparisonLayout == .divider, outcome != nil, !showingOriginal {
                    dividerControl(width: width, height: height)
                        .opacity(cropChromeActive ? 0 : 1)
                        .scaleEffect(cropChromeActive ? 0.96 : 1)
                        .animation(toolChromeAnimation, value: cropChromeActive)
                        .transition(.opacity)
                }

                if comparisonLayout == .hold, outcome != nil {
                    VStack {
                        Spacer()
                        holdToCompareButton
                    }
                    .padding(.bottom, 12)
                    .opacity(cropChromeActive ? 0 : 1)
                    .offset(y: cropChromeActive ? 32 : 0)
                    .scaleEffect(cropChromeActive ? 0.92 : 1, anchor: .bottom)
                    .animation(toolChromeAnimation, value: cropChromeActive)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if phase?.isInitialLoading == true {
                    VStack {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text("Optimizing preview…")
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
                        Spacer()
                    }
                    .padding(.top, 12)
                    .allowsHitTesting(false)
                }

                if let failure = phase?.failureMessage {
                    VStack(spacing: 9) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Preview unavailable")
                            .font(.caption.weight(.medium))
                        Button("Try Again") { refreshPreviews() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .position(x: panels.after.midX, y: panels.after.midY)
                    .help(failure)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("comparison"))
                    .onChanged { value in
                        guard outcome != nil else { return }
                        switch comparisonLayout {
                        case .hold:
                            showingOriginal = true
                        case .divider where width > 0:
                            dividerPosition = min(max(value.location.x / width, 0.02), 0.98)
                        case .divider, .sideBySide, .stacked:
                            break
                        }
                    }
                    .onEnded { _ in
                        if comparisonLayout == .hold { showingOriginal = false }
                    }
            )
            .coordinateSpace(name: "comparison")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Before and after image preview")
    }

    var holdToCompareButton: some View {
        Label {
            Text("Hold to Compare")
        } icon: {
            Image(systemName: showingOriginal ? "hand.tap.fill" : "hand.tap")
                .transaction { transaction in
                    transaction.animation = nil
                }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(showingOriginal ? Color.white : Color.accentColor)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background {
            Capsule()
                .fill(.regularMaterial)
                .overlay {
                    Capsule()
                        .fill(Color.accentColor)
                        .opacity(showingOriginal ? 1 : 0.14)
                }
        }
        .shadow(
            color: showingOriginal ? Color.accentColor.opacity(0.28) : Color.black.opacity(0.1),
            radius: showingOriginal ? 8 : 5,
            y: 2
        )
        .scaleEffect(showingOriginal && !reduceMotion ? 0.96 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: showingOriginal)
        .allowsHitTesting(false)
        .help("Press and hold anywhere on the image to compare")
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Hold to compare")
    }

    func overlayChip(_ text: String, tint: Color = .primary) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .contentTransition(.numericText())
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
    }

    func dividerControl(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.92))
                .frame(width: 1.5)
                .shadow(color: .black.opacity(0.35), radius: 2)
            Circle()
                .fill(.white)
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
                .overlay {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.7))
                }
        }
        .frame(width: 44, height: height)
        .position(x: width * dividerPosition, y: height / 2)
        .allowsHitTesting(false)
        .accessibilityLabel("Comparison divider")
        .accessibilityValue("\(Int(dividerPosition * 100)) percent Before")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: dividerPosition = min(dividerPosition + 0.1, 0.98)
            case .decrement: dividerPosition = max(dividerPosition - 0.1, 0.02)
            @unknown default: break
            }
        }
    }

}

struct ComparisonLayoutIcon: View {
    let layout: ComparisonLayout
    let isSelected: Bool

    private var color: Color { isSelected ? .white : .secondary }

    var body: some View {
        switch layout {
        case .hold:
            Image(systemName: "hand.tap")
                .font(.system(size: 13, weight: .medium))
        case .divider:
            ZStack {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(color, style: StrokeStyle(lineWidth: 1.35))
                Rectangle()
                    .fill(color)
                    .frame(width: 1.2)
                Circle()
                    .fill(color)
                    .frame(width: 4.5, height: 4.5)
            }
        case .sideBySide:
            HStack(spacing: 2.5) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(color, style: StrokeStyle(lineWidth: 1.35))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(color, style: StrokeStyle(lineWidth: 1.35))
            }
        case .stacked:
            VStack(spacing: 2.5) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(color, style: StrokeStyle(lineWidth: 1.35))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(color, style: StrokeStyle(lineWidth: 1.35))
            }
        }
    }
}
