#if canImport(AppKit)
import AppKit
import ApplicationServices
import HighlightCore

/// Shows a small floating "Highlight" button next to the text selected in Apple Notes.
///
/// Notes itself is not modified: like screen readers and tools such as Pronotes, this uses
/// the Accessibility API to follow the selection, and pastes the result with Notes' own
/// Edit › Paste and Retain Style (see NotesPaster). It needs the Accessibility permission.
final class SelectionToolbar: NSObject {
    static let notesBundleID = NotesPaster.notesBundleID
    /// The button appears once the selection stops changing for this long (e.g. drag ended).
    private static let settleDelay: TimeInterval = 0.25
    private static let panelSize = CGSize(width: 150, height: 34)

    private let write: (String, NSPasteboard) throws -> Void
    private var observer: AXObserver?
    private var notesElement: AXUIElement?
    private var observedPID: pid_t?
    private var workspaceObserver: NSObjectProtocol?
    private var pendingUpdate: DispatchWorkItem?
    private var eventMonitor: Any?
    /// The selection the button is currently shown for.
    private var shownRange: (location: Int, length: Int)?
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
        // Notes doesn't always report the end of a drag or a Shift-arrow selection, so also
        // look again whenever the mouse button or a key is released while Notes is in front.
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .keyUp]) { [weak self] _ in
            guard let self, self.observedPID != nil else { return }
            self.selectionChanged()
        }
        frontmostApplicationChanged(NSWorkspace.shared.frontmostApplication)
    }

    func stop() {
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        workspaceObserver = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
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
        // Notes also reports "selection changed" when the selection stays the same (focus
        // moves, redraws, autosave); leave the button where it is then, or it flickers.
        if let shownRange, let element = focusedTextElement(), let range = selectedRange(of: element),
           range.location == shownRange.location, range.length == shownRange.length {
            return
        }
        hidePanel()
        pendingUpdate?.cancel()
        let update = DispatchWorkItem { [weak self] in self?.showPanelForCurrentSelection() }
        pendingUpdate = update
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: update)
    }

    private func showPanelForCurrentSelection() {
        guard let element = focusedTextElement() else {
            DebugLog.write("button: not shown, Notes has no focused text element")
            return
        }
        guard let range = selectedRange(of: element), range.length > 0,
              let text = selectedText(of: element), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let primary = NSScreen.screens.first else { return }
        let bounds = anchorRect(for: range, in: element, primaryScreenHeight: primary.frame.height)

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
        shownRange = (range.location, range.length)
    }

    private func hidePanel() {
        panel.orderOut(nil)
        shownRange = nil
    }

    // MARK: Highlighting

    @objc private func highlightClicked() {
        hidePanel()
        guard let pid = observedPID, let element = focusedTextElement(),
              let text = selectedText(of: element), !text.isEmpty else {
            NSSound.beep()
            return
        }
        do {
            DebugLog.write("floating button: highlighting \(text.count) characters")
            try NotesPaster.paste(into: pid, replacing: text) { pasteboard in try write(text, pasteboard) }
        } catch {
            NSSound.beep()
        }
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

    /// Where the selection is on screen (Accessibility coordinates). Notes can't always give
    /// bounds for a long, multi-line selection, so fall back to its first and last characters,
    /// and finally to the mouse pointer, which is where a drag ends.
    private func anchorRect(for range: CFRange, in element: AXUIElement, primaryScreenHeight: CGFloat) -> CGRect {
        if let rect = bounds(of: range, in: element), rect.height > 0 {
            return rect
        }
        let first = bounds(of: CFRange(location: range.location, length: 1), in: element)
        let last = bounds(of: CFRange(location: range.location + range.length - 1, length: 1), in: element)
        switch (first, last) {
        case let (first?, last?):
            DebugLog.write("button: no bounds for \(range.length) characters, using first and last")
            return first.union(last)
        case let (rect?, nil), let (nil, rect?):
            return rect
        case (nil, nil):
            DebugLog.write("button: no bounds for the selection, using the mouse position")
            let mouse = NSEvent.mouseLocation
            return CGRect(x: mouse.x, y: primaryScreenHeight - mouse.y - 20, width: 1, height: 20)
        }
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

    private func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
        NotesPaster.attribute(name, of: element)
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
#endif
