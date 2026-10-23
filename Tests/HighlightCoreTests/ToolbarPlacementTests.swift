@testable import HighlightCore
import XCTest

final class ToolbarPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 875) // minus the menu bar
    private let size = CGSize(width: 140, height: 32)

    func testPlacedAboveSelection() {
        // Selection 300pt from the top of the screen, 40pt tall.
        let frame = ToolbarPlacement.frame(
            forSelection: CGRect(x: 200, y: 300, width: 400, height: 40),
            primaryScreenHeight: screen.height, visibleFrame: visible, size: size
        )
        XCTAssertEqual(frame, CGRect(x: 200, y: 900 - 300 + 8, width: 140, height: 32))
    }

    func testFlipsBelowWhenNoRoomAbove() {
        let frame = ToolbarPlacement.frame(
            forSelection: CGRect(x: 200, y: 30, width: 400, height: 40),
            primaryScreenHeight: screen.height, visibleFrame: visible, size: size
        )
        XCTAssertEqual(frame.maxY, 900 - 70 - 8)
    }

    func testKeptInsideScreenHorizontally() {
        let frame = ToolbarPlacement.frame(
            forSelection: CGRect(x: 1400, y: 300, width: 30, height: 20),
            primaryScreenHeight: screen.height, visibleFrame: visible, size: size
        )
        XCTAssertEqual(frame.maxX, 1440 - 8)
    }

    func testSecondaryScreenAbovePrimary() {
        // A screen stacked above the primary one has AppKit y >= 900 and negative AX y.
        let upper = CGRect(x: 0, y: 900, width: 1920, height: 1080)
        let frame = ToolbarPlacement.frame(
            forSelection: CGRect(x: 100, y: -500, width: 200, height: 20),
            primaryScreenHeight: screen.height, visibleFrame: upper, size: size
        )
        XCTAssertEqual(frame.origin, CGPoint(x: 100, y: 900 + 500 + 8))
    }
}
