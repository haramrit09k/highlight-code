#if canImport(AppKit)
import AppKit
import ApplicationServices

/// Pastes highlighted code into Apple Notes so that it keeps its colours.
///
/// Notes' plain Edit › Paste drops the font and colour of pasted rich text (and treats
/// text handed back by a Service the same way). Only Edit › Paste and Retain Style (⌥⇧⌘V)
/// keeps them, so this puts the code on the clipboard, presses that menu item through the
/// Accessibility API, and then restores the user's clipboard. Requires Accessibility access.
enum NotesPaster {
    static let notesBundleID = "com.apple.Notes"

    /// Modifier masks used by kAXMenuItemCmdModifiersAttribute (⌘ is implied).
    private static let shiftOption = 1 << 0 | 1 << 1
    private static let commandOnly = 0

    /// - Parameter write: puts the content to paste on the given pasteboard.
    static func paste(into pid: pid_t, write: (NSPasteboard) throws -> Void) throws {
        let pasteboard = NSPasteboard.general
        let saved = PasteboardSnapshot(pasteboard)
        do {
            try write(pasteboard)
        } catch {
            saved.restore(to: pasteboard)
            throw error
        }
        let ourChange = pasteboard.changeCount
        pasteRetainingStyle(in: AXUIElementCreateApplication(pid))

        // Put the user's clipboard back once Notes has read ours.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if pasteboard.changeCount == ourChange { saved.restore(to: pasteboard) }
        }
    }

    /// Presses Edit › Paste and Retain Style, found by its ⌥⇧⌘V shortcut so it works in any
    /// language; falls back to plain Paste, then to typing the shortcut.
    private static func pasteRetainingStyle(in application: AXUIElement) {
        let items = menuItems(withCommandCharacter: "V", in: application)
        for modifiers in [shiftOption, commandOnly] {
            if let item = items.first(where: { $0.modifiers == modifiers }),
               AXUIElementPerformAction(item.element, kAXPressAction as CFString) == .success {
                return
            }
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyV: CGKeyCode = 9
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: keyDown)
            event?.flags = [.maskCommand, .maskAlternate, .maskShift]
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func menuItems(withCommandCharacter character: String, in application: AXUIElement) -> [(element: AXUIElement, modifiers: Int)] {
        guard let menuBar: AXUIElement = attribute(kAXMenuBarAttribute, of: application) else { return [] }
        var result: [(AXUIElement, Int)] = []
        for menuBarItem in children(of: menuBar) {
            for menu in children(of: menuBarItem) {
                for item in children(of: menu) {
                    let key: String? = attribute(kAXMenuItemCmdCharAttribute, of: item)
                    guard key?.uppercased() == character else { continue }
                    let modifiers: NSNumber? = attribute(kAXMenuItemCmdModifiersAttribute, of: item)
                    result.append((item, modifiers?.intValue ?? commandOnly))
                }
            }
        }
        return result
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(kAXChildrenAttribute, of: element) ?? []
    }

    static func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else { return nil }
        if T.self == AXUIElement.self, CFGetTypeID(value) != AXUIElementGetTypeID() { return nil }
        if T.self == AXValue.self, CFGetTypeID(value) != AXValueGetTypeID() { return nil }
        return value as? T
    }
}

/// A copy of everything on a pasteboard, so it can be put back afterwards.
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { contents[type] = data }
            }
            return contents
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items.map { contents in
            let item = NSPasteboardItem()
            for (type, data) in contents { item.setData(data, forType: type) }
            return item
        })
    }
}
#endif
