/// Notes (like most Mac apps) turns typed quotes into curly “smart” quotes, which no
/// language treats as string delimiters. Code is highlighted with straight quotes, and the
/// result is mapped back onto the original text, so the note keeps its characters.
public enum SmartQuotes {
    static let replacements: [Character: Character] = [
        "\u{201C}": "\"", "\u{201D}": "\"", "\u{201E}": "\"", "\u{201F}": "\"", // “ ” „ ‟
        "\u{2018}": "'", "\u{2019}": "'", "\u{201A}": "'", "\u{201B}": "'",     // ‘ ’ ‚ ‛
    ]

    public static func straightened(_ text: String) -> String {
        String(text.map { replacements[$0] ?? $0 })
    }

    /// Re-slices `original` along the boundaries of `runs`, which were produced from
    /// `straightened(original)`. Returns `runs` unchanged if the lengths don't line up.
    public static func restore(_ runs: [TokenRun], from original: String) -> [TokenRun] {
        guard runs.reduce(0, { $0 + $1.text.count }) == original.count else { return runs }
        var index = original.startIndex
        return runs.map { run in
            let end = original.index(index, offsetBy: run.text.count)
            defer { index = end }
            return TokenRun(text: String(original[index..<end]), scopes: run.scopes)
        }
    }
}
