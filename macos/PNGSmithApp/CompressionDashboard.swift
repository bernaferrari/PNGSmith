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
    ) var autoColorsEnabled = false
    @AppStorage(
        PNGSmithSettingsStore.autoStrategyKey,
        store: UserDefaults(suiteName: PNGSmithSettingsStore.appGroup) ?? .standard
    ) var autoColorStrategyRawValue = AutoColorStrategy.balanced.rawValue
    @State var colorInput = "256"
    @State var showColorEditor = false
    @State var previews: [URL: PreviewPhase] = [:]
    @State var automaticColorBudgets: [URL: Int] = [:]
    @State var generation = 0
    @State var sliderDebounce: Task<Void, Never>?
    @State var isImporterPresented = false
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
    @State var hoveredTabURL: URL?
    @State var hoveredTabCloseURL: URL?
    @State var tabDropTargetURL: URL?
    @State var cropSelections: [URL: CanvasEdit] = [:]
    @State var cropEditorItem: WorkItem?
    @State var cropChromeActive = false
    @FocusState var colorInputFocused: Bool
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
                canCycle: items.count > 1 && cropEditorItem == nil,
                canClose: selectedItem != nil && cropEditorItem == nil,
                selectPrevious: { selectImage(offset: -1) },
                selectNext: { selectImage(offset: 1) },
                closeSelected: { removeSelectedImage() }
            )
        )
        .task {
            guard !didRestoreOpenSession else { return }
            didRestoreOpenSession = true
            setMaxColors(maxColorCount)
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
            if newURL != nil {
                rememberOpenSession()
            } else if items.isEmpty {
                forgetOpenSession()
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.png],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { add(urls) }
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
        .onChange(of: reduceColorsEnabled) { _, _ in
            saveSummary = nil
            refreshPreviews()
        }
        .onChange(of: maxColorCount) { _, _ in
            guard reduceColorsEnabled, !autoColorsEnabled else { return }
            sliderDebounce?.cancel()
            sliderDebounce = Task {
                try? await Task.sleep(for: .milliseconds(260))
                guard !Task.isCancelled else { return }
                refreshPreviews()
            }
        }
        .onChange(of: autoColorsEnabled) { _, _ in
            automaticColorBudgets.removeAll()
            saveSummary = nil
            refreshPreviews()
        }
        .onChange(of: autoColorStrategyRawValue) { _, _ in
            guard autoColorsEnabled else { return }
            automaticColorBudgets.removeAll()
            saveSummary = nil
            refreshPreviews()
        }
        .onChange(of: store.settings) { oldValue, newValue in
            saveSummary = nil
            let before = PreviewVariant(mode: mode, maxColors: Int(maxColors), settings: oldValue)
            let after = PreviewVariant(mode: mode, maxColors: Int(maxColors), settings: newValue)
            if before != after { refreshPreviews() }
        }
    }

}

struct HoldToCompareButtonStyle: ButtonStyle {
    @Binding var isShowingOriginal: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .onChange(of: configuration.isPressed) { _, isPressed in
                isShowingOriginal = isPressed
            }
    }
}
