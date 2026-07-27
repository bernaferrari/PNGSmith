import SwiftUI

// MARK: - Crop Canvas & Interaction

extension CropEditorWorkspace {
    var editorCanvas: some View {
        GeometryReader { proxy in
            ZStack {
                NativeMagnifyingScrollView(
                    magnification: $viewZoom
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
        let cropAffordanceMarginScale: CGFloat = allowOutsideImage ? 1 : 0.4
        let base = CropGeometry.imageRect(
            source: CGSize(width: item.pixelWidth, height: item.pixelHeight),
            available: size,
            allowsOutsideImage: allowOutsideImage,
            // Begin at the comparison geometry, then introduce only enough
            // internal space to make every crop edge easy to grab.
            marginScale: imageLayoutProgress * cropAffordanceMarginScale
        )
        let frame = CropGeometry.canvasRect(canvas, in: base)
        let editingBounds = allowOutsideImage ? workspace : base
        return ZStack {
            WorkspaceImageStage()
                .opacity(surfaceDimmed ? 1 : 0)

            imageSurface(frame: base)
                .opacity(handoffProgress)

            CropDimmingShape(imageRect: base, cutout: frame)
                .fill(.black.opacity(surfaceDimmed ? 0.62 : 0), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

            cropGrid(in: frame)
                .opacity(cropFramePresented ? 1 : 0)
                .allowsHitTesting(false)
            snapGuides(imageRect: base).allowsHitTesting(false)

            if handoffVisible, comparisonDividerVisible {
                ComparisonToCropHandoff(
                    cropRect: frame,
                    dividerPosition: comparisonDividerPosition,
                    progress: handoffProgress,
                    showsHandle: true
                )
                .transition(.opacity)
            }

            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                // Keep the move target away from the resize regions so a drag
                // near an edge can never be claimed as a crop move.
                .frame(
                    width: max(frame.width - CropGeometry.moveHitInset * 2, 1),
                    height: max(frame.height - CropGeometry.moveHitInset * 2, 1)
                )
                .position(x: frame.midX, y: frame.midY)
                .gesture(canvasMoveGesture(base: base, workspace: editingBounds))
                .allowsHitTesting(workspacePresented)

            ForEach(CropHandle.edges, id: \.self) { handle in
                handleView(handle, frame: frame, base: base, workspace: editingBounds)
                    .opacity(cropFramePresented ? 1 : 0)
                    .allowsHitTesting(cropFramePresented)
            }

            // Corners sit above the edge hit regions so diagonal resizing wins
            // where the two affordances overlap.
            ForEach(CropHandle.corners, id: \.self) { handle in
                handleView(handle, frame: frame, base: base, workspace: editingBounds)
                    .opacity(cropFramePresented ? 1 : 0)
                    .allowsHitTesting(cropFramePresented)
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
                } else if let handle = CropGeometry.handle(at: location, frame: frame) {
                    handle.cursor.set()
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
                .tint(Color.accentColor)
                .background {
                    Capsule()
                        .fill(Color.secondary.opacity(0.32))
                        .frame(height: 3)
                        .padding(.horizontal, 2)
                }
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
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .controlSize(.small)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.42))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
    }

    private func adjustViewZoom(by amount: CGFloat) {
        setViewZoom(viewZoom + amount)
    }

    private func setViewZoom(_ value: CGFloat) {
        viewZoom = min(max(value, 1), 4)
    }

    var aspectAnimation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.34, bounce: 0.1)
    }

    var imageHandoffAnimation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.06)
    }

    var dimmingAnimation: Animation? {
        reduceMotion ? nil : .timingCurve(0.77, 0, 0.175, 1, duration: 0.18)
    }

