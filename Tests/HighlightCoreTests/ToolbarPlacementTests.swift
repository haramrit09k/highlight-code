@testable import HighlightCore
import XCTest

final class ToolbarPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 875) // minus the menu bar
    private let size = CGSize(width: 200, height: 36)

    private func frame(_ selection: CGRect, edge: ToolbarPlacement.Edge = .below, visibleFrame: CGRect? = nil) -> CGRect {
        ToolbarPlacement.frame(
            forSelection: selection, primaryScreenHeight: screen.height,
            visibleFrame: visibleFrame ?? visible, size: size, edge: edge
        )
    }

    func testBelowSelectionByDefault() {
        // Selection 300pt from the top of the screen, 40pt tall: its bottom is at AppKit y 560.
        XCTAssertEqual(frame(CGRect(x: 200, y: 300, width: 400, height: 40)),
                       CGRect(x: 200, y: 560 - 8 - 36, width: 200, height: 36))
    }

    func testAboveSelectionWhenPreferred() {
        XCTAssertEqual(frame(CGRect(x: 200, y: 300, width: 400, height: 40), edge: .above),
                       CGRect(x: 200, y: 600 + 8, width: 200, height: 36))
    }

    func testFlipsAboveWhenNoRoomBelow() {
        let result = frame(CGRect(x: 200, y: 820, width: 400, height: 40))
        XCTAssertEqual(result.minY, 900 - 820 + 8)
    }

    func testFlipsBelowWhenNoRoomAbove() {
        let result = frame(CGRect(x: 200, y: 30, width: 400, height: 40), edge: .above)
        XCTAssertEqual(result.maxY, 900 - 70 - 8)
    }

    func testKeptInsideScreenHorizontally() {
        XCTAssertEqual(frame(CGRect(x: 1400, y: 300, width: 30, height: 20)).maxX, 1440 - 8)
    }

    func testSelectionTallerThanScreenStaysOnScreen() {
        let result = frame(CGRect(x: 100, y: -100, width: 300, height: 1200))
        XCTAssertTrue(visible.contains(result), "\(result)")
    }

    func testSecondaryScreenAbovePrimary() {
        // A screen stacked above the primary one has AppKit y >= 900 and negative AX y.
        let upper = CGRect(x: 0, y: 900, width: 1920, height: 1080)
        let result = frame(CGRect(x: 100, y: -500, width: 200, height: 20), visibleFrame: upper)
        XCTAssertEqual(result.origin, CGPoint(x: 100, y: 900 + 480 - 8 - 36))
    }
}
