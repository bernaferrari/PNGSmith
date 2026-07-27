import XCTest
@testable import PNGSmith

final class DocumentTabNavigationTests: XCTestCase {
    private let first = URL(fileURLWithPath: "/tmp/first.png")
    private let second = URL(fileURLWithPath: "/tmp/second.png")
    private let third = URL(fileURLWithPath: "/tmp/third.png")

    func testDraggingFirstTabOntoLastMovesItToTheRightmostPosition() {
        XCTAssertEqual(
            DocumentTabNavigation.reordered(
                [first, second, third],
                moving: first,
                to: third
            ),
            [second, third, first]
        )
    }

    func testDraggingLastTabOntoFirstMovesItToTheLeftmostPosition() {
        XCTAssertEqual(
            DocumentTabNavigation.reordered(
                [first, second, third],
                moving: third,
                to: first
            ),
            [third, first, second]
        )
    }

    func testClosingTheSelectedTabChoosesItsRightNeighbor() {
        let selection = DocumentTabNavigation.selection(
            afterRemoving: second,
            from: [first, second, third],
            selected: second
        )

        XCTAssertEqual(selection, third)
    }

    func testClosingTheLastSelectedTabChoosesItsLeftNeighbor() {
        let selection = DocumentTabNavigation.selection(
            afterRemoving: third,
            from: [first, second, third],
            selected: third
        )

        XCTAssertEqual(selection, second)
    }

    func testClosingABackgroundTabKeepsTheCurrentSelection() {
        let selection = DocumentTabNavigation.selection(
            afterRemoving: first,
            from: [first, second, third],
            selected: third
        )

        XCTAssertEqual(selection, third)
    }

    func testKeyboardNavigationWrapsInBothDirections() {
        let urls = [first, second, third]

        XCTAssertEqual(
            DocumentTabNavigation.selection(offset: 1, from: urls, selected: third),
            first
        )
        XCTAssertEqual(
            DocumentTabNavigation.selection(offset: -1, from: urls, selected: first),
            third
        )
    }
}
