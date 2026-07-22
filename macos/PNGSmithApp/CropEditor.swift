import AppKit
import SwiftUI

private enum CropGeometryField: Hashable {
    case width, height, sizePercentage
}


struct CropEditorWorkspace: View {
    let item: WorkItem
    let onDismissalStarted: () -> Void
    let onCancel: () -> Void
    let onApply: (CanvasEdit) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.undoManager) private var undoManager
    @Namespace private var aspectSelectionNamespace
    @StateObject private var history = CropEditHistory()
    @State private var canvas: NormalizedCrop
    @State private var aspect: CropAspect = .free
    @State private var allowOutsideImage: Bool
    @State private var widthInput: String
    @State private var heightInput: String
    @State private var sizePercentageInput: String
    @State private var moveStart: CGRect?
    @State private var resizeStart: CGRect?
    @State private var activeHandle: CropHandle?
    @State private var baseImageRect: CGRect = .zero
    @State private var workspaceRect: CGRect = .zero
    @State private var snapGuideX: CGFloat?
    @State private var snapGuideY: CGFloat?
    @State private var gestureStartEdit: CanvasEdit?
    @State private var workspacePresented = false
    @State private var surfaceDimmed = false
    @State private var imageLayoutProgress: CGFloat = 0
    @State private var viewZoom: CGFloat = 1
    @State private var viewportPan = CGSize.zero
    @State private var viewportPanStart: CGSize?
    @State private var isPanningViewport = false
    @State private var isDismissing = false
    @State private var presentationTask: Task<Void, Never>?
    @FocusState private var geometryField: CropGeometryField?

    init(
        item: WorkItem,
        initial: CanvasEdit,
        onDismissalStarted: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onApply: @escaping (CanvasEdit) -> Void
    ) {
        self.item = item
        self.onDismissalStarted = onDismissalStarted
        self.onCancel = onCancel
        self.onApply = onApply
        _canvas = State(initialValue: initial.canvas)
        _aspect = State(initialValue: initial.aspect)
        _allowOutsideImage = State(initialValue: CropGeometry.extendsOutsideImage(initial.canvas))
        let initialSize = initial.pixelOptions(
            imageWidth: item.pixelWidth,
            imageHeight: item.pixelHeight
        )
        _widthInput = State(initialValue: String(initialSize.width))
        _heightInput = State(initialValue: String(initialSize.height))
        _sizePercentageInput = State(initialValue: "100")
    }

    var body: some View {
        HStack(spacing: 0) {
            editorCanvas
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().opacity(workspacePresented ? 1 : 0)
            sidebar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            history.connect(edit: editBinding, undoManager: undoManager)
            presentationTask?.cancel()
            presentationTask = Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled else { return }
                if reduceMotion {
                    surfaceDimmed = true
                    imageLayoutProgress = 1
                    workspacePresented = true
                    return
                }
                withAnimation(imageHandoffAnimation) {
                    imageLayoutProgress = 1
                }
                withAnimation(dimmingAnimation) {
                    surfaceDimmed = true
                }
                withAnimation(chromeAnimation) {
                    workspacePresented = true
                }
            }
        }
        .onDisappear {
            presentationTask?.cancel()
            history.disconnect()
            NSCursor.arrow.set()
        }
        .onChange(of: geometryField) { oldField, _ in
            commitGeometryField(oldField)
        }
        .onChange(of: canvas) { _, _ in
            synchronizeGeometryInputs()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "crop")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 38, height: 38)
                            .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Crop").font(.headline)
                            Text(item.url.lastPathComponent)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(2).truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        HStack(spacing: 4) {
                            Button { undoManager?.undo() } label: {
                                Image(systemName: "arrow.uturn.backward")
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .disabled(!(undoManager?.canUndo ?? false))
                            .help("Undo")
                            .accessibilityLabel("Undo")

                            Button { undoManager?.redo() } label: {
                                Image(systemName: "arrow.uturn.forward")
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .disabled(!(undoManager?.canRedo ?? false))
                            .help("Redo")
                            .accessibilityLabel("Redo")
                        }
                        .foregroundStyle(.secondary)
                        .id(history.revision)
                    }

                    Divider().padding(.vertical, 18)
                    Text("Aspect ratio")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    aspectControl.padding(.top, 10)

                    Divider().padding(.vertical, 18)
                    outsideImageControl

                    Divider().padding(.vertical, 18)
                    geometryControls
                }
                .padding(18)
            }
            .frame(maxHeight: .infinity)
            .opacity(workspacePresented ? 1 : 0)
            .offset(x: workspacePresented ? 0 : 14)
            .scaleEffect(workspacePresented ? 1 : 0.985, anchor: .trailing)

            HStack(spacing: 10) {
                Button("Cancel") { dismiss(after: onCancel) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply Crop") {
                    let edit = currentEdit
                    dismiss { onApply(edit) }
                }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .opacity(workspacePresented ? 1 : 0)
            .offset(y: workspacePresented ? 0 : 16)
            .scaleEffect(workspacePresented ? 1 : 0.98, anchor: .bottom)
            .padding(14)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
        .frame(width: 330)
    }

    private var aspectControl: some View {
        HStack(spacing: 2) {
            ForEach(CropAspect.allCases) { option in
                Button {
                    let before = currentEdit
                    withAnimation(aspectAnimation) {
                        aspect = option
                        if let ratio = option.ratio {
                            canvas = fittedCanvas(for: ratio)
                        }
                    }
                    history.record(before: before, actionName: "Change Aspect Ratio")
                } label: {
                    Text(option.rawValue)
                        .font(.subheadline.weight(aspect == option ? .semibold : .medium))
                        .foregroundStyle(aspect == option ? .primary : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                        .background {
                            if aspect == option {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.11))
                                    .matchedGeometryEffect(
                                        id: "aspect-selection",
                                        in: aspectSelectionNamespace
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .accessibilityAddTraits(aspect == option ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }

    private var geometryControls: some View {
        return VStack(alignment: .leading, spacing: 16) {
            Text("Output size")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                geometryTextField("Width", text: $widthInput, field: .width)
                Text("×").foregroundStyle(.tertiary)
                geometryTextField("Height", text: $heightInput, field: .height)
                Text("px").font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text("Crop size")
                    .font(.subheadline)
                Spacer()
                TextField("100", text: $sizePercentageInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(width: 58)
                    .focused($geometryField, equals: .sizePercentage)
                    .onSubmit { commitGeometryField(.sizePercentage) }
                    .accessibilityLabel("Crop size percent")
                Text("%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func geometryTextField(
        _ label: String,
        text: Binding<String>,
        field: CropGeometryField
    ) -> some View {
        TextField(label, text: text)
            .textFieldStyle(.roundedBorder)
            .font(.body.monospacedDigit())
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: .infinity)
            .focused($geometryField, equals: field)
            .onSubmit { commitGeometryField(field) }
            .accessibilityLabel(label)
    }

    private var outsideImageControl: some View {
        Toggle(isOn: outsideImageBinding) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Allow outside image")
                    .font(.subheadline.weight(.medium))
                Text("Adds transparent space beyond the edges.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var outsideImageBinding: Binding<Bool> {
        Binding(
            get: { allowOutsideImage },
            set: { setAllowOutsideImage($0) }
        )
    }

    private var currentEdit: CanvasEdit {
        CanvasEdit(
            canvas: canvas,
            aspect: aspect
        )
    }

    private var editBinding: Binding<CanvasEdit> {
        Binding(
            get: { currentEdit },
            set: { apply($0) }
        )
    }

    private func apply(_ edit: CanvasEdit) {
        canvas = edit.canvas
        aspect = edit.aspect
        if CropGeometry.extendsOutsideImage(edit.canvas) {
            allowOutsideImage = true
        }
    }

    private func setAllowOutsideImage(_ allowed: Bool) {
        guard allowOutsideImage != allowed else { return }
        let before = currentEdit
        withAnimation(aspectAnimation) {
            if !allowed, baseImageRect.width > 0, baseImageRect.height > 0 {
                let current = CropGeometry.canvasRect(canvas, in: baseImageRect)
                canvas = CropGeometry.normalizedCanvas(
                    CropGeometry.fit(current, inside: baseImageRect),
                    in: baseImageRect
                )
            }
            allowOutsideImage = allowed
        }
        history.record(before: before, actionName: allowed ? "Allow Outside Image" : "Constrain Crop")
    }

    private func commitGeometryField(_ field: CropGeometryField?) {
        guard let field else { return }
        switch field {
        case .width:
            guard let width = Int(widthInput), width > 0 else {
                synchronizeGeometryInputs(force: .width)
                return
            }
            resizeCrop(to: width, changing: .width)
        case .height:
            guard let height = Int(heightInput), height > 0 else {
                synchronizeGeometryInputs(force: .height)
                return
            }
            resizeCrop(to: height, changing: .height)
        case .sizePercentage:
            let normalized = sizePercentageInput.replacingOccurrences(of: ",", with: ".")
            guard let percent = Double(normalized), percent.isFinite else {
                synchronizeGeometryInputs(force: .sizePercentage)
                return
            }
            resizeCrop(toPercent: percent)
        }
    }

    private func resizeCrop(to outputPixels: Int, changing field: CropGeometryField) {
        guard baseImageRect.width > 0, baseImageRect.height > 0 else { return }
        let before = currentEdit
        let bounds = allowOutsideImage ? workspaceRect : baseImageRect
        var rect = CropGeometry.canvasRect(canvas, in: baseImageRect)

        if let ratio = aspect.ratio {
            let outputWidth: Double
            let outputHeight: Double
            if field == .height {
                outputHeight = Double(outputPixels)
                outputWidth = outputHeight * ratio
            } else {
                outputWidth = Double(outputPixels)
                outputHeight = outputWidth / ratio
            }
            let width = CGFloat(outputWidth / Double(item.pixelWidth)) * baseImageRect.width
            let height = CGFloat(outputHeight / Double(item.pixelHeight)) * baseImageRect.height
            rect = CropGeometry.fit(
                CGRect(
                    x: rect.midX - width / 2,
                    y: rect.midY - height / 2,
                    width: width,
                    height: height
                ),
                inside: bounds
            )
        } else if field == .height {
            let requested = CGFloat(Double(outputPixels) / Double(item.pixelHeight)) * baseImageRect.height
            let minimum = baseImageRect.height / CGFloat(max(item.pixelHeight, 1))
            let height = min(max(requested, minimum), bounds.height)
            rect.origin.y = min(
                max(rect.midY - height / 2, bounds.minY),
                bounds.maxY - height
            )
            rect.size.height = height
        } else {
            let requested = CGFloat(Double(outputPixels) / Double(item.pixelWidth)) * baseImageRect.width
            let minimum = baseImageRect.width / CGFloat(max(item.pixelWidth, 1))
            let width = min(max(requested, minimum), bounds.width)
            rect.origin.x = min(
                max(rect.midX - width / 2, bounds.minX),
                bounds.maxX - width
            )
            rect.size.width = width
        }

        withAnimation(aspectAnimation) {
            canvas = CropGeometry.normalizedCanvas(rect, in: baseImageRect)
        }
        history.record(before: before, actionName: "Change Output Size")
        synchronizeGeometryInputs(force: field)
    }

    private func resizeCrop(toPercent requestedPercent: Double) {
        guard baseImageRect.width > 0, baseImageRect.height > 0 else { return }
        let before = currentEdit
        let reference = referenceCropRect()
        let placementBounds = allowOutsideImage ? workspaceRect : baseImageRect
        let maximumScale = allowOutsideImage
            ? min(placementBounds.width / reference.width, placementBounds.height / reference.height)
            : 1
        let percent = min(max(requestedPercent, 1), maximumScale * 100)
        let scale = CGFloat(percent / 100)
        let current = CropGeometry.canvasRect(canvas, in: baseImageRect)
        let target = CropGeometry.fit(
            CGRect(
                x: current.midX - reference.width * scale / 2,
                y: current.midY - reference.height * scale / 2,
                width: reference.width * scale,
                height: reference.height * scale
            ),
            inside: placementBounds
        )

        withAnimation(aspectAnimation) {
            canvas = CropGeometry.normalizedCanvas(target, in: baseImageRect)
        }
        history.record(before: before, actionName: "Change Crop Size")
        synchronizeGeometryInputs(force: .sizePercentage)
    }

    private func referenceCropRect() -> CGRect {
        guard let ratio = aspect.ratio else { return baseImageRect }
        let target = CGFloat(ratio)
        let imageRatio = baseImageRect.width / baseImageRect.height
        let size: CGSize
        if imageRatio > target {
            size = CGSize(width: baseImageRect.height * target, height: baseImageRect.height)
        } else {
            size = CGSize(width: baseImageRect.width, height: baseImageRect.width / target)
        }
        return CGRect(
            x: baseImageRect.midX - size.width / 2,
            y: baseImageRect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func cropSizePercentage() -> Double {
        guard baseImageRect.width > 0, baseImageRect.height > 0 else { return 100 }
        let reference = referenceCropRect()
        let current = CropGeometry.canvasRect(canvas, in: baseImageRect)
        let widthScale = max(current.width / reference.width, 0)
        let heightScale = max(current.height / reference.height, 0)
        return Double(sqrt(widthScale * heightScale) * 100)
    }

    private func synchronizeGeometryInputs(force: CropGeometryField? = nil) {
        let size = currentEdit.pixelOptions(
            imageWidth: item.pixelWidth,
            imageHeight: item.pixelHeight
        )
        if geometryField != .width || force == .width {
            widthInput = String(size.width)
        }
        if geometryField != .height || force == .height {
            heightInput = String(size.height)
        }
        if geometryField != .sizePercentage || force == .sizePercentage {
            sizePercentageInput = String(Int(cropSizePercentage().rounded()))
        }
    }

    private func reset() {
        let before = currentEdit
        aspect = .free
        canvas = .full
        history.record(before: before, actionName: "Reset Crop")
    }

    private var editorCanvas: some View {
        GeometryReader { proxy in
            ZStack {
                NativeMagnifyingScrollView(
                    magnification: $viewZoom,
                    panOffset: viewportPan
                ) {
                    cropStage(size: proxy.size)
                }

                zoomControl
                    .opacity(workspacePresented ? 1 : 0)
                    .offset(y: workspacePresented ? 0 : 18)
                    .scaleEffect(workspacePresented ? 1 : 0.96, anchor: .bottomTrailing)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1))
            }
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        }
    }

    private func cropStage(size: CGSize) -> some View {
        let workspace = CGRect(origin: .zero, size: size)
        let base = CropGeometry.imageRect(
            source: CGSize(width: item.pixelWidth, height: item.pixelHeight),
            available: size,
            allowsOutsideImage: allowOutsideImage,
            marginScale: imageLayoutProgress
        )
        let frame = CropGeometry.canvasRect(canvas, in: base)
        let editingBounds = allowOutsideImage ? workspace : base
        return ZStack {
            Color(nsColor: .underPageBackgroundColor)

            imageSurface(frame: base)

            CropDimmingShape(imageRect: base, cutout: frame)
                .fill(.black.opacity(surfaceDimmed ? 0.62 : 0), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

            cropGrid(in: frame)
                .opacity(workspacePresented ? 1 : 0)
                .allowsHitTesting(false)
            snapGuides(imageRect: base).allowsHitTesting(false)

            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .gesture(viewportPanGesture)
                .allowsHitTesting(workspacePresented && viewZoom > 1)

            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .gesture(canvasMoveGesture(base: base, workspace: editingBounds))
                .allowsHitTesting(workspacePresented && viewZoom <= 1.001)

            ForEach(CropHandle.edges, id: \.self) { handle in
                handleView(handle, frame: frame, base: base, workspace: editingBounds)
                    .opacity(workspacePresented ? 1 : 0)
                    .allowsHitTesting(workspacePresented)
            }

            // Corners sit above the edge hit regions so diagonal resizing wins
            // where the two affordances overlap.
            ForEach(CropHandle.corners, id: \.self) { handle in
                handleView(handle, frame: frame, base: base, workspace: editingBounds)
                    .opacity(workspacePresented ? 1 : 0)
                    .allowsHitTesting(workspacePresented)
            }

        }
        .frame(width: size.width, height: size.height)
        .animation(aspectAnimation, value: aspect)
        .animation(aspectAnimation, value: allowOutsideImage)
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                if let activeHandle {
                    activeHandle.cursor.set()
                } else if isPanningViewport {
                    NSCursor.closedHand.set()
                } else if let handle = CropGeometry.handle(at: location, frame: frame) {
                    handle.cursor.set()
                } else if viewZoom > 1 {
                    NSCursor.openHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            case .ended:
                if activeHandle == nil { NSCursor.arrow.set() }
            }
        }
        .onAppear {
            baseImageRect = base
            workspaceRect = workspace
            synchronizeGeometryInputs()
        }
        .onChange(of: base) { _, value in
            baseImageRect = value
            synchronizeGeometryInputs()
        }
        .onChange(of: workspace) { _, value in workspaceRect = value }
    }

    private func imageSurface(frame: CGRect) -> some View {
        ZStack {
            WorkspaceImageBackdrop(frame: frame, viewScale: viewZoom)
            WorkspaceFileImage(url: item.url, frame: frame)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var zoomControl: some View {
        HStack(spacing: 7) {
            Button { adjustViewZoom(by: -0.25) } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 18, height: 18)
            }
            .disabled(viewZoom <= 1)
            .help("Zoom out")

            Slider(value: $viewZoom, in: 1...4)
                .frame(width: 82)
                .accessibilityLabel("View zoom")

            Button { adjustViewZoom(by: 0.25) } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 18, height: 18)
            }
            .disabled(viewZoom >= 4)
            .help("Zoom in")

            Divider().frame(height: 16)

            Button { setViewZoom(1) } label: {
                Text("\(Int((viewZoom * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 36, alignment: .trailing)
            }
            .help("Reset view zoom to 100%")

            Button { reset() } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 18, height: 18)
            }
            .disabled(currentEdit.isIdentity)
            .help("Reset crop")
            .accessibilityLabel("Reset crop")
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .controlSize(.small)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.24), radius: 8, y: 3)
    }

    private func adjustViewZoom(by amount: CGFloat) {
        setViewZoom(viewZoom + amount)
    }

    private func setViewZoom(_ value: CGFloat) {
        viewZoom = min(max(value, 1), 4)
    }

    private var viewportPanGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                guard viewZoom > 1 else { return }
                if viewportPanStart == nil {
                    viewportPanStart = viewportPan
                    isPanningViewport = true
                    NSCursor.closedHand.set()
                }
                guard let start = viewportPanStart else { return }
                viewportPan = CGSize(
                    width: start.width + value.translation.width,
                    height: start.height + value.translation.height
                )
            }
            .onEnded { _ in
                viewportPanStart = nil
                isPanningViewport = false
                if viewZoom > 1 {
                    NSCursor.openHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
    }

    private var aspectAnimation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.34, bounce: 0.1)
    }

    private var imageHandoffAnimation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.06)
    }

    private var dimmingAnimation: Animation? {
        reduceMotion ? nil : .timingCurve(0.77, 0, 0.175, 1, duration: 0.18)
    }

    private var chromeAnimation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.08)
    }

    private func dismiss(after completion: @escaping () -> Void) {
        guard !isDismissing else { return }
        isDismissing = true
        presentationTask?.cancel()
        onDismissalStarted()

        if reduceMotion {
            workspacePresented = false
            surfaceDimmed = false
            imageLayoutProgress = 0
            completion()
            return
        }

        withAnimation(chromeAnimation) {
            workspacePresented = false
        }
        withAnimation(dimmingAnimation) {
            surfaceDimmed = false
        }
        withAnimation(imageHandoffAnimation) {
            imageLayoutProgress = 0
        }
        presentationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(290))
            guard !Task.isCancelled else { return }
            completion()
        }
    }

    private func canvasMoveGesture(base: CGRect, workspace: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if moveStart == nil {
                    moveStart = CropGeometry.canvasRect(canvas, in: base)
                    gestureStartEdit = currentEdit
                }
                guard let start = moveStart else { return }
                var proposed = CGRect(
                    x: start.minX + value.translation.width,
                    y: start.minY + value.translation.height,
                    width: start.width,
                    height: start.height
                )
                proposed.origin.x = min(max(proposed.minX, workspace.minX), workspace.maxX - proposed.width)
                proposed.origin.y = min(max(proposed.minY, workspace.minY), workspace.maxY - proposed.height)
                let snapDistance = 12 / viewZoom
                let xSnap = CropGeometry.nearestSnap(
                    candidates: [
                        (base.midX - proposed.midX, base.midX),
                        (base.minX - proposed.minX, base.minX),
                        (base.maxX - proposed.maxX, base.maxX),
                    ],
                    threshold: snapDistance
                )
                let ySnap = CropGeometry.nearestSnap(
                    candidates: [
                        (base.midY - proposed.midY, base.midY),
                        (base.minY - proposed.minY, base.minY),
                        (base.maxY - proposed.maxY, base.maxY),
                    ],
                    threshold: snapDistance
                )
                if let xSnap { proposed.origin.x += xSnap.offset }
                if let ySnap { proposed.origin.y += ySnap.offset }
                proposed.origin.x = min(max(proposed.minX, workspace.minX), workspace.maxX - proposed.width)
                proposed.origin.y = min(max(proposed.minY, workspace.minY), workspace.maxY - proposed.height)
                updateSnapFeedback(x: xSnap?.guide, y: ySnap?.guide)
                canvas = CropGeometry.normalizedCanvas(proposed, in: base)
            }
            .onEnded { _ in
                if let before = gestureStartEdit {
                    history.record(before: before, actionName: "Move Crop")
                }
                moveStart = nil
                gestureStartEdit = nil
                clearSnapping()
            }
    }

    private func handleView(_ handle: CropHandle, frame: CGRect, base: CGRect, workspace: CGRect) -> some View {
        Color.clear
            .frame(
                width: CropGeometry.hitSize(for: handle, frame: frame).width,
                height: CropGeometry.hitSize(for: handle, frame: frame).height
            )
            .contentShape(Rectangle())
            .position(CropGeometry.point(for: handle, in: frame))
            .gesture(resizeGesture(handle, base: base, workspace: workspace))
            .accessibilityLabel("Resize crop")
    }

    private func resizeGesture(_ handle: CropHandle, base: CGRect, workspace: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                handle.cursor.set()
                if resizeStart == nil {
                    resizeStart = CropGeometry.canvasRect(canvas, in: base)
                    activeHandle = handle
                    gestureStartEdit = currentEdit
                }
                guard let start = resizeStart else { return }
                let resized = resizedRect(
                    start,
                    handle: handle,
                    translation: value.translation,
                    imageRect: base,
                    workspace: workspace
                )
                canvas = CropGeometry.normalizedCanvas(resized, in: base)
            }
            .onEnded { _ in
                if let before = gestureStartEdit {
                    history.record(before: before, actionName: "Resize Crop")
                }
                resizeStart = nil
                activeHandle = nil
                gestureStartEdit = nil
                clearSnapping()
                NSCursor.arrow.set()
            }
    }

    private func resizedRect(
        _ start: CGRect,
        handle: CropHandle,
        translation: CGSize,
        imageRect: CGRect,
        workspace: CGRect
    ) -> CGRect {
        let minimum: CGFloat = 40
        let snapDistance = 12 / viewZoom
        let handlePoint = CropGeometry.point(for: handle, in: start)
        var p = CGPoint(x: handlePoint.x + translation.width, y: handlePoint.y + translation.height)
        var xGuide: CGFloat?
        var yGuide: CGFloat?

        switch handle {
        case .topLeading, .leading, .bottomLeading:
            if abs(p.x - imageRect.minX) < snapDistance { p.x = imageRect.minX; xGuide = imageRect.minX }
        case .topTrailing, .trailing, .bottomTrailing:
            if abs(p.x - imageRect.maxX) < snapDistance { p.x = imageRect.maxX; xGuide = imageRect.maxX }
        case .top, .bottom:
            break
        }
        switch handle {
        case .topLeading, .top, .topTrailing:
            if abs(p.y - imageRect.minY) < snapDistance { p.y = imageRect.minY; yGuide = imageRect.minY }
        case .bottomLeading, .bottom, .bottomTrailing:
            if abs(p.y - imageRect.maxY) < snapDistance { p.y = imageRect.maxY; yGuide = imageRect.maxY }
        case .leading, .trailing:
            break
        }
        updateSnapFeedback(x: xGuide, y: yGuide)

        var left = start.minX, right = start.maxX, top = start.minY, bottom = start.maxY
        switch handle {
        case .topLeading: left = p.x; top = p.y
        case .top: top = p.y
        case .topTrailing: right = p.x; top = p.y
        case .leading: left = p.x
        case .trailing: right = p.x
        case .bottomLeading: left = p.x; bottom = p.y
        case .bottom: bottom = p.y
        case .bottomTrailing: right = p.x; bottom = p.y
        }
        left = min(max(left, workspace.minX), right - minimum)
        right = max(min(right, workspace.maxX), left + minimum)
        top = min(max(top, workspace.minY), bottom - minimum)
        bottom = max(min(bottom, workspace.maxY), top + minimum)
        var result = CGRect(x: left, y: top, width: right - left, height: bottom - top)

        if let ratio = aspect.ratio {
            let target = CGFloat(ratio)
            if handle.isCorner {
                let anchor = CropGeometry.oppositePoint(for: handle, in: start)
                var width = max(abs(p.x - anchor.x), minimum)
                var height = width / target
                if height > abs(p.y - anchor.y) { height = max(abs(p.y - anchor.y), minimum); width = height * target }
                result = CGRect(
                    x: p.x < anchor.x ? anchor.x - width : anchor.x,
                    y: p.y < anchor.y ? anchor.y - height : anchor.y,
                    width: width, height: height
                )
            } else if handle == .top || handle == .bottom {
                let height = result.height
                let width = height * target
                result.origin.x = start.midX - width / 2
                result.size.width = width
            } else {
                let width = result.width
                let height = width / target
                result.origin.y = start.midY - height / 2
                result.size.height = height
            }
            result = CropGeometry.fit(result, inside: workspace)
        }
        return result
    }

    private func fittedCanvas(for ratio: Double) -> NormalizedCrop {
        let current = CropGeometry.canvasRect(canvas, in: baseImageRect)
        guard current.width > 0, current.height > 0, ratio > 0 else { return canvas }

        // Preserve area instead of repeatedly fitting each new ratio inside the
        // previous crop. This keeps preset changes reversible and lets one axis
        // expand while the other contracts, like a canvas crop tool.
        let area = current.width * current.height
        let width = sqrt(area * ratio)
        let height = width / ratio
        let bounds = allowOutsideImage ? workspaceRect : baseImageRect
        let rect = CropGeometry.fit(
            CGRect(
                x: current.midX - width / 2,
                y: current.midY - height / 2,
                width: width,
                height: height
            ),
            inside: bounds
        )
        return CropGeometry.normalizedCanvas(rect, in: baseImageRect)
    }

    private func cropGrid(in rect: CGRect) -> some View {
        AnimatedCropGrid(
            rect: rect,
            emphasized: activeHandle != nil || moveStart != nil
        )
    }

    private func snapGuides(imageRect: CGRect) -> some View {
        Path { path in
            if let snapGuideX {
                path.move(to: CGPoint(x: snapGuideX, y: imageRect.minY))
                path.addLine(to: CGPoint(x: snapGuideX, y: imageRect.maxY))
            }
            if let snapGuideY {
                path.move(to: CGPoint(x: imageRect.minX, y: snapGuideY))
                path.addLine(to: CGPoint(x: imageRect.maxX, y: snapGuideY))
            }
        }
        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    private func updateSnapFeedback(x: CGFloat?, y: CGFloat?) {
        let enteredNewGuide = (x != nil && x != snapGuideX) || (y != nil && y != snapGuideY)
        if enteredNewGuide {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        snapGuideX = x
        snapGuideY = y
    }

    private func clearSnapping() {
        snapGuideX = nil
        snapGuideY = nil
    }

}
