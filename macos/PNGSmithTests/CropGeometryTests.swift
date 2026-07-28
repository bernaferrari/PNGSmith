import XCTest
@testable import PNGSmith

final class CropGeometryTests: XCTestCase {
    func testCanvasEditConvertsNormalizedCoordinatesToPixels() {
        let edit = CanvasEdit(
            canvas: NormalizedCrop(x: -0.1, y: 0.25, width: 0.5, height: 0.75),
            aspect: .free
        )

        let options = edit.pixelOptions(imageWidth: 1_000, imageHeight: 800)

        XCTAssertEqual(options.width, 500)
        XCTAssertEqual(options.height, 600)
        XCTAssertEqual(options.imageOffsetX, 100)
        XCTAssertEqual(options.imageOffsetY, -200)
    }

    func testFitPreservesCenterAndConstrainsRectangle() {
        let result = CropGeometry.fit(
            CGRect(x: -20, y: -10, width: 200, height: 100),
            inside: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        XCTAssertEqual(result, CGRect(x: 0, y: 15, width: 100, height: 50))
    }

    func testRoundTripBetweenNormalizedAndDisplayCoordinates() {
        let base = CGRect(x: 40, y: 20, width: 800, height: 600)
        let normalized = NormalizedCrop(x: 0.1, y: 0.2, width: 0.5, height: 0.4)

        let display = CropGeometry.canvasRect(normalized, in: base)
        let roundTrip = CropGeometry.normalizedCanvas(display, in: base)

        XCTAssertEqual(roundTrip.x, normalized.x, accuracy: 0.000_001)
        XCTAssertEqual(roundTrip.y, normalized.y, accuracy: 0.000_001)
        XCTAssertEqual(roundTrip.width, normalized.width, accuracy: 0.000_001)
        XCTAssertEqual(roundTrip.height, normalized.height, accuracy: 0.000_001)
    }

    func testZoomedHandleHitTargetsKeepTheirScreenSize() {
        let frame = CGRect(x: 20, y: 20, width: 400, height: 300)
        let normal = CropGeometry.hitSize(for: .topLeading, frame: frame, viewScale: 1)
        let zoomed = CropGeometry.hitSize(for: .topLeading, frame: frame, viewScale: 2)

        XCTAssertEqual(zoomed.width * 2, normal.width)
        XCTAssertEqual(zoomed.height * 2, normal.height)
    }

    func testOutsideImageDetection() {
        XCTAssertFalse(CropGeometry.extendsOutsideImage(.full))
        XCTAssertTrue(CropGeometry.extendsOutsideImage(
            NormalizedCrop(x: -0.01, y: 0, width: 1, height: 1)
        ))
    }

    func testImageRectLeavesAVisibleWorkspaceMargin() {
        let rect = CropGeometry.imageRect(
            source: CGSize(width: 1_600, height: 900),
            available: CGSize(width: 1_200, height: 800),
            allowsOutsideImage: false
        )

        XCTAssertGreaterThan(rect.minX, 0)
        XCTAssertGreaterThan(rect.minY, 0)
        XCTAssertLessThan(rect.maxX, 1_200)
        XCTAssertLessThan(rect.maxY, 800)
    }

    func testImageRectCanMatchTheEdgeToEdgePreviewDuringHandoff() {
        let rect = CropGeometry.imageRect(
            source: CGSize(width: 1_600, height: 900),
            available: CGSize(width: 1_200, height: 800),
            allowsOutsideImage: false,
            marginScale: 0
        )

        XCTAssertEqual(rect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(rect.width, 1_200, accuracy: 0.001)
        XCTAssertEqual(rect.midY, 400, accuracy: 0.001)
    }
}
