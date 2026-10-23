#if canImport(AppKit)
import AppKit
import HighlightCore

/// Handles the entries this app adds to the Services menu (declared under
/// `NSServices` in Resources/Info.plist).
final class ServiceProvider: NSObject {
    private let formatter: () throws -> SnippetFormatter
    private let languageMenu: () -> LanguageMenu
    private let preferences: Preferences
    private let onRequest: () -> Void
    private let onNotesNeedsAccessibility: () -> Void

    init(
        preferences: Preferences,
        formatter: @escaping () throws -> SnippetFormatter,
        languageMenu: @escaping () -> LanguageMenu,
        onNotesNeedsAccessibility: @escaping () -> Void,
        onRequest: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.formatter = formatter
        self.languageMenu = languageMenu
        self.onNotesNeedsAccessibility = onNotesNeedsAccessibility
        self.onRequest = onRequest
    }

    /// "Highlight Code": replaces the selected text with highlighted code.
    @objc func highlightCode(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        replaceSelection(in: pasteboard, choice: .automatic, error: error)
    }

    /// "Highlight Code As…": asks for the language first, then replaces the selection.
    @objc func highlightCodeAs(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        onRequest()
        guard pasteboard.string(forType: .string)?.isEmpty == false else {
            error.pointee = "Select some code first." as NSString
            return
        }
        // The pointer is where the user just clicked the Services menu; with a keyboard
        // shortcut it is wherever the mouse happens to be.
        guard let choice = languageMenu().pick(at: NSEvent.mouseLocation, in: nil) else {
            // Reporting an error tells the calling app to leave the selection alone.
            error.pointee = "Cancelled." as NSString
            return
        }
        preferences.noteUsed(choice)
        replaceSelection(in: pasteboard, choice: choice, error: error)
    }

    /// "Copy Highlighted Code": leaves the selection alone and puts highlighted code on the
    /// clipboard, for apps where replacing the selection is not possible.
    @objc func copyHighlightedCode(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        format(from: pasteboard, to: .general, choice: .automatic, error: error)
    }

    private func replaceSelection(in pasteboard: NSPasteboard, choice: LanguageChoice, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let notes = NSWorkspace.shared.frontmostApplication, notes.bundleIdentifier == NotesPaster.notesBundleID else {
            format(from: pasteboard, to: pasteboard, choice: choice, error: error)
            return
        }
        guard SelectionToolbar.isTrusted else {
            DebugLog.write("service: Notes without Accessibility access, normal reply")
            // Fall through to the normal reply, which Notes shows without colours.
            onNotesNeedsAccessibility()
            format(from: pasteboard, to: pasteboard, choice: choice, error: error)
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
                    try formatter().write(text, language: choice.languageID, options: options, to: target)
                }
            } catch {
                NSSound.beep()
            }
        }
    }

    private func format(
        from source: NSPasteboard,
        to destination: NSPasteboard,
        choice: LanguageChoice,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        onRequest()
        guard let text = source.string(forType: .string), !text.isEmpty else {
            error.pointee = "Select some code first." as NSString
            return
        }
        do {
            try formatter().write(text, language: choice.languageID, options: preferences.renderOptions, to: destination)
        } catch let failure {
            error.pointee = "\(failure)" as NSString
        }
    }
}
#endif
