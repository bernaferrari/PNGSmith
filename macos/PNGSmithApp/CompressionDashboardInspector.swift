import SwiftUI

extension CompressionDashboard {
    // MARK: - Mode controls

    var modeSection: some View {
        let optimization = selectedOptimization
        return VStack(alignment: .leading, spacing: 16) {
            if selectedItem?.isAnimated == true {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "play.rectangle.on.rectangle.fill")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Animated PNG")
                            .font(.subheadline.weight(.medium))
                        Text("All frames stay intact with lossless compression.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
            } else {
                ColorReductionSelector(
                    isEnabled: optimization.reduceColors,
                    selectedPreset: selectedColorReductionPreset,
                    status: nil,
                    setEnabled: setSelectedColorReductionEnabled,
                    select: applySelectedColorReductionPreset
                )

                if optimization.reduceColors {
                    shrinkControls
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: optimization.reduceColors)
    }

    var selectedColorReductionPreset: ColorReductionPreset? {
        selectedOptimization.colorReductionPreset
    }

    func setSelectedColorReductionEnabled(_ isEnabled: Bool) {
        guard let item = selectedItem else { return }
        updateOptimizations(for: [item]) { $0.reduceColors = isEnabled }
    }

    func applySelectedColorReductionPreset(_ preset: ColorReductionPreset) {
        guard let item = selectedItem else { return }
        updateOptimizations(for: [item]) { $0.apply(preset) }
    }

    var shrinkControls: some View {
        let optimization = selectedOptimization
        // Preserve the last computed count while a new automatic preset runs;
        // replacing it with a dash makes the control appear to reset.
        let outcome = selectedItem.flatMap { previews[$0.url]?.lastKnownOutcome }
        let automaticCount = selectedItem.flatMap { item in
            automaticColorBudgets[item.url] ?? outcome?.paletteEntries ?? outcome?.sourceColors
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Button {
                    colorInput = String(
                        optimization.autoColors
                            ? automaticCount ?? optimization.maxColors
                            : optimization.maxColors
                    )
                    showColorEditor = true
                } label: {
                    Text(
                        optimization.autoColors
                            ? automaticCount.map(String.init) ?? "—"
                            : String(optimization.maxColors)
                    )
                        .font(.system(size: 28, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .frame(minWidth: 48, minHeight: 44)
                        .background(
                            Color.primary.opacity(0.065),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showColorEditor, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Maximum colors")
                            .font(.headline)
                        HStack(spacing: 8) {
                            TextField("2–256", text: $colorInput)
                                .textFieldStyle(.roundedBorder)
                                .focused($colorInputFocused)
                                .onSubmit(commitColorInput)
                                .frame(width: 90)
                            Button("Apply") { commitColorInput() }
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                    .padding(14)
                    .onAppear { colorInputFocused = true }
                }
                .help("Set a custom color count")
                .accessibilityLabel("Maximum colors. Click to enter a value")
                Text("colors")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if !optimization.autoColors {
                Slider(
                    value: Binding(
                        get: { Double(selectedOptimization.maxColors) },
                        set: { setMaxColors(Int($0.rounded())) }
                    ),
                    in: Double(ImageOptimizationSettings.supportedColorRange.lowerBound)...Double(ImageOptimizationSettings.supportedColorRange.upperBound)
                )
                .accessibilityLabel("Maximum colors")
                .accessibilityValue("\(optimization.maxColors)")
            }

        }
    }

    func setMaxColors(_ count: Int, debounced: Bool = true) {
        guard let item = selectedItem else { return }
        let clamped = ImageOptimizationSettings.clampedColorCount(count)
        colorInput = String(clamped)
        updateOptimizations(for: [item], debounced: debounced) {
            $0.applyManualColorCount(clamped)
        }
    }

    func commitColorInput() {
        guard let value = Int(colorInput.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            colorInput = String(selectedOptimization.maxColors)
            return
        }
        guard let item = selectedItem else { return }
        let clamped = ImageOptimizationSettings.clampedColorCount(value)
        colorInput = String(clamped)
        updateOptimizations(for: [item]) {
            $0.applyManualColorCount(clamped)
        }
        showColorEditor = false
    }

    var fasterSuggestion: some View {
        Button {
            store.settings.oxipngLevel = 4
            store.settings.zopfli = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "hare.fill")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Faster?")
                        .font(.subheadline.weight(.semibold))
                    Text("Use Balanced for most savings without the long wait.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text("Switch")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Switch compression effort from Maximum to Balanced")
    }

    // MARK: - Export footer

    var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            if workspaceMode == .batch,
               batchOptimizationSummary.colorReductionEnabled,
               batchOptimizationSummary.preset != .manual {
                batchPaletteProtectionControl

                Divider()
            }

            savingsBar

            Divider()

            if activeSaveItems.count == 1, activeSaveItems.first?.isClipboardItem == true {
                Text(destinationTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .padding(.leading, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 34)
                    .accessibilityLabel("Save destination")
                    .accessibilityValue(destinationTitle)
            } else {
                Menu {
                    Picker(
                        "Save destination",
                        selection: Binding(
                            get: { saveDestination },
                            set: { selectDestination($0) }
                        )
                    ) {
                        Text("Save copies").tag(SaveDestination.copies)
                        Text("Replace originals").tag(SaveDestination.replace)
                        if activeSaveItems.count == 1 {
                            Divider()
                            Label("Save As…", systemImage: "square.and.arrow.down")
                                .tag(SaveDestination.saveAs)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    Text(destinationTitle)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .padding(.leading, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 34)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .frame(height: 34)
                .disabled(isSaving)
                .accessibilityLabel("Save destination")
                .accessibilityValue(destinationTitle)
            }

            HStack(spacing: 8) {
                Button {
                    save()
                } label: {
                    HStack(spacing: 8) {
                        if isSaving || (activePreviewStatus.isPending && !activeEstimateAvailable && saveSummary == nil) {
                            LoadingSpinner(controlSize: .small, contrast: .light)
                        } else if activePreviewStatus.failedCount > 0 || (saveSummary?.failedCount ?? 0) > 0 {
                            Image(systemName: "exclamationmark.triangle.fill")
                        } else if saveConfirmationTitle != nil {
                            Image(systemName: "checkmark.circle.fill")
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                        }
                        Text(saveButtonTitle)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(isSaving || !activePreviewStatus.canSave)
                .help("\(saveButtonTitle) (Command-S)")

                if workspaceMode == .image, selectedItem != nil {
                    Button {
                        copyPreviewToClipboard()
                    } label: {
                        Image(systemName: copiedToClipboardURL == selectedItem?.url
                              ? "checkmark"
                              : "doc.on.clipboard")
                            .frame(width: 24, height: 26)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!canCopyPreviewToClipboard)
                    .help(copiedToClipboardURL == selectedItem?.url
                          ? "Copied"
                          : "Copy optimized image to the clipboard (Command-C)")
                    .accessibilityLabel(copiedToClipboardURL == selectedItem?.url
                                        ? "Copied to clipboard"
                                        : "Copy optimized image to clipboard")
                }
            }
        }
        .padding(14)
        .background(WorkspaceSurface.inspector)
        .overlay(alignment: .top) { Divider() }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: saveSummary)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: copiedToClipboardURL)
    }

    var saveDestination: SaveDestination {
        if activeSaveItems.count == 1, activeSaveItems.first?.isClipboardItem == true {
            return .saveAs
        }
        if saveAsSelected && activeSaveItems.count == 1 { return .saveAs }
        return store.settings.createCopy ? .copies : .replace
    }

    var destinationTitle: String {
        switch saveDestination {
        case .copies: "Save copies"
        case .replace: "Replace originals"
        case .saveAs: "Save As…"
        }
    }

    func selectDestination(_ destination: SaveDestination) {
        saveAsSelected = destination == .saveAs
        switch destination {
        case .copies: store.settings.createCopy = true
        case .replace: store.settings.createCopy = false
        case .saveAs: break
        }
    }

    var saveButtonTitle: String {
        if isSaving { return "Saving…" }
        if let saveConfirmationTitle { return saveConfirmationTitle }
        if activePreviewStatus.failedCount > 0 {
            return activePreviewStatus.failedCount == 1 ? "Preview Failed" : "Previews Failed"
        }
        let count = activeSaveItems.count
        if count == 0 { return "Save" }
        switch saveDestination {
        case .copies:
            return count == 1 ? "Save Copy" : "Save \(count) Copies"
        case .replace:
            return count == 1 ? "Replace Original" : "Replace \(count) Originals"
        case .saveAs:
            return "Save As…"
        }
    }

    var saveConfirmationTitle: String? {
        guard !isSaving, let summary = saveSummary else { return nil }
        let total = summary.totalCount
        guard total > 0 else { return nil }
        if summary.writtenCount == total {
            switch saveDestination {
            case .replace:
                return total == 1 ? "Replaced" : "Replaced \(total) Originals"
            case .copies:
                return total == 1 ? "Saved" : "Saved \(total) Copies"
            case .saveAs:
                return "Saved"
            }
        }
        if summary.writtenCount > 0 {
            return "Saved \(summary.writtenCount) of \(total)"
        }
        if summary.skippedCount == total { return "Already optimized" }
        if summary.failedCount == total {
            return total == 1 ? "Save Failed" : "\(total) Saves Failed"
        }
        if summary.skippedCount > 0 && summary.failedCount > 0 {
            return "\(summary.skippedCount) unchanged · \(summary.failedCount) failed"
        }
        return nil
    }

    // MARK: - Savings bar

    var savingsBar: some View {
        let scopedItems = activeSaveItems
        let estimates = scopedItems.compactMap { previews[$0.url]?.lastKnownOutcome }
        let status = activePreviewStatus
        let hasCompleteEstimate = !scopedItems.isEmpty && estimates.count == scopedItems.count
        let showInitialProgress = status.isPending && !hasCompleteEstimate
        let original = estimates.reduce(UInt64(0)) { $0 + $1.originalBytes }
        let output = estimates.reduce(UInt64(0)) { $0 + $1.outputBytes }
        let saved = Int64(original) - Int64(output)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(workspaceMode == .batch ? "Estimated batch result" : "Estimated result")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if showInitialProgress { LoadingSpinner(controlSize: .small) }
            }

            HStack(spacing: 8) {
                if status.failedCount > 0 {
                    Text(status.failedCount == 1 ? "1 preview failed" : "\(status.failedCount) previews failed")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { refreshPreviews() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Retry failed previews")
                } else if hasCompleteEstimate && original > 0 {
                    let percent = Int((Double(saved) / Double(original) * 100).rounded())
                    Text(saved == 0
                         ? Self.byteText(output)
                         : saved > 0
                             ? "\(Self.byteText(original)) → \(Self.byteText(output)) (−\(percent)%)"
                             : "\(Self.byteText(original)) → \(Self.byteText(output))")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(saved == 0
                         ? "Same size"
                         : saved > 0
                             ? "−\(Self.byteText(UInt64(saved)))"
                             : "No smaller result")
                        .foregroundStyle(saved > 0 ? .green : .secondary)
                        .contentTransition(.numericText())
                } else if status.isPending {
                    Text(scopedItems.count > 1 && status.readyCount > 0
                         ? "Calculating \(status.readyCount) of \(status.totalCount)…"
                         : "Calculating…")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Preview unavailable")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline.weight(.medium).monospacedDigit())
            .frame(height: 22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: output)
    }


}

struct ColorReductionSelector: View {
    let isEnabled: Bool
    let selectedPreset: ColorReductionPreset?
    let status: String?
    let setEnabled: (Bool) -> Void
    let select: (ColorReductionPreset) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(
                isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in setEnabled(newValue) }
                )
            ) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "paintpalette.fill")
                        .foregroundStyle(isEnabled ? Color.orange : Color.secondary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 7) {
                            Text("Reduce colors")
                                .font(.subheadline.weight(.medium))
                            if let status {
                                Text(status)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("Smaller files; colors may change.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .frame(maxWidth: .infinity)

            if isEnabled {
                HStack(spacing: 2) {
                    ForEach(ColorReductionPreset.allCases) { preset in
                        Button {
                            select(preset)
                        } label: {
                            Text(preset.title)
                                .font(.caption.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(selectedPreset == preset ? Color.primary : Color.secondary)
                        .background {
                            if selectedPreset == preset {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.1))
                            }
                        }
                        .help(preset.help)
                        .accessibilityAddTraits(selectedPreset == preset ? .isSelected : [])
                    }
                }
                .padding(3)
                .background(
                    Color.primary.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isEnabled)
    }
}
