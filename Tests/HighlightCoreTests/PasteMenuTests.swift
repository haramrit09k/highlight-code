@testable import HighlightCore
import XCTest

final class PasteMenuTests: XCTestCase {
    /// Notes' Edit menu on macOS 26, as reported by Accessibility in a user's log
    /// (items without a shortcut report modifiers 8, "no ⌘").
    private let notesEditMenu = [
        PasteMenu.Item(title: "Undo Typing", key: "Z"),
        PasteMenu.Item(title: "Redo Typing", key: "Z", modifiers: 1),
        PasteMenu.Item(title: " ", modifiers: 8),
        PasteMenu.Item(title: "Cut", key: "X"),
        PasteMenu.Item(title: "Copy", key: "C"),
        PasteMenu.Item(title: "Paste", key: "V"),
        PasteMenu.Item(title: "Paste and Match Style", key: "V", modifiers: 3),
        PasteMenu.Item(title: "Paste and Retain Style", modifiers: 8),
        PasteMenu.Item(title: "Delete", key: "\u{8}", modifiers: 8),
        PasteMenu.Item(title: "Rename", modifiers: 8),
        PasteMenu.Item(title: "Select All", key: "A"),
    ]

    func testPicksPasteAndRetainStyleByTitle() {
        XCTAssertTrue(PasteMenu.isEditMenu(notesEditMenu))
        XCTAssertEqual(PasteMenu.indexToPress(in: notesEditMenu), 7)
    }

    func testPicksItemAfterPasteAndMatchStyleInOtherLanguages() {
        let german = notesEditMenu.map { item -> PasteMenu.Item in
            var item = item
            item.title = ["Paste": "Einsetzen", "Paste and Match Style": "Einsetzen und Stil anpassen",
                          "Paste and Retain Style": "Einsetzen und Stil beibehalten"][item.title] ?? item.title
            return item
        }
        XCTAssertEqual(PasteMenu.indexToPress(in: german), 7)
    }

    func testFallsBackToPlainPaste() {
        let menu = [
            PasteMenu.Item(title: "Copy", key: "C"),
            PasteMenu.Item(title: "Paste", key: "V"),
            PasteMenu.Item(title: "Paste and Match Style", key: "V", modifiers: 3),
            PasteMenu.Item(title: "Delete", key: "\u{8}"),
        ]
        XCTAssertEqual(PasteMenu.indexToPress(in: menu), 1)
    }

    func testOtherMenusAreNotTheEditMenu() {
        XCTAssertFalse(PasteMenu.isEditMenu([PasteMenu.Item(title: "New Note", key: "N")]))
        XCTAssertNil(PasteMenu.indexToPress(in: []))
    }
}