    var chromeAnimation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.08)
    }

    var cropFrameAnimation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.2, bounce: 0.04)
    }

    func dismiss(after completion: @escaping () -> Void) {
        guard !isDismissing else { return }
        isDismissing = true
        presentationTask?.cancel()
        onDismissalStarted()

        if reduceMotion {
            workspacePresented = false
            cropFramePresented = false
            surfaceDimmed = false
            imageLayoutProgress = 0
            handoffProgress = 0
            completion()
            return
        }

        handoffVisible = true
        withAnimation(cropFrameAnimation) {
            cropFramePresented = false
        }
        withAnimation(chromeAnimation) {
            workspacePresented = false
        }
        withAnimation(dimmingAnimation) {
            surfaceDimmed = false
        }
        withAnimation(imageHandoffAnimation) {
            imageLayoutProgress = 0
            handoffProgress = 0
        }
        presentationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(310))
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

    func fittedCanvas(for ratio: Double) -> NormalizedCrop {
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

// MARK: - Crop Overlay Primitives

typealias CropRectAnimationData = AnimatablePair<
    AnimatablePair<CGFloat, CGFloat>,
    AnimatablePair<CGFloat, CGFloat>
>
typealias CropDimmingAnimationData = AnimatablePair<
    CropRectAnimationData,
    CropRectAnimationData
>
typealias CropHandoffAnimationData = AnimatablePair<
    CropRectAnimationData,
    AnimatablePair<CGFloat, CGFloat>
>

/// Morphs the comparison divider into the crop boundary so entering the crop
/// tool reads as a change of mode on the same image, rather than a new screen.
struct ComparisonToCropShape: Shape {
    var cropRect: CGRect
    var dividerX: CGFloat
    var progress: CGFloat

    var animatableData: CropHandoffAnimationData {
        get {
            CropHandoffAnimationData(
                CropRectAnimationData(
                    AnimatablePair(cropRect.origin.x, cropRect.origin.y),
                    AnimatablePair(cropRect.size.width, cropRect.size.height)
                ),
                AnimatablePair(dividerX, progress)
            )
        }
        set {
            cropRect = CGRect(
                x: newValue.first.first.first,
                y: newValue.first.first.second,
                width: newValue.first.second.first,
                height: newValue.first.second.second
            )
            dividerX = newValue.second.first
            progress = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let amount = min(max(progress, 0), 1)
        let left = mix(dividerX, cropRect.minX, amount)
        let right = mix(dividerX, cropRect.maxX, amount)
        let top = mix(rect.minY, cropRect.minY, amount)
        let bottom = mix(rect.maxY, cropRect.maxY, amount)

        var path = Path()
        path.move(to: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: left, y: bottom))
        path.closeSubpath()
        return path
    }

    private func mix(_ start: CGFloat, _ end: CGFloat, _ amount: CGFloat) -> CGFloat {
        start + (end - start) * amount
    }
}

struct ComparisonToCropHandoff: View {
    let cropRect: CGRect
    let dividerPosition: CGFloat
    let progress: CGFloat
    let showsHandle: Bool

    var body: some View {
        GeometryReader { proxy in
            let dividerX = proxy.size.width * dividerPosition
            let handleProgress = min(max(progress, 0), 1)

            ZStack {
                ComparisonToCropShape(
                    cropRect: cropRect,
                    dividerX: dividerX,
                    progress: progress
                )
                .stroke(
                    Color.white.opacity(0.9),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: .black.opacity(0.38), radius: 2)

                if showsHandle {
                    Circle()
                        .fill(.white)
                        .frame(width: 30, height: 30)
                        .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
                        .overlay {
                            Image(systemName: "arrow.left.and.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.7))
                        }
                        .scaleEffect(1 - handleProgress * 0.18)
                        .opacity(1 - handleProgress)
                        .position(
                            x: dividerX,
                            y: mix(
                                proxy.size.height / 2,
                                proxy.size.height + 22,
                                handleProgress
                            )
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func mix(_ start: CGFloat, _ end: CGFloat, _ amount: CGFloat) -> CGFloat {
        start + (end - start) * amount
    }
}

struct CropDimmingShape: Shape {
    var imageRect: CGRect
    var cutout: CGRect

    var animatableData: CropDimmingAnimationData {
        get {
            CropDimmingAnimationData(
                CropRectAnimationData(
                    AnimatablePair(imageRect.origin.x, imageRect.origin.y),
                    AnimatablePair(imageRect.size.width, imageRect.size.height)
                ),
                CropRectAnimationData(
                    AnimatablePair(cutout.origin.x, cutout.origin.y),
                    AnimatablePair(cutout.size.width, cutout.size.height)
                )
            )
        }
        set {
            imageRect = CGRect(
                x: newValue.first.first.first,
                y: newValue.first.first.second,
                width: newValue.first.second.first,
                height: newValue.first.second.second
            )
            cutout = CGRect(
                x: newValue.second.first.first,
                y: newValue.second.first.second,
                width: newValue.second.second.first,
                height: newValue.second.second.second
            )
        }
    }

    func path(in _: CGRect) -> Path {
        var path = Path()
        path.addRect(imageRect)
        let visibleImage = imageRect.intersection(cutout)
        if !visibleImage.isNull, !visibleImage.isEmpty {
            path.addRect(visibleImage)
        }
        return path
    }
}

struct CropRectShape: Shape {
    enum Kind {
        case grid, border, corners
    }

    var cropRect: CGRect
    let kind: Kind

    var animatableData: CropRectAnimationData {
        get {
            CropRectAnimationData(
                AnimatablePair(cropRect.origin.x, cropRect.origin.y),
                AnimatablePair(cropRect.size.width, cropRect.size.height)
            )
        }
        set {
            cropRect = CGRect(
                x: newValue.first.first,
                y: newValue.first.second,
                width: newValue.second.first,
                height: newValue.second.second
            )
        }
    }

    func path(in _: CGRect) -> Path {
        var path = Path()
        switch kind {
        case .grid:
            for fraction in [1.0 / 3.0, 2.0 / 3.0] {
                let x = cropRect.minX + cropRect.width * fraction
                path.move(to: CGPoint(x: x, y: cropRect.minY))
                path.addLine(to: CGPoint(x: x, y: cropRect.maxY))
                let y = cropRect.minY + cropRect.height * fraction
                path.move(to: CGPoint(x: cropRect.minX, y: y))
                path.addLine(to: CGPoint(x: cropRect.maxX, y: y))
            }
        case .border:
            path.addRect(cropRect)
        case .corners:
            let length = min(20, max(12, min(cropRect.width, cropRect.height) * 0.12))
            path.move(to: CGPoint(x: cropRect.minX, y: cropRect.minY + length))
            path.addLine(to: CGPoint(x: cropRect.minX, y: cropRect.minY))
            path.addLine(to: CGPoint(x: cropRect.minX + length, y: cropRect.minY))
            path.move(to: CGPoint(x: cropRect.maxX - length, y: cropRect.minY))
            path.addLine(to: CGPoint(x: cropRect.maxX, y: cropRect.minY))
            path.addLine(to: CGPoint(x: cropRect.maxX, y: cropRect.minY + length))
            path.move(to: CGPoint(x: cropRect.minX, y: cropRect.maxY - length))
            path.addLine(to: CGPoint(x: cropRect.minX, y: cropRect.maxY))
            path.addLine(to: CGPoint(x: cropRect.minX + length, y: cropRect.maxY))
            path.move(to: CGPoint(x: cropRect.maxX - length, y: cropRect.maxY))
            path.addLine(to: CGPoint(x: cropRect.maxX, y: cropRect.maxY))
            path.addLine(to: CGPoint(x: cropRect.maxX, y: cropRect.maxY - length))
        }
        return path
    }
}

struct AnimatedCropGrid: View {
    let rect: CGRect
    let emphasized: Bool

    var body: some View {
        ZStack {
            CropRectShape(cropRect: rect, kind: .grid)
            .stroke(.white.opacity(0.23), lineWidth: 0.75)

            CropRectShape(cropRect: rect, kind: .border)
                .stroke(.white.opacity(emphasized ? 0.88 : 0.7), lineWidth: 1)

            CropRectShape(cropRect: rect, kind: .corners)
                .stroke(
                    .white,
                    style: StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: .black.opacity(0.45), radius: 1)

            edgeHandleBars
        }
    }

    private var edgeHandleBars: some View {
        ZStack {
            Capsule().fill(.white).frame(width: 28, height: 3)
                .position(x: rect.midX, y: rect.minY)
            Capsule().fill(.white).frame(width: 28, height: 3)
                .position(x: rect.midX, y: rect.maxY)
            Capsule().fill(.white).frame(width: 3, height: 28)
                .position(x: rect.minX, y: rect.midY)
            Capsule().fill(.white).frame(width: 3, height: 28)
                .position(x: rect.maxX, y: rect.midY)
        }
        .shadow(color: .black.opacity(0.45), radius: 1)
    }
}
