#if canImport(AppKit)
import AppKit

public struct RenderOptions: Equatable {
    public var theme: Theme
    public var fontName: String
    public var fontSize: CGFloat

    /// Menlo is available on every Mac, iPhone and iPad, so notes look the same after syncing.
    public init(theme: Theme = .balanced, fontName: String = "Menlo", fontSize: CGFloat = 13) {
        self.theme = theme
        self.fontName = fontName
        self.fontSize = fontSize
    }
}

public enum CodeRenderer {
    /// Builds monospaced rich text. Unscoped text gets no colour, so it keeps following
    /// the note's own light or dark text colour.
    public static func attributedString(for runs: [TokenRun], options: RenderOptions = RenderOptions()) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let base = NSFont(name: options.fontName, size: options.fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: options.fontSize, weight: .regular)

        for run in runs {
            let style = options.theme.style(forScopes: run.scopes)
            var attributes: [NSAttributedString.Key: Any] = [.font: font(base, bold: style.bold, italic: style.italic)]
            if let color = style.color {
                attributes[.foregroundColor] = NSColor(
                    srgbRed: CGFloat(color.red) / 255,
                    green: CGFloat(color.green) / 255,
                    blue: CGFloat(color.blue) / 255,
                    alpha: 1
                )
            }
            output.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        return output
    }

    /// RTF data for the pasteboard.
    public static func rtfData(for attributed: NSAttributedString) -> Data? {
        attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:])
    }

    private static func font(_ base: NSFont, bold: Bool, italic: Bool) -> NSFont {
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        guard !traits.isEmpty else { return base }
        return NSFontManager.shared.convert(base, toHaveTrait: traits)
    }
}
#endif
