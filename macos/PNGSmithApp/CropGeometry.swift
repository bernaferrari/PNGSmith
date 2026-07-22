import CoreGraphics

enum CropGeometry {
    static func extendsOutsideImage(_ crop: NormalizedCrop) -> Bool {
        let tolerance = 0.000_1
        return crop.x < -tolerance
            || crop.y < -tolerance
            || crop.x + crop.width > 1 + tolerance
            || crop.y + crop.height > 1 + tolerance
    }

    static func fit(_ rect: CGRect, inside bounds: CGRect) -> CGRect {
        var result = rect
        let scale = min(1, bounds.width / result.width, bounds.height / result.height)
        if scale < 1 {
            let anchor = result.center
            result.size.width *= scale
            result.size.height *= scale
            result.origin = CGPoint(
                x: anchor.x - result.width / 2,
                y: anchor.y - result.height / 2
            )
        }
        if result.minX < bounds.minX { result.origin.x = bounds.minX }
        if result.maxX > bounds.maxX { result.origin.x = bounds.maxX - result.width }
        if result.minY < bounds.minY { result.origin.y = bounds.minY }
        if result.maxY > bounds.maxY { result.origin.y = bounds.maxY - result.height }
        return result
    }

    static func imageRect(
        source: CGSize,
        available: CGSize,
        allowsOutsideImage: Bool,
        marginScale: CGFloat = 1
    ) -> CGRect {
        guard source.width > 0, source.height > 0 else { return .zero }
        let shortestSide = min(available.width, available.height)
        let standardMargin = min(max(shortestSide * 0.035, 18), 36)
        let outsideMargin = min(max(shortestSide * 0.12, 44), 96)
        let resolvedMarginScale = min(max(marginScale, 0), 1)
        let margin = (allowsOutsideImage ? outsideMargin : standardMargin) * resolvedMarginScale
        let usable = CGSize(
            width: max(available.width - margin * 2, 1),
            height: max(available.height - margin * 2, 1)
        )
        let scale = min(usable.width / source.width, usable.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(
            x: (available.width - size.width) / 2,
            y: (available.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    static func canvasRect(_ value: NormalizedCrop, in base: CGRect) -> CGRect {
        CGRect(
            x: base.minX + CGFloat(value.x) * base.width,
            y: base.minY + CGFloat(value.y) * base.height,
            width: CGFloat(value.width) * base.width,
            height: CGFloat(value.height) * base.height
        )
    }

    static func normalizedCanvas(_ rect: CGRect, in base: CGRect) -> NormalizedCrop {
        NormalizedCrop(
            x: Double((rect.minX - base.minX) / base.width),
            y: Double((rect.minY - base.minY) / base.height),
            width: Double(rect.width / base.width),
            height: Double(rect.height / base.height)
        )
    }

    static func nearestSnap(
        candidates: [(offset: CGFloat, guide: CGFloat)],
        threshold: CGFloat
    ) -> (offset: CGFloat, guide: CGFloat)? {
        candidates
            .filter { abs($0.offset) < threshold }
            .min { abs($0.offset) < abs($1.offset) }
    }

    static func hitSize(for handle: CropHandle, frame: CGRect) -> CGSize {
        switch handle {
        case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing:
            CGSize(width: 24, height: 24)
        case .top, .bottom:
            CGSize(width: frame.width, height: 16)
        case .leading, .trailing:
            CGSize(width: 16, height: frame.height)
        }
    }

    static func handle(at location: CGPoint, frame: CGRect) -> CropHandle? {
        for handle in CropHandle.corners + CropHandle.edges {
            let size = hitSize(for: handle, frame: frame)
            let center = point(for: handle, in: frame)
            let hitRect = CGRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            if hitRect.contains(location) { return handle }
        }
        return nil
    }

    static func point(for handle: CropHandle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeading: CGPoint(x: rect.minX, y: rect.minY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .topTrailing: CGPoint(x: rect.maxX, y: rect.minY)
        case .leading: CGPoint(x: rect.minX, y: rect.midY)
        case .trailing: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeading: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomTrailing: CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    static func oppositePoint(for handle: CropHandle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeading: CGPoint(x: rect.maxX, y: rect.maxY)
        case .top: CGPoint(x: rect.midX, y: rect.maxY)
        case .topTrailing: CGPoint(x: rect.minX, y: rect.maxY)
        case .leading: CGPoint(x: rect.maxX, y: rect.midY)
        case .trailing: CGPoint(x: rect.minX, y: rect.midY)
        case .bottomLeading: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottom: CGPoint(x: rect.midX, y: rect.minY)
        case .bottomTrailing: CGPoint(x: rect.minX, y: rect.minY)
        }
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
