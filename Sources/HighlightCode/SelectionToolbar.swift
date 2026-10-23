#if canImport(AppKit)
import AppKit
import ApplicationServices
import HighlightCore

/// Shows a small floating "Highlight" button next to the text selected in Apple Notes.
///
/// Notes itself is not modified: like screen readers and tools such as Pronotes, this uses
/// the Accessibility API to follow the selection, and pastes the result through Notes'
/// own Edit › Paste menu item. It needs the Accessibility permission.
final class SelectionToolbar: NSObject {
    static let notesBundleID = "com.apple.Notes"
    /// The button appears once the selection stops changing for this long (e.g. drag ended).
    private static let settleDelay: TimeInterval = 0.25
    private static let panelSize = CGSize(width: 150, height: 34)

    private let write: (String, NSPasteboard) throws -> Void
    private var observer: AXObserver?
    private var notesElement: AXUIElement?
    private var observedPID: pid_t?
    private var workspaceObserver: NSObjectProtocol?
    private var pendingUpdate: DispatchWorkItem?
    private lazy var panel = makePanel()

    /// - Parameter write: formats the given text and writes it to the pasteboard.
    init(write: @escaping (String, NSPasteboard) throws -> Void) {
        self.write = write
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to Privacy & Security › Accessibility.
    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    var isRunning: Bool { workspaceObserver != nil }

    func start() {
        guard !isRunning else { return }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            self?.frontmostApplicationChanged(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
        frontmostApplicationChanged(NSWorkspace.shared.frontmostApplication)
    }

    func stop() {
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        workspaceObserver = nil
        detach()
        hidePanel()
    }

    // MARK: Following Notes

    private func frontmostApplicationChanged(_ application: NSRunningApplication?) {
        if let application, application.bundleIdentifier == Self.notesBundleID {
            attach(to: application.processIdentifier)
        } else {
            detach()
            hidePanel()
        }
    }

    private func attach(to pid: pid_t) {
        guard observedPID != pid else { return }
        detach()
        guard Self.isTrusted else { return }

        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<SelectionToolbar>.fromOpaque(refcon).takeUnretainedValue().selectionChanged()
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }

        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kAXSelectedTextChangedNotification, kAXFocusedUIElementChangedNotification] {
            AXObserverAddNotification(created, element, notification as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        notesElement = element
        observedPID = pid
        selectionChanged()
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        notesElement = nil
        observedPID = nil
        pendingUpdate?.cancel()
    }

    private func selectionChanged() {
        hidePanel()
        pendingUpdate?.cancel()
        let update = DispatchWorkItem { [weak self] in self?.showPanelForCurrentSelection() }
        pendingUpdate = update
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: update)
    }

    private func showPanelForCurrentSelection() {
        guard let element = focusedTextElement(),
              let range = selectedRange(of: element), range.length > 0,
              let text = selectedText(of: element), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let bounds = bounds(of: range, in: element),
              let primary = NSScreen.screens.first else { return }

        let flipped = CGPoint(x: bounds.midX, y: primary.frame.height - bounds.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(flipped) } ?? primary
        let frame = ToolbarPlacement.frame(
            forSelection: bounds,
            primaryScreenHeight: primary.frame.height,
            visibleFrame: screen.visibleFrame,
            size: Self.panelSize
        )
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    private func hidePanel() {
        panel.orderOut(nil)
    }

    // MARK: Highlighting

    @objc private func highlightClicked() {
        hidePanel()
        guard let element = focusedTextElement(), let text = selectedText(of: element), !text.isEmpty else {
            NSSound.beep()
            return
        }

        let pasteboard = NSPasteboard.general
        let saved = PasteboardSnapshot(pasteboard)
        do {
            try write(text, pasteboard)
        } catch {
            NSSound.beep()
            return
        }
        let ourChange = pasteboard.changeCount
        paste()

        // Put the user's clipboard back once Notes has read ours.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if pasteboard.changeCount == ourChange { saved.restore(to: pasteboard) }
        }
    }

    /// Presses Notes' Edit › Paste (found by its ⌘V shortcut, so it works in any language),
    /// falling back to a ⌘V keystroke.
    private func paste() {
        if let notesElement, let item = pasteMenuItem(in: notesElement),
           AXUIElementPerformAction(item, kAXPressAction as CFString) == .success {
            return
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyV: CGKeyCode = 9
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    private func pasteMenuItem(in application: AXUIElement) -> AXUIElement? {
        guard let menuBar: AXUIElement = attribute(kAXMenuBarAttribute, of: application) else { return nil }
        for menuBarItem in children(of: menuBar) {
            for menu in children(of: menuBarItem) {
                for item in children(of: menu) {
                    let character: String? = attribute(kAXMenuItemCmdCharAttribute, of: item)
                    let modifiers: NSNumber? = attribute(kAXMenuItemCmdModifiersAttribute, of: item)
                    // A modifiers value of 0 means "⌘ only".
                    if character?.uppercased() == "V", modifiers?.intValue == 0 { return item }
                }
            }
        }
        return nil
    }

    // MARK: Accessibility helpers

    private func focusedTextElement() -> AXUIElement? {
        guard let notesElement else { return nil }
        return attribute(kAXFocusedUIElementAttribute, of: notesElement)
    }

    private func selectedText(of element: AXUIElement) -> String? {
        attribute(kAXSelectedTextAttribute, of: element)
    }

    private func selectedRange(of element: AXUIElement) -> CFRange? {
        guard let value: AXValue = attribute(kAXSelectedTextRangeAttribute, of: element) else { return nil }
        var range = CFRange()
        return AXValueGetValue(value, .cfRange, &range) ? range : nil
    }

    private func bounds(of range: CFRange, in element: AXUIElement) -> CGRect? {
        var range = range
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &result
        ) == .success, let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        // swiftlint:disable:next force_cast
        return AXValueGetValue(result as! AXValue, .cgRect, &rect) && rect.width >= 0 ? rect : nil
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(kAXChildrenAttribute, of: element) ?? []
    }

    private func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else { return nil }
        if T.self == AXUIElement.self, CFGetTypeID(value) != AXUIElementGetTypeID() { return nil }
        if T.self == AXValue.self, CFGetTypeID(value) != AXValueGetTypeID() { return nil }
        return value as? T
    }

    // MARK: Panel

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.panelSize))
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 9
        background.layer?.masksToBounds = true

        let button = NSButton(title: "Highlight Code", target: self, action: #selector(highlightClicked))
        button.image = NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.isBordered = false
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.contentTintColor = .controlAccentColor
        button.toolTip = "Replace the selection with syntax-highlighted code"
        button.frame = background.bounds
        button.autoresizingMask = [.width, .height]
        background.addSubview(button)

        panel.contentView = background
        return panel
    }
}

/// A copy of everything on a pasteboard, so it can be put back afterwards.
private struct PasteboardSnapshot {
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
