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
                        .opacity(cropChromeActive ? 0.62 : 1)
                        .allowsHitTesting(cropEditorItem == nil)
                        .animation(toolChromeAnimation, value: cropChromeActive)
                }

                ZStack {
                    dashboardWorkspace
                        .allowsHitTesting(cropEditorItem == nil)
                        .accessibilityHidden(cropEditorItem != nil)

                    if let cropItem = cropEditorItem {
                        CropEditorWorkspace(
                            item: cropItem,
                            initial: cropSelections[cropItem.url] ?? .full,
                            onDismissalStarted: {
                                withAnimation(toolChromeAnimation) {
                                    cropChromeActive = false
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

    var dashboardWorkspace: some View {
        HStack(spacing: 0) {
            mainArea
            Divider()
            sidebar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func closeCropEditor() {
        cropChromeActive = false
        cropEditorItem = nil
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
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
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
                WorkspaceThumbnailImage(url: item.url)
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.url.lastPathComponent)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Text(items.count > 1
                         ? "\((items.firstIndex(of: item) ?? 0) + 1) of \(items.count) · \(Self.byteText(item.originalBytes))"
                         : Self.byteText(item.originalBytes))
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
                        cropChromeActive = true
                        cropEditorItem = item
                    }
                } label: {
                    Label("Crop", systemImage: "crop")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(item.isAnimated)
                .help(item.isAnimated
                      ? "Animated PNGs are kept intact and cannot be cropped yet"
                      : "Crop this image before compression")

                if let crop = cropSelections[item.url] {
                    let size = crop.pixelOptions(imageWidth: item.pixelWidth, imageHeight: item.pixelHeight)
                    Text("\(size.width) × \(size.height)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") {
                        resetCrop(for: item)
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .help("Remove crop")
                } else {
                    Text(item.isAnimated
                         ? "\(item.frameCount) frames · \(item.pixelWidth) × \(item.pixelHeight)"
                         : "\(item.pixelWidth) × \(item.pixelHeight)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
        }
    }

    var selectedItem: WorkItem? {
        items.first { $0.url == selectedURL } ?? items.first
    }

    var mode: DashboardMode { reduceColorsEnabled ? .shrink : .auto }

    var maxColors: Double { Double(maxColorCount) }

    var autoColorStrategy: AutoColorStrategy {
        AutoColorStrategy(rawValue: autoColorStrategyRawValue) ?? .balanced
    }

    var autoColorStrategyBinding: Binding<AutoColorStrategy> {
        Binding(
            get: { autoColorStrategy },
            set: { autoColorStrategyRawValue = $0.rawValue }
        )
    }

    var effectiveColorBudget: Int {
        guard autoColorsEnabled, let url = selectedItem?.url else { return maxColorCount }
        return automaticColorBudgets[url] ?? 256
    }

    var documentTabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
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

    func documentTab(_ item: WorkItem) -> some View {
        let phase = previews[item.url]
        let selected = item.url == selectedItem?.url
        let hovered = hoveredTabURL == item.url
        return HStack(spacing: 4) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                    selectedURL = item.url
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
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 2, height: 24)
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
        }
        .dropDestination(for: URL.self) { urls, _ in
            if let movingURL = urls.first,
               items.contains(where: { $0.url == movingURL }) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                    moveImageTab(movingURL, before: item.url)
                }
                tabDropTargetURL = nil
                return true
            }
            let added = add(urls)
            tabDropTargetURL = nil
            return added
        } isTargeted: { targeted in
            tabDropTargetURL = targeted ? item.url : nil
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
        case .loading, nil: "Calculating preview"
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
        case .loading, nil:
            ProgressView().controlSize(.mini)
        }
    }

    // MARK: - Comparison

    var comparison: some View {
        let item = selectedItem
        let phase = item.flatMap { previews[$0.url] }
        let outcome = phase?.lastKnownOutcome
        return comparisonCanvas(item: item, phase: phase, outcome: outcome)
    }

    func comparisonCanvas(item: WorkItem?, phase: PreviewPhase?, outcome: PreviewOutcome?) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
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
            let imageFrame = CropGeometry.imageRect(
                source: sourceSize,
                available: proxy.size,
                allowsOutsideImage: false,
                marginScale: 0
            )
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                if item != nil {
                    WorkspaceImageBackdrop(frame: imageFrame)
                }
                if let outputURL = outcome?.outputURL {
                    comparisonImage(outputURL, frame: imageFrame)
                }
                if let item {
                    comparisonImage(outcome?.comparisonSourceURL ?? item.url, frame: imageFrame)
                        .mask(alignment: .leading) {
                            if outcome != nil {
                                Rectangle().frame(width: showingOriginal ? width : width * dividerPosition)
                            } else {
                                Rectangle()
                            }
                        }
                }
                if outcome != nil && !showingOriginal {
                    dividerControl(width: width, height: height)
                        .opacity(cropChromeActive ? 0 : 1)
                        .scaleEffect(cropChromeActive ? 0.96 : 1)
                        .animation(toolChromeAnimation, value: cropChromeActive)
                }
                comparisonLabels(item: item, phase: phase, outcome: outcome)
                    .opacity(cropChromeActive ? 0 : 1)
                    .offset(y: cropChromeActive ? -14 : 0)
                    .scaleEffect(cropChromeActive ? 0.985 : 1, anchor: .top)
                    .animation(toolChromeAnimation, value: cropChromeActive)
                    .allowsHitTesting(false)
                if outcome != nil {
                    VStack {
                        Spacer()
                        holdToCompareButton
                    }
                    .padding(.bottom, 12)
                    .opacity(cropChromeActive ? 0 : 1)
                    .offset(y: cropChromeActive ? 32 : 0)
                    .scaleEffect(cropChromeActive ? 0.92 : 1, anchor: .bottom)
                    .animation(toolChromeAnimation, value: cropChromeActive)
                }
                if phase?.isLoading == true {
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
                    VStack {
                        Spacer()
                        Label(failure, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .padding(12)
                            .frame(maxWidth: 420, alignment: .leading)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    }
                    .padding(14)
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("comparison"))
                    .onChanged { value in
                        guard outcome != nil, width > 0 else { return }
                        dividerPosition = min(max(value.location.x / width, 0.02), 0.98)
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
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Before and after image preview")
    }

    func comparisonImage(_ url: URL, frame: CGRect) -> some View {
        WorkspaceFileImage(url: url, frame: frame)
    }

    func comparisonLabels(item: WorkItem?, phase: PreviewPhase?, outcome: PreviewOutcome?) -> some View {
        VStack {
            HStack {
                if let item {
                    overlayChip(
                        cropSelections[item.url] == nil
                            ? "Original · \(Self.byteText(item.originalBytes))"
                            : "Cropped original · \(Self.byteText(item.originalBytes))"
                    )
                }
                Spacer()
                if let outcome {
                    overlayChip(
                        "Optimized · \(Self.byteText(outcome.outputBytes)) · \(percentText(outcome))",
                        tint: outcome.savedBytes > 0 ? .green : .secondary
                    )
                }
            }
            Spacer()
        }
        .padding(12)
    }

    var holdToCompareButton: some View {
        Button {} label: {
            Label(
                showingOriginal ? "Original" : "Hold for original",
                systemImage: showingOriginal ? "photo.fill" : "hand.tap"
            )
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
        }
        .buttonStyle(HoldToCompareButtonStyle(isShowingOriginal: $showingOriginal))
        .help("Press and hold to show the original. Drag the divider for a split comparison.")
        .accessibilityLabel("Show original while pressed")
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
        .accessibilityValue("\(Int(dividerPosition * 100)) percent original")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: dividerPosition = min(dividerPosition + 0.1, 0.98)
            case .decrement: dividerPosition = max(dividerPosition - 0.1, 0.02)
            @unknown default: break
            }
        }
    }

    var toolChromeAnimation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.08)
    }

    // MARK: - Savings bar

    var savingsBar: some View {
        let ready = items.compactMap { previews[$0.url]?.readyOutcome }
        let anyLoading = items.contains { previews[$0.url]?.isLoading == true }
        let original = ready.reduce(UInt64(0)) { $0 + $1.originalBytes }
        let output = ready.reduce(UInt64(0)) { $0 + $1.outputBytes }
        let saved = Int64(original) - Int64(output)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(items.count == 1 ? "Estimated result" : "Estimated batch result")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if anyLoading { ProgressView().controlSize(.small) }
            }

            HStack(spacing: 8) {
                if anyLoading {
                    Text(items.count > 1 && !ready.isEmpty
                         ? "Calculating \(ready.count) of \(items.count)…"
                         : "Calculating…")
                        .foregroundStyle(.secondary)
                } else if original > 0 {
                    let percent = Int((Double(saved) / Double(original) * 100).rounded())
                    Text(saved > 0
                         ? "\(Self.byteText(original)) → \(Self.byteText(output)) (−\(percent)%)"
                         : "\(Self.byteText(original)) → \(Self.byteText(output))")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(saved > 0
                         ? "−\(Self.byteText(UInt64(saved)))"
                         : "No smaller result")
                        .foregroundStyle(saved > 0 ? .green : .secondary)
                        .contentTransition(.numericText())
                } else {
                    Text("Preview unavailable")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline.weight(.medium).monospacedDigit())
            .frame(height: 22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: output)
    }

}
