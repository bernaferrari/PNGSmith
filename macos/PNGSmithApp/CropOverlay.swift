import SwiftUI

typealias CropRectAnimationData = AnimatablePair<
    AnimatablePair<CGFloat, CGFloat>,
    AnimatablePair<CGFloat, CGFloat>
>
typealias CropDimmingAnimationData = AnimatablePair<
    CropRectAnimationData,
    CropRectAnimationData
>

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
