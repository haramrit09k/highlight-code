import Foundation

/// A language the user can pick, e.g. `python` / "Python".
public struct LanguageInfo: Equatable, Hashable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Builds the language picker's contents from what highlight.js provides.
public enum LanguageCatalog {
    /// Shown near the top of the picker, in this order.
    public static let popularIDs = [
        "python", "javascript", "typescript", "java", "swift", "kotlin", "go", "rust",
        "c", "cpp", "csharp", "ruby", "php", "sql", "bash", "json", "yaml", "xml", "css",
        "markdown", "dockerfile", "plaintext",
    ]

    /// Grammars that only make sense embedded in another language.
    static let hiddenIDs: Set<String> = ["php-template", "python-repl"]

    /// Friendlier names where highlight.js' own are terse or unusual.
    static let nameOverrides = [
        "php": "PHP",
        "ini": "TOML / INI",
        "xml": "HTML / XML",
        "plaintext": "Plain Text",
        "shell": "Shell Session",
        "nginx": "Nginx",
    ]

    /// Turns highlight.js `(id, name)` pairs into picker entries, sorted by name.
    public static func languages(fromHighlightJS pairs: [(id: String, name: String)]) -> [LanguageInfo] {
        pairs
            .filter { !hiddenIDs.contains($0.id) }
            .map { LanguageInfo(id: $0.id, name: nameOverrides[$0.id] ?? $0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public struct Sections: Equatable {
        public var recent: [LanguageInfo]
        public var popular: [LanguageInfo]
        public var all: [LanguageInfo]
    }

    /// Splits the picker into recently used, popular (minus the recent ones) and everything.
    public static func sections(all: [LanguageInfo], recentIDs: [String]) -> Sections {
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recent = recentIDs.compactMap { byID[$0] }
        let recentSet = Set(recent.map(\.id))
        let popular = popularIDs.filter { !recentSet.contains($0) }.compactMap { byID[$0] }
        return Sections(recent: recent, popular: popular, all: all)
    }
}

/// The languages most recently picked, newest first.
public struct RecentLanguages: Equatable {
    public static let limit = 5

    public private(set) var ids: [String]

    public init(ids: [String] = []) {
        self.ids = Array(ids.prefix(Self.limit))
    }

    public mutating func use(_ id: String) {
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        if ids.count > Self.limit { ids.removeLast(ids.count - Self.limit) }
    }
}
