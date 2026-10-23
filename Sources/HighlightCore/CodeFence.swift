/// Code selected for highlighting, with an optional language hint.
public struct CodeSnippet: Equatable {
    public var code: String
    public var language: String?

    public init(code: String, language: String? = nil) {
        self.code = code
        self.language = language
    }

    /// Recognises Markdown fences, so selecting
    ///
    ///     ```python
    ///     print("hi")
    ///     ```
    ///
    /// highlights `print("hi")` as Python and drops the fence lines.
    /// Text without a fence is returned unchanged with no language hint.
    public static func parse(_ text: String) -> CodeSnippet {
        var lines = text.components(separatedBy: "\n")
        guard let first = lines.firstIndex(where: { !$0.trimmingWhitespace().isEmpty }),
              lines[first].trimmingWhitespace().hasPrefix("```") else {
            return CodeSnippet(code: text)
        }

        let info = lines[first].trimmingWhitespace().dropFirst(3).trimmingWhitespace()
        // The info string may carry extra words (```js title="x"); the first is the language.
        let language = info.split(separator: " ").first.map { String($0).lowercased() }

        lines.removeSubrange(0...first)
        if let last = lines.lastIndex(where: { !$0.trimmingWhitespace().isEmpty }),
           lines[last].trimmingWhitespace() == "```" {
            // Keep a trailing newline if the selection ended with one after the fence.
            let hadTrailingNewline = lines.count > last + 1
            lines.removeSubrange(last...)
            var code = lines.joined(separator: "\n")
            if hadTrailingNewline { code += "\n" }
            return CodeSnippet(code: code, language: language)
        }
        return CodeSnippet(code: lines.joined(separator: "\n"), language: language)
    }
}

extension StringProtocol {
    func trimmingWhitespace() -> String {
        let scalars = unicodeScalars
        guard let start = scalars.firstIndex(where: { !$0.properties.isWhitespace }) else { return "" }
        let end = scalars.lastIndex(where: { !$0.properties.isWhitespace })!
        return String(String.UnicodeScalarView(scalars[start...end]))
    }
}
