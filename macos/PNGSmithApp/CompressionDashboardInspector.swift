import SwiftUI

extension CompressionDashboard {
    // MARK: - Mode controls

    var modeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                Button {
                    reduceColorsEnabled.toggle()
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "paintpalette.fill")
                            .foregroundStyle(reduceColorsEnabled ? Color.orange : Color.secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Reduce colors")
                                .font(.subheadline.weight(.medium))
                            Text("Smaller files, with possible visual changes.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        Toggle("", isOn: reduceColorsBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .allowsHitTesting(false)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reduce colors")
                .accessibilityValue(reduceColorsEnabled ? "On" : "Off")

                if reduceColorsEnabled {
                    shrinkControls
                        .transition(.opacity)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: reduceColorsEnabled)
    }

    var reduceColorsBinding: Binding<Bool> {
        Binding(
            get: { reduceColorsEnabled },
            set: { newValue in reduceColorsEnabled = newValue }
        )
    }

    var shrinkControls: some View {
        let outcome = selectedItem.flatMap { previews[$0.url]?.readyOutcome }
        let automaticCount = selectedItem.flatMap { item in
            automaticColorBudgets[item.url] ?? outcome?.paletteEntries
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Button {
                    colorInput = String(autoColorsEnabled ? automaticCount ?? maxColorCount : maxColorCount)
                    showColorEditor = true
                } label: {
                    Text(autoColorsEnabled ? automaticCount.map(String.init) ?? "—" : String(maxColorCount))
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
                Toggle("Auto", isOn: $autoColorsEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Find the smallest palette that meets a high visual-quality target")
            }

            if autoColorsEnabled {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 2) {
                        ForEach(AutoColorStrategy.allCases) { strategy in
                            Button {
                                autoColorStrategyBinding.wrappedValue = strategy
                            } label: {
                                Text(strategy.title)
                                    .font(.subheadline.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(autoColorStrategy == strategy ? Color.primary : Color.secondary)
                            .background {
                                if autoColorStrategy == strategy {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.primary.opacity(0.1))
                                }
                            }
                            .help(strategy.help)
                            .accessibilityAddTraits(autoColorStrategy == strategy ? .isSelected : [])
                        }
                    }
                    .padding(3)
                    .background(
                        Color.primary.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )

                    Text(autoColorStrategy.help)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            } else {
                Slider(
                    value: Binding(
                        get: { Double(maxColorCount) },
                        set: { setMaxColors(Int($0.rounded())) }
                    ),
                    in: 2...256
                )
                .accessibilityLabel("Maximum colors")
                .accessibilityValue("\(maxColorCount)")
            }

        }
    }

    func setMaxColors(_ count: Int) {
        let clamped = min(max(count, 2), 256)
        maxColorCount = clamped
        colorInput = String(clamped)
    }

    func commitColorInput() {
        guard let value = Int(colorInput.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            colorInput = String(maxColorCount)
            return
        }
        autoColorsEnabled = false
        setMaxColors(value)
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
            savingsBar

            Divider()

            Menu {
                Button {
                    selectDestination(.copies)
                } label: {
                    Label("Save copies", systemImage: saveDestination == .copies ? "checkmark" : "doc.on.doc")
                }
                Button {
                    selectDestination(.replace)
                } label: {
                    Label("Replace originals", systemImage: saveDestination == .replace ? "checkmark" : "arrow.triangle.2.circlepath")
                }
                if items.count == 1 {
                    Divider()
                    Button {
                        selectDestination(.saveAs)
                    } label: {
                        Label("Save As…", systemImage: saveDestination == .saveAs ? "checkmark" : "square.and.arrow.down")
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: destinationIcon)
                        .foregroundStyle(saveDestination == .replace ? Color.orange : Color.accentColor)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(destinationTitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(outputCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 42)
                .contentShape(Rectangle())
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .disabled(isSaving)
            .accessibilityLabel("Save destination")
            .accessibilityValue(destinationTitle)

            Button {
                save()
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else if saveConfirmationTitle != nil {
                        Image(systemName: "checkmark.circle.fill")
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                    }
                    Text(saveButtonTitle)
                }
                .frame(maxWidth: .infinity, minHeight: 26)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(isSaving || items.isEmpty)
            .help("\(saveButtonTitle) (Command-S)")
        }
        .padding(14)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: saveSummary)
    }

    var outputCaption: String {
        switch saveDestination {
        case .copies: "Adds \(store.settings.suffix) to each filename"
        case .replace: "Changes the selected files in place"
        case .saveAs: "Choose a name and location"
        }
    }

    var saveDestination: SaveDestination {
        if saveAsSelected && items.count == 1 { return .saveAs }
        return store.settings.createCopy ? .copies : .replace
    }

    var destinationTitle: String {
        switch saveDestination {
        case .copies: "Save copies"
        case .replace: "Replace originals"
        case .saveAs: "Save As…"
        }
    }

    var destinationIcon: String {
        switch saveDestination {
        case .copies: "doc.on.doc"
        case .replace: "arrow.triangle.2.circlepath"
        case .saveAs: "square.and.arrow.down"
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
        let count = items.count
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
        if summary.writtenCount > 0 { return "Saved" }
        if summary.skippedCount > 0 { return "Already optimized" }
        return nil
    }

}
