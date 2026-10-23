#if canImport(AppKit) && canImport(JavaScriptCore)
import AppKit

/// The whole pipeline: selected text in, highlighted rich text out.
public final class SnippetFormatter {
    private let highlighter: CodeHighlighter

    public init(highlighter: CodeHighlighter) {
        self.highlighter = highlighter
    }

    public struct Output {
        public var attributed: NSAttributedString
        public var language: String?
    }

    /// - Parameter language: a language picked by the user; it wins over a Markdown fence.
    ///   `nil` uses the fence's language, or auto-detects.
    public func format(_ text: String, language: String? = nil, options: RenderOptions) -> Output {
        let snippet = CodeSnippet.parse(text)
        let result = highlighter.highlight(SmartQuotes.straightened(snippet.code), language: language ?? snippet.language)
        let runs = SmartQuotes.restore(result.runs, from: snippet.code)
        return Output(
            attributed: CodeRenderer.attributedString(for: runs, options: options),
            language: result.language
        )
    }

    /// Writes the formatted text to `pasteboard` as RTF plus a plain-text fallback.
    @discardableResult
    public func write(_ text: String, language: String? = nil, options: RenderOptions, to pasteboard: NSPasteboard) -> Output {
        let output = format(text, language: language, options: options)
        pasteboard.clearContents()
        pasteboard.declareTypes([.rtf, .string], owner: nil)
        if let rtf = CodeRenderer.rtfData(for: output.attributed) {
            pasteboard.setData(rtf, forType: .rtf)
        }
        pasteboard.setString(output.attributed.string, forType: .string)
        return output
    }
}
#endif
