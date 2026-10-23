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

    init(
        preferences: Preferences,
        formatter: @escaping () throws -> SnippetFormatter,
        languageMenu: @escaping () -> LanguageMenu,
        onRequest: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.formatter = formatter
        self.languageMenu = languageMenu
        self.onRequest = onRequest
    }

    /// "Highlight Code": replaces the selected text with highlighted code.
    @objc func highlightCode(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        format(from: pasteboard, to: pasteboard, choice: .automatic, error: error)
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
        format(from: pasteboard, to: pasteboard, choice: choice, error: error)
    }

    /// "Copy Highlighted Code": leaves the selection alone and puts highlighted code on the
    /// clipboard, for apps where replacing the selection is not possible.
    @objc func copyHighlightedCode(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        format(from: pasteboard, to: .general, choice: .automatic, error: error)
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
