import AppKit
import SwiftUI

enum CropGeometryField: Hashable {
    case width, height, sizePercentage
}

// MARK: - Crop Configuration & Lifecycle

struct CropEditorWorkspace: View {
    let item: WorkItem
    let comparisonDividerPosition: CGFloat
    let comparisonDividerVisible: Bool
    let onDismissalStarted: () -> Void
    let onCancel: () -> Void
    let onApply: (CanvasEdit) -> Void

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.undoManager) var undoManager
    @Namespace var aspectSelectionNamespace
    @StateObject var history = CropEditHistory()
    @State var canvas: NormalizedCrop
    @State var aspect: CropAspect = .free
    @State var allowOutsideImage: Bool
    @State var widthInput: String
    @State var heightInput: String
    @State var sizePercentageInput: String
    @State var moveStart: CGRect?
    @State var resizeStart: CGRect?
    @State var activeHandle: CropHandle?
    @State var baseImageRect: CGRect = .zero
    @State var workspaceRect: CGRect = .zero
    @State var snapGuideX: CGFloat?
    @State var snapGuideY: CGFloat?
    @State var gestureStartEdit: CanvasEdit?
    @State var workspacePresented = false
    @State var cropFramePresented = false
    @State var surfaceDimmed = false
    @State var imageLayoutProgress: CGFloat = 0
    @State var handoffProgress: CGFloat = 0
    @State var handoffVisible = true
    @State var viewZoom: CGFloat = 1
    @State var isDismissing = false
    @State var presentationTask: Task<Void, Never>?
    @FocusState var geometryField: CropGeometryField?

    init(
        item: WorkItem,
        initial: CanvasEdit,
        comparisonDividerPosition: CGFloat,
        comparisonDividerVisible: Bool,
        onDismissalStarted: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onApply: @escaping (CanvasEdit) -> Void
    ) {
        self.item = item
        self.comparisonDividerPosition = comparisonDividerPosition
        self.comparisonDividerVisible = comparisonDividerVisible
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
                // Match the normal comparison workspace exactly. The small
                // crop affordance margin belongs inside the canvas instead.
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
                    handoffProgress = 1
                    handoffVisible = false
                    workspacePresented = true
                    cropFramePresented = true
                    return
                }
                withAnimation(imageHandoffAnimation) {
                    imageLayoutProgress = 1
                    handoffProgress = 1
                }
                withAnimation(dimmingAnimation?.delay(0.035)) {
                    surfaceDimmed = true
                }
                withAnimation(chromeAnimation?.delay(0.035)) {
                    workspacePresented = true
                }
                withAnimation(cropFrameAnimation?.delay(0.15)) {
                    cropFramePresented = true
                }
                try? await Task.sleep(for: .milliseconds(270))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.08)) {
                    handoffVisible = false
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

    var sidebar: some View {
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
            .padding(14)
            .background(WorkspaceSurface.inspector)
            .overlay(alignment: .top) { Divider() }
            .opacity(workspacePresented ? 1 : 0)
            .offset(y: workspacePresented ? 0 : 16)
            .scaleEffect(workspacePresented ? 1 : 0.98, anchor: .bottom)
        }
        .background(WorkspaceSurface.inspector.opacity(workspacePresented ? 1 : 0))
        .animation(chromeAnimation, value: workspacePresented)
        .frame(width: 330)
    }

    var aspectControl: some View {
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

    var geometryControls: some View {
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

    func geometryTextField(
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

    var outsideImageControl: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Allow outside image")
                    .font(.subheadline.weight(.medium))
                Text("Adds transparent space beyond the edges.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Toggle("Allow outside image", isOn: outsideImageBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var outsideImageBinding: Binding<Bool> {
        Binding(
            get: { allowOutsideImage },
            set: { setAllowOutsideImage($0) }
        )
    }

    var currentEdit: CanvasEdit {
        CanvasEdit(
            canvas: canvas,
            aspect: aspect
        )
    }

    var editBinding: Binding<CanvasEdit> {
        Binding(
            get: { currentEdit },
            set: { apply($0) }
        )
    }

    func apply(_ edit: CanvasEdit) {
        canvas = edit.canvas
        aspect = edit.aspect
        if CropGeometry.extendsOutsideImage(edit.canvas) {
            allowOutsideImage = true
        }
    }

    func setAllowOutsideImage(_ allowed: Bool) {
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

    func commitGeometryField(_ field: CropGeometryField?) {
        guard let field else { return }
        switch field {
        case .width:
            guard let width = CropDimensionExpression.pixels(from: widthInput) else {
                synchronizeGeometryInputs(force: .width)
                return
            }
            resizeCrop(to: width, changing: .width)
        case .height:
            guard let height = CropDimensionExpression.pixels(from: heightInput) else {
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

    func resizeCrop(to outputPixels: Int, changing field: CropGeometryField) {
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

    func resizeCrop(toPercent requestedPercent: Double) {
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

    func referenceCropRect() -> CGRect {
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

    func cropSizePercentage() -> Double {
        guard baseImageRect.width > 0, baseImageRect.height > 0 else { return 100 }
        let reference = referenceCropRect()
        let current = CropGeometry.canvasRect(canvas, in: baseImageRect)
        let widthScale = max(current.width / reference.width, 0)
        let heightScale = max(current.height / reference.height, 0)
        return Double(sqrt(widthScale * heightScale) * 100)
    }

    func synchronizeGeometryInputs(force: CropGeometryField? = nil) {
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

}
