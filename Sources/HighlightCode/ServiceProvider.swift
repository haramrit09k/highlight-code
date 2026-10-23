#if canImport(AppKit)
import AppKit
import HighlightCore

/// Handles the two entries this app adds to the Services menu (declared under
/// `NSServices` in Resources/Info.plist).
final class ServiceProvider: NSObject {
    private let formatter: () throws -> SnippetFormatter
    private let preferences: Preferences
    private let onRequest: () -> Void

    init(preferences: Preferences, formatter: @escaping () throws -> SnippetFormatter, onRequest: @escaping () -> Void) {
        self.preferences = preferences
        self.formatter = formatter
        self.onRequest = onRequest
    }

    /// "Highlight Code": replaces the selected text with highlighted code.
    @objc func highlightCode(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
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
