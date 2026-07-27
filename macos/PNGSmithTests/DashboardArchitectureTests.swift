import XCTest
@testable import PNGSmith

final class DashboardArchitectureTests: XCTestCase {
    func testCropDimensionsAcceptSafeArithmeticExpressions() {
        XCTAssertEqual(CropDimensionExpression.pixels(from: "1000*0.3"), 300)
        XCTAssertEqual(CropDimensionExpression.pixels(from: "1920 / 2"), 960)
        XCTAssertEqual(CropDimensionExpression.pixels(from: "(800 + 40) / 3"), 280)
        XCTAssertEqual(CropDimensionExpression.pixels(from: "1000×0,3"), 300)
    }

    func testCropDimensionsRejectInvalidArithmeticExpressions() {
        XCTAssertNil(CropDimensionExpression.pixels(from: "1000 / 0"))
        XCTAssertNil(CropDimensionExpression.pixels(from: "1000 *"))
        XCTAssertNil(CropDimensionExpression.pixels(from: "-20"))
        XCTAssertNil(CropDimensionExpression.pixels(from: "print(1000)"))
    }

    func testCropToolLifecycleKeepsItsDocumentIdentityUntilClosed() {
        let url = URL(fileURLWithPath: "/tmp/example.png")
        var state = CropToolState.inactive

        state.present(url)
        XCTAssertEqual(state.itemURL, url)
        XCTAssertTrue(state.showsChrome)

        state.beginDismissal()
        XCTAssertEqual(state.itemURL, url)
        XCTAssertFalse(state.showsChrome)
        XCTAssertTrue(state.isActive)

        state.close()
        XCTAssertNil(state.itemURL)
        XCTAssertFalse(state.isActive)
    }

    func testCropToolIgnoresDismissalOutsidePresentedState() {
        let url = URL(fileURLWithPath: "/tmp/example.png")
        var state = CropToolState.inactive

        state.beginDismissal()
        XCTAssertEqual(state, .inactive)

        state.present(url)
        state.beginDismissal()
        state.beginDismissal()
        XCTAssertEqual(state, .dismissing(url))
    }

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
        XCTAssertEqual(summary.totalCount, 3)
        XCTAssertEqual(summary.savedBytes, 40)
    }

    func testBatchCanSaveOnlyWhenEveryPreviewIsReady() {
        let pending = PreviewBatchStatus(states: [.ready, .pending])
        let failed = PreviewBatchStatus(states: [.ready, .failed])
        let ready = PreviewBatchStatus(states: [.ready, .ready])

        XCTAssertFalse(pending.canSave)
        XCTAssertTrue(pending.isPending)
        XCTAssertFalse(failed.canSave)
        XCTAssertEqual(failed.failedCount, 1)
        XCTAssertTrue(ready.canSave)
        XCTAssertFalse(ready.isPending)
    }

    func testPreviewPhaseOnlyShowsInitialLoadingWithoutCachedResult() {
        let outcome = PreviewOutcome(
            outputURL: URL(fileURLWithPath: "/tmp/output.png"),
            comparisonSourceURL: URL(fileURLWithPath: "/tmp/source.png"),
            originalBytes: 100,
            outputBytes: 60,
            actualMode: "lossless",
            paletteEntries: nil,
            colorBudget: nil,
            sourceColors: nil,
            sourceColorsAtLeast: nil,
            lossy: false,
            neededColors: nil
        )

        XCTAssertTrue(PreviewPhase.loading(previous: nil).isInitialLoading)
        XCTAssertFalse(PreviewPhase.loading(previous: outcome).isInitialLoading)
        XCTAssertEqual(PreviewPhase.loading(previous: outcome).lastKnownOutcome, outcome)
    }

    func testReplacementRiskReflectsFinishedPerImageEdits() {
        XCTAssertEqual(
            ReplacementRisk(hasCropEdits: false, hasLossyPreviews: false),
            .none
        )
        XCTAssertEqual(
            ReplacementRisk(hasCropEdits: true, hasLossyPreviews: false),
            .crop
        )
        XCTAssertEqual(
            ReplacementRisk(hasCropEdits: false, hasLossyPreviews: true),
            .colorReduction
        )
        XCTAssertEqual(
            ReplacementRisk(hasCropEdits: true, hasLossyPreviews: true),
            .cropAndColorReduction
        )
    }

    func testPerImageOptimizationDerivesItsOwnMode() {
        let lossless = ImageOptimizationSettings(
            reduceColors: false,
            maxColors: 32,
            autoColors: true,
            autoStrategy: .smaller
        )
        var reduced = lossless
        reduced.reduceColors = true

        XCTAssertEqual(lossless.mode, .auto)
        XCTAssertEqual(reduced.mode, .shrink)
        XCTAssertEqual(reduced.maxColors, 32)
        XCTAssertEqual(reduced.autoStrategy, .smaller)
    }

    func testColorReductionPresetsHaveOneCanonicalTransition() {
        var optimization = ImageOptimizationSettings(
            reduceColors: false,
            maxColors: 81,
            autoColors: false,
            autoStrategy: .balanced
        )

        optimization.apply(.smaller)
        XCTAssertTrue(optimization.reduceColors)
        XCTAssertTrue(optimization.autoColors)
        XCTAssertEqual(optimization.autoStrategy, .smaller)
        XCTAssertEqual(optimization.colorReductionPreset, .smaller)

        optimization.applyManualColorCount(512)
        XCTAssertEqual(optimization.maxColors, 256)
        XCTAssertEqual(optimization.colorReductionPreset, .manual)
    }

    func testUniformDisabledBatchIsNotReportedAsMixed() {
        let disabled = ImageOptimizationSettings(
            reduceColors: false,
            maxColors: 256,
            autoColors: true,
            autoStrategy: .balanced
        )

        let summary = OptimizationGroupSummary([disabled, disabled])
        XCTAssertFalse(summary.colorReductionEnabled)
        XCTAssertNil(summary.preset)
        XCTAssertNil(summary.status)
    }

    func testBatchSummaryDistinguishesUniformAndMixedManualCounts() {
        let first = ImageOptimizationSettings(
            reduceColors: true,
            maxColors: 64,
            autoColors: false,
            autoStrategy: .balanced
        )
        var second = first

        XCTAssertEqual(OptimizationGroupSummary([first, second]).manualColorCount, 64)
        XCTAssertNil(OptimizationGroupSummary([first, second]).status)

        second.maxColors = 32
        let mixed = OptimizationGroupSummary([first, second])
        XCTAssertNil(mixed.manualColorCount)
        XCTAssertEqual(mixed.status, "Mixed")
    }

    func testPerImageOptimizationCanBePersisted() throws {
        let value = ImageOptimizationSettings(
            reduceColors: true,
            maxColors: 81,
            autoColors: false,
            autoStrategy: .balanced
        )

        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(ImageOptimizationSettings.self, from: data), value)
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
        XCTAssertTrue(request.lossless.preserveTransparentRGB)

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
        XCTAssertTrue(request.automatic.protectExistingPalette)
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
            sourceColors: nil,
            sourceColorsAtLeast: nil,
            pixelIdentical: nil,
            lossy: false,
            written: written,
            skippedReason: written || error != nil ? nil : "not smaller",
            error: error
        )
    }
}
