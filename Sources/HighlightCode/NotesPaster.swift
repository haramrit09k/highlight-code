#if canImport(AppKit)
import AppKit
import ApplicationServices

/// Pastes highlighted code into Apple Notes so that it keeps its colours.
///
/// Notes' plain Edit › Paste drops the font and colour of pasted rich text (and treats
/// text handed back by a Service the same way). Only Edit › Paste and Retain Style
/// keeps them, so this puts the code on the clipboard, presses that menu item through the
/// Accessibility API, and then restores the user's clipboard. Requires Accessibility access.
enum NotesPaster {
    static let notesBundleID = "com.apple.Notes"

    /// Modifier masks used by kAXMenuItemCmdModifiersAttribute (⌘ is implied).
    private static let shiftOption = 1 << 0 | 1 << 1
    private static let commandOnly = 0

    /// Replaces the selection in Notes with what `write` puts on the pasteboard.
    /// - Parameters:
    ///   - original: the selected text being replaced. If Notes no longer has it selected
    ///     (for example, after it dropped the selection), it is selected again first, and
    ///     nothing is pasted when that fails, so the code is never inserted twice.
    ///   - write: puts the content to paste on the given pasteboard.
    static func paste(into pid: pid_t, replacing original: String, write: (NSPasteboard) throws -> Void) throws {
        let application = AXUIElementCreateApplication(pid)
        guard ensureSelected(original, in: application) else {
            DebugLog.write("paste: aborted, the original text is no longer selected")
            NSSound.beep()
            return
        }

        let pasteboard = NSPasteboard.general
        let saved = PasteboardSnapshot(pasteboard)
        do {
            try write(pasteboard)
        } catch {
            saved.restore(to: pasteboard)
            throw error
        }
        let types = pasteboard.types?.map(\.rawValue).joined(separator: ", ") ?? "none"
        DebugLog.write("paste: pasteboard has [\(types)], rtf \(pasteboard.data(forType: .rtf)?.count ?? 0) bytes")
        let ourChange = pasteboard.changeCount
        pasteRetainingStyle(in: application)

        // Put the user's clipboard back once Notes has read ours.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if pasteboard.changeCount == ourChange { saved.restore(to: pasteboard) }
        }
    }

    /// Makes sure `original` is selected in Notes' focused text view.
    private static func ensureSelected(_ original: String, in application: AXUIElement) -> Bool {
        guard let element: AXUIElement = attribute(kAXFocusedUIElementAttribute, of: application),
              let range = selectedRange(of: element) else {
            DebugLog.write("selection: no focused text element; pasting anyway")
            return true
        }
        let selected: String = attribute(kAXSelectedTextAttribute, of: element) ?? ""
        if range.length > 0 {
            // Something is selected, so pasting replaces it rather than duplicating.
            DebugLog.write("selection: \(range.length) characters selected (matches original: \(normalized(selected) == normalized(original)))")
            return true
        }
        // Only a caret: if the original text sits right before it, select it again.
        let length = (original as NSString).length
        guard range.location >= length else { return false }
        var candidate = CFRange(location: range.location - length, length: length)
        guard let value = AXValueCreate(.cfRange, &candidate),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success else {
            return false
        }
        let reselected: String = attribute(kAXSelectedTextAttribute, of: element) ?? ""
        DebugLog.write("selection: caret only; reselected \(length) characters, matches: \(normalized(reselected) == normalized(original))")
        return normalized(reselected) == normalized(original)
    }

    private static func normalized(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).joined()
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        guard let value: AXValue = attribute(kAXSelectedTextRangeAttribute, of: element) else { return nil }
        var range = CFRange()
        return AXValueGetValue(value, .cfRange, &range) ? range : nil
    }

    /// Presses Edit › Paste and Retain Style exactly once: found by title, or by its ⌥⇧⌘V
    /// shortcut in other languages, otherwise plain Paste. Only if no menu item is found
    /// is the shortcut typed instead.
    ///
    /// Pressing a menu item through Accessibility often reports an error even though the
    /// item ran (the call times out waiting for the action), so the result is never used to
    /// try another item: that pasted the code twice.
    private static func pasteRetainingStyle(in application: AXUIElement) {
        let items = pasteMenuItems(in: application)
        let item = items.first { $0.title.localizedCaseInsensitiveContains("retain style") }
            ?? items.first { $0.modifiers == shiftOption && !$0.title.localizedCaseInsensitiveContains("match") }
            ?? items.first { $0.modifiers == commandOnly }
        DebugLog.write("paste: menu items with V: \(items.map { "\($0.title) [\($0.modifiers)]" }); pressing \(item?.title ?? "none")")

        if let item {
            let result = AXUIElementPerformAction(item.element, kAXPressAction as CFString)
            DebugLog.write("paste: pressed \(item.title), result \(result.rawValue)")
            return
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyV: CGKeyCode = 9
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: keyDown)
            event?.flags = [.maskCommand, .maskAlternate, .maskShift]
            event?.post(tap: .cghidEventTap)
        }
        DebugLog.write("paste: no menu item found, typed ⌥⇧⌘V")
    }

    private static func pasteMenuItems(in application: AXUIElement) -> [(element: AXUIElement, title: String, modifiers: Int)] {
        guard let menuBar: AXUIElement = attribute(kAXMenuBarAttribute, of: application) else { return [] }
        var result: [(AXUIElement, String, Int)] = []
        for menuBarItem in children(of: menuBar) {
            for menu in children(of: menuBarItem) {
                for item in children(of: menu) {
                    let key: String? = attribute(kAXMenuItemCmdCharAttribute, of: item)
                    guard key?.uppercased() == "V" else { continue }
                    let title: String = attribute(kAXTitleAttribute, of: item) ?? ""
                    let modifiers: NSNumber? = attribute(kAXMenuItemCmdModifiersAttribute, of: item)
                    result.append((item, title, modifiers?.intValue ?? commandOnly))
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
