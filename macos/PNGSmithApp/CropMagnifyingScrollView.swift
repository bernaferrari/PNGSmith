import AppKit
import SwiftUI

struct NativeMagnifyingScrollView<Content: View>: NSViewRepresentable {
    @Binding var magnification: CGFloat
    private let content: Content

    init(
        magnification: Binding<CGFloat>,
        @ViewBuilder content: () -> Content
    ) {
        _magnification = magnification
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(magnification: $magnification)
    }

    func makeNSView(context: Context) -> CropMagnifyingScrollView<Content> {
        let hostingView = ArrowHostingView(rootView: content)
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = []

        let scrollView = CropMagnifyingScrollView(hostingView: hostingView)
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 1
        scrollView.maxMagnification = 4
        scrollView.magnificationChanged = { value in
            context.coordinator.updateBinding(value)
        }
        scrollView.documentView = hostingView
        context.coordinator.hostingView = hostingView
        return scrollView
    }

    func updateNSView(_ scrollView: CropMagnifyingScrollView<Content>, context: Context) {
        context.coordinator.magnification = $magnification
        context.coordinator.hostingView?.rootView = content
        scrollView.updateDocumentSize()
        scrollView.setMagnificationIfNeeded(magnification)
    }

    static func dismantleNSView(_ scrollView: CropMagnifyingScrollView<Content>, coordinator: Coordinator) {
        scrollView.magnificationChanged = nil
    }

    @MainActor
    final class Coordinator {
        var magnification: Binding<CGFloat>
        weak var hostingView: ArrowHostingView<Content>?

        init(magnification: Binding<CGFloat>) {
            self.magnification = magnification
        }

        func updateBinding(_ value: CGFloat) {
            let clamped = min(max(value, 1), 4)
            guard abs(magnification.wrappedValue - clamped) > 0.001 else { return }
            magnification.wrappedValue = clamped
        }
    }
}

final class CropMagnifyingScrollView<Content: View>: NSScrollView {
    let hostingView: ArrowHostingView<Content>
    var magnificationChanged: ((CGFloat) -> Void)?
    private var lastDocumentSize: CGSize = .zero

    init(hostingView: ArrowHostingView<Content>) {
        self.hostingView = hostingView
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateDocumentSize()
    }

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        magnificationChanged?(magnification)
    }

    func updateDocumentSize() {
        // The clip view's frame is the stable, unmagnified viewport. Its bounds
        // change while zooming, which would make the document subtly resize on
        // every magnification tick if used here.
        let size = contentView.frame.size
        guard size.width > 0, size.height > 0,
              abs(size.width - lastDocumentSize.width) > 0.5 || abs(size.height - lastDocumentSize.height) > 0.5 else {
            return
        }

        let oldSize = lastDocumentSize
        let oldVisible = documentVisibleRect
        let normalizedCenter = CGPoint(
            x: oldSize.width > 0 ? oldVisible.midX / oldSize.width : 0.5,
            y: oldSize.height > 0 ? oldVisible.midY / oldSize.height : 0.5
        )

        lastDocumentSize = size
        hostingView.frame = CGRect(origin: .zero, size: size)

        let center = CGPoint(
            x: size.width * normalizedCenter.x,
            y: size.height * normalizedCenter.y
        )
        setMagnification(magnification, centeredAt: center)
    }

    func setMagnificationIfNeeded(_ value: CGFloat) {
        let target = min(max(value, minMagnification), maxMagnification)
        guard abs(magnification - target) > 0.001 else { return }

        let visible = documentVisibleRect
        let center = CGPoint(x: visible.midX, y: visible.midY)
        setMagnification(target, centeredAt: center)
    }

}

final class ArrowHostingView<Content: View>: NSHostingView<Content> {
}
