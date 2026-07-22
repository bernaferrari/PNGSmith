import Foundation

struct NormalizedCrop: Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let full = NormalizedCrop(x: 0, y: 0, width: 1, height: 1)
}

/// A transparent output canvas positioned relative to the source image.
struct CanvasEdit: Hashable, Sendable {
    var canvas: NormalizedCrop
    var aspect: CropAspect

    static let full = CanvasEdit(canvas: .full, aspect: .free)

    var isIdentity: Bool {
        abs(canvas.x) < 0.000_1 && abs(canvas.y) < 0.000_1
            && abs(canvas.width - 1) < 0.000_1 && abs(canvas.height - 1) < 0.000_1
    }

    func pixelOptions(imageWidth: Int, imageHeight: Int) -> CanvasOptions {
        let outputWidth = max(Int((canvas.width * Double(imageWidth)).rounded()), 1)
        let outputHeight = max(Int((canvas.height * Double(imageHeight)).rounded()), 1)
        return CanvasOptions(
            width: outputWidth,
            height: outputHeight,
            imageScale: 1,
            imageOffsetX: Int((-canvas.x * Double(imageWidth)).rounded()),
            imageOffsetY: Int((-canvas.y * Double(imageHeight)).rounded())
        )
    }
}

enum CropAspect: String, CaseIterable, Identifiable, Sendable {
    case free = "Free"
    case square = "Square"
    case fourThree = "4:3"
    case sixteenNine = "16:9"
    case twoOne = "2:1"

    var id: Self { self }

    var ratio: Double? {
        switch self {
        case .free: nil
        case .square: 1
        case .fourThree: 4.0 / 3.0
        case .sixteenNine: 16.0 / 9.0
        case .twoOne: 2
        }
    }
}
