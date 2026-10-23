#if canImport(AppKit)
import AppKit
import HighlightCore

/// Handles the two entries this app adds to the Services menu (declared under
/// `NSServices` in Resources/Info.plist).
final class ServiceProvider: NSObject {
    private let formatter: () throws -> SnippetFormatter
    private let preferences: Preferences
    private let onRequest: () -> Void
    private let onNotesNeedsAccessibility: () -> Void

    init(
        preferences: Preferences,
        formatter: @escaping () throws -> SnippetFormatter,
        onNotesNeedsAccessibility: @escaping () -> Void,
        onRequest: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.formatter = formatter
        self.onNotesNeedsAccessibility = onNotesNeedsAccessibility
        self.onRequest = onRequest
    }

    /// "Highlight Code": replaces the selected text with highlighted code.
    @objc func highlightCode(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        if let notes = NSWorkspace.shared.frontmostApplication, notes.bundleIdentifier == NotesPaster.notesBundleID {
            guard SelectionToolbar.isTrusted else {
                DebugLog.write("service: Notes without Accessibility access, normal reply")
                // Fall through to the normal reply, which Notes shows without colours.
                onNotesNeedsAccessibility()
                format(from: pasteboard, to: pasteboard, error: error)
                return
            }
            onRequest()
            guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
                error.pointee = "Select some code first." as NSString
                return
            }
            // Notes drops the colours of text returned by a service, so decline the reply and
            // paste with Paste and Retain Style once Notes has control again. Clearing the
            // service pasteboard leaves Notes nothing to put in place of the selection.
            DebugLog.write("service: Notes, highlighting \(text.count) characters via Paste and Retain Style")
            pasteboard.clearContents()
            error.pointee = "Pasting into Notes with Paste and Retain Style instead." as NSString
            let options = preferences.renderOptions
            let formatter = formatter
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                do {
                    try NotesPaster.paste(into: notes.processIdentifier, replacing: text) { target in
                        try formatter().write(text, options: options, to: target)
                    }
                } catch {
                    NSSound.beep()
                }
            }
            return
        }
        format(from: pasteboard, to: pasteboard, error: error)
    }

    /// "Copy Highlighted Code": leaves the selection alone and puts highlighted code on the
    /// clipboard, for apps where replacing the selection is not possible.
    @objc func copyHighlightedCode(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        format(from: pasteboard, to: .general, error: error)
    }

    private func format(from source: NSPasteboard, to destination: NSPasteboard, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        onRequest()
        guard let text = source.string(forType: .string), !text.isEmpty else {
            error.pointee = "Select some code first." as NSString
            return
        }
        do {
            try formatter().write(text, options: preferences.renderOptions, to: destination)
        } catch let failure {
            error.pointee = "\(failure)" as NSString
        }
    }
}
#endif
