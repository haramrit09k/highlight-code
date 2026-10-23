#if canImport(JavaScriptCore)
import Foundation
import JavaScriptCore

public struct HighlightResult: Equatable {
    /// Highlight.js' language id, e.g. `python`; `nil` when nothing matched.
    public var language: String?
    public var runs: [TokenRun]
}

public enum CodeHighlighterError: Error, CustomStringConvertible {
    case scriptMissing
    case scriptFailed(String)

    public var description: String {
        switch self {
        case .scriptMissing: return "highlight.js was not found in the app bundle."
        case .scriptFailed(let message): return "highlight.js failed to load: \(message)"
        }
    }
}

/// Runs highlight.js inside JavaScriptCore, so no browser or network is needed.
public final class CodeHighlighter {
    /// Languages considered for auto-detection. Others in the bundle can still be used
    /// through a fence (```lua); leaving rarely used grammars out keeps detection accurate.
    public static let autoDetectLanguages = [
        "bash", "c", "cpp", "csharp", "css", "dart", "diff", "dockerfile", "elixir", "go",
        "graphql", "haskell", "java", "javascript", "kotlin", "lua", "makefile", "markdown",
        "objectivec", "php", "powershell", "python", "r", "ruby", "rust", "scala", "scss",
        "shell", "sql", "swift", "typescript", "xml", "yaml",
    ]

    private let context: JSContext
    private let highlightFunction: JSValue

    public convenience init(bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: "highlight", withExtension: "js") else {
            throw CodeHighlighterError.scriptMissing
        }
        try self.init(script: String(contentsOf: url, encoding: .utf8))
    }

    public init(script: String) throws {
        guard let context = JSContext() else { throw CodeHighlighterError.scriptFailed("no JSContext") }
        var exception: String?
        context.exceptionHandler = { _, value in exception = value?.toString() }
        context.evaluateScript(script)
        context.setObject(Self.autoDetectLanguages, forKeyedSubscript: "__autoLanguages" as NSString)
        context.evaluateScript(Self.glue)
        if let exception { throw CodeHighlighterError.scriptFailed(exception) }
        guard let function = context.objectForKeyedSubscript("__highlight"), !function.isUndefined else {
            throw CodeHighlighterError.scriptFailed("hljs is not defined")
        }
        self.context = context
        self.highlightFunction = function
    }

    public var supportedLanguages: [String] {
        context.evaluateScript("hljs.listLanguages()")?.toArray() as? [String] ?? []
    }

    /// Highlights `code`, using `language` (an id or alias such as `py`) when highlight.js
    /// knows it and auto-detecting otherwise.
    public func highlight(_ code: String, language: String? = nil) -> HighlightResult {
        let result = highlightFunction.call(withArguments: [code, language ?? ""])
        let html = result?.objectForKeyedSubscript("html")?.toString() ?? ""
        let detected = result?.objectForKeyedSubscript("language")?.toString() ?? ""
        let runs = html.isEmpty && !code.isEmpty ? [TokenRun(text: code)] : HighlightHTMLParser.parse(html)
        return HighlightResult(language: detected.isEmpty ? nil : detected, runs: runs)
    }

    private static let glue = """
    function __guessLanguage(code) {
      var trimmed = code.trim();
      if (/^[\\[{]/.test(trimmed)) {
        try { JSON.parse(trimmed); return "json"; } catch (e) {}
      }
      // Short Java snippets are otherwise easily mistaken for C#.
      if (/\\bSystem\\.out\\.print|\\bpublic\\s+static\\s+void\\s+main\\s*\\(\\s*String|^\\s*import\\s+java\\./m.test(code)) {
        return "java";
      }
      return null;
    }
    function __highlight(code, language) {
      try {
        var lang = language && hljs.getLanguage(language) ? language : __guessLanguage(code);
        var result = lang
          ? hljs.highlight(code, { language: lang, ignoreIllegals: true })
          : hljs.highlightAuto(code, __autoLanguages);
        return { html: result.value, language: result.language || "" };
      } catch (e) {
        return { html: "", language: "" };
      }
    }
    """
}
#endif
