/// A piece of source code together with the highlight.js scopes that apply to it,
/// outermost first. For example `["string", "subst"]` for the `${b}` part of a
/// JavaScript template literal.
public struct TokenRun: Equatable {
    public var text: String
    public var scopes: [String]

    public init(text: String, scopes: [String] = []) {
        self.text = text
        self.scopes = scopes
    }
}

/// Parses the small HTML subset highlight.js emits: plain text, HTML entities and
/// (nested) `<span class="hljs-…">` elements.
public enum HighlightHTMLParser {
    public static func parse(_ html: String) -> [TokenRun] {
        var runs: [TokenRun] = []
        var stack: [String] = []
        var buffer = ""

        func flush() {
            guard !buffer.isEmpty else { return }
            if let last = runs.last, last.scopes == stack {
                runs[runs.count - 1].text += buffer
            } else {
                runs.append(TokenRun(text: buffer, scopes: stack))
            }
            buffer = ""
        }

        var index = html.startIndex
        while index < html.endIndex {
            let char = html[index]
            if char == "<", let close = html[index...].firstIndex(of: ">") {
                let tag = html[html.index(after: index)..<close]
                flush()
                if tag.hasPrefix("/") {
                    _ = stack.popLast()
                } else if tag.hasPrefix("span") {
                    stack.append(scope(fromSpanTag: String(tag)))
                }
                index = html.index(after: close)
            } else if char == "&", let semicolon = html[index...].prefix(10).firstIndex(of: ";"),
                      let decoded = decodeEntity(String(html[html.index(after: index)..<semicolon])) {
                buffer.append(decoded)
                index = html.index(after: semicolon)
            } else {
                buffer.append(char)
                index = html.index(after: index)
            }
        }
        flush()
        return runs
    }

    /// Turns `span class="hljs-title function_"` into the scope name `title.function`,
    /// mirroring how highlight.js 11 encodes dotted scopes as CSS classes.
    static func scope(fromSpanTag tag: String) -> String {
        guard let start = tag.range(of: "class=\"") else { return "" }
        let rest = tag[start.upperBound...]
        let value = rest.prefix { $0 != "\"" }
        let parts = value.split(separator: " ").enumerated().map { offset, part -> String in
            var name = String(part)
            if offset == 0, name.hasPrefix("hljs-") { name.removeFirst(5) }
            while name.hasSuffix("_") { name.removeLast() }
            return name
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ".")
    }

    static func decodeEntity(_ name: String) -> Character? {
        switch name {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        default:
            let scalarValue: UInt32?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                scalarValue = UInt32(name.dropFirst(2), radix: 16)
            } else if name.hasPrefix("#") {
                scalarValue = UInt32(name.dropFirst())
            } else {
                scalarValue = nil
            }
            return scalarValue.flatMap(Unicode.Scalar.init).map(Character.init)
        }
    }
}
