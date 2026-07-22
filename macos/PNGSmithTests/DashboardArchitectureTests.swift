import XCTest
@testable import PNGSmith

final class DashboardArchitectureTests: XCTestCase {
    func testAnimatedItemsAlwaysResolveToLosslessMode() {
        let item = WorkItem(
            url: URL(fileURLWithPath: "/tmp/animated.png"),
            securityScoped: false,
            originalBytes: 100,
            pixelWidth: 10,
            pixelHeight: 10,
            frameCount: 2
        )

        XCTAssertTrue(item.isAnimated)
        XCTAssertEqual(item.supportedMode(requested: .shrink), .auto)
    }

    func testStillItemsKeepTheRequestedMode() {
        let item = WorkItem(
            url: URL(fileURLWithPath: "/tmp/still.png"),
            securityScoped: false,
            originalBytes: 100,
            pixelWidth: 10,
            pixelHeight: 10,
            frameCount: 1
        )

        XCTAssertFalse(item.isAnimated)
        XCTAssertEqual(item.supportedMode(requested: .shrink), .shrink)
    }

    func testSaveSummarySeparatesWrittenSkippedAndFailedResults() {
        let summary = SaveSummary(results: [
            result(written: true, original: 100, output: 60, error: nil),
            result(written: false, original: 100, output: 110, error: nil),
            result(written: false, original: nil, output: nil, error: "failed"),
        ])

        XCTAssertEqual(summary.writtenCount, 1)
        XCTAssertEqual(summary.skippedCount, 1)
        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertEqual(summary.savedBytes, 40)
    }

    func testAutoSaveRequestCarriesCanvasEditToTheCore() async throws {
        let item = WorkItem(
            url: URL(fileURLWithPath: "/tmp/still.png"),
            securityScoped: false,
            originalBytes: 100,
            pixelWidth: 10,
            pixelHeight: 10,
            frameCount: 1
        )
        let canvas = CanvasOptions(
            width: 20,
            height: 20,
            imageScale: 1,
            imageOffsetX: 5,
            imageOffsetY: 5
        )
        let settings = PNGSmithSettings()
        let variant = PreviewVariant(
            mode: .auto,
            maxColors: 256,
            settings: settings,
            crop: canvas
        )

        let request = try await DashboardSavePipeline.request(
            item: item,
            mode: .auto,
            variant: variant,
            settings: settings
        )

        XCTAssertEqual(request.mode, "smart_lossless")
        XCTAssertEqual(request.canvas, canvas)
        XCTAssertTrue(request.output.onlyIfSmaller)

        let encoded = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNotNil(json["canvas"], "Canvas edits must cross the Swift/Rust JSON boundary")
    }

    func testAutomaticPaletteRequestIsDelegatedToRust() async throws {
        let item = WorkItem(
            url: URL(fileURLWithPath: "/tmp/still.png"),
            securityScoped: false,
            originalBytes: 100,
            pixelWidth: 10,
            pixelHeight: 10,
            frameCount: 1
        )
        let settings = PNGSmithSettings()
        let variant = PreviewVariant(
            mode: .shrink,
            maxColors: 32,
            settings: settings,
            automaticStrategy: "smaller"
        )

        let request = try await DashboardSavePipeline.request(
            item: item,
            mode: .shrink,
            variant: variant,
            settings: settings
        )

        XCTAssertEqual(request.mode, "automatic_palette")
        XCTAssertEqual(request.maxColors, 256)
        XCTAssertEqual(request.automatic.strategy, "smaller")
    }

    private func result(
        written: Bool,
        original: UInt64?,
        output: UInt64?,
        error: String?
    ) -> PNGSmithResult {
        PNGSmithResult(
            input: "/tmp/input.png",
            output: written ? "/tmp/output.png" : nil,
            originalBytes: original,
            outputBytes: output,
            actualMode: nil,
            paletteEntries: nil,
            colorBudget: nil,
            pixelIdentical: nil,
            lossy: false,
            written: written,
            skippedReason: written || error != nil ? nil : "not smaller",
            error: error
        )
    }
}
