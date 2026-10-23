import Foundation

/// An sRGB colour, stored without any platform type so themes can be tested anywhere.
public struct RGBColor: Equatable, Hashable {
    public var red: UInt8, green: UInt8, blue: UInt8

    public init(hex: UInt32) {
        red = UInt8((hex >> 16) & 0xFF)
        green = UInt8((hex >> 8) & 0xFF)
        blue = UInt8(hex & 0xFF)
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func channel(_ value: UInt8) -> Double {
            let c = Double(value) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG contrast ratio between two colours (1...21).
    public func contrast(with other: RGBColor) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

public struct TokenStyle: Equatable {
    public var color: RGBColor?
    public var bold: Bool
    public var italic: Bool

    public init(color: RGBColor? = nil, bold: Bool = false, italic: Bool = false) {
        self.color = color
        self.bold = bold
        self.italic = italic
    }
}

/// The semantic groups highlight.js scopes are folded into. Keeping themes to this
/// short list makes new palettes easy to add.
public enum TokenRole: CaseIterable {
    case keyword, string, comment, number, function, type, builtIn, meta, variable
    case tag, attribute, addition, deletion, heading, emphasis, strong, link
}

public struct Theme: Equatable, Identifiable {
    public var id: String
    public var name: String
    /// Plain text (no scope) is left uncoloured so it follows Notes' light/dark text colour.
    public var styles: [TokenRole: TokenStyle]

    public func style(for role: TokenRole) -> TokenStyle? { styles[role] }

    /// Resolves the style for a stack of nested scopes, innermost scope winning,
    /// like CSS inheritance in a highlight.js stylesheet.
    public func style(forScopes scopes: [String]) -> TokenStyle {
        var result = TokenStyle()
        var colorSet = false
        for scope in scopes.reversed() {
            guard let role = Theme.role(forScope: scope), let style = styles[role] else { continue }
            if !colorSet, let color = style.color {
                result.color = color
                colorSet = true
            }
            result.bold = result.bold || style.bold
            result.italic = result.italic || style.italic
        }
        return result
    }

    /// Maps a highlight.js scope such as `title.function.invoke` to a role, trying the
    /// most specific name first (`title.function.invoke`, `title.function`, `title`).
    public static func role(forScope scope: String) -> TokenRole? {
        var parts = scope.split(separator: ".").map(String.init)
        while !parts.isEmpty {
            if let role = scopeRoles[parts.joined(separator: ".")] { return role }
            parts.removeLast()
        }
        return nil
    }

    static let scopeRoles: [String: TokenRole] = [
        "keyword": .keyword, "doctag": .keyword, "selector-tag": .keyword, "operator": .keyword,
        "literal": .number, "number": .number, "symbol": .number, "bullet": .number,
        "string": .string, "regexp": .string, "char": .string, "template-tag": .string,
        "selector-attr": .string, "selector-pseudo": .string,
        "comment": .comment, "quote": .comment,
        "title": .function, "title.function": .function, "section": .heading,
        "title.class": .type, "type": .type, "class": .type, "selector-class": .type,
        "built_in": .builtIn, "subst": .variable, "variable": .variable,
        "template-variable": .variable, "selector-id": .variable, "property": .attribute,
        "meta": .meta, "meta.keyword": .keyword, "meta.string": .string,
        "tag": .tag, "name": .tag, "attr": .attribute, "attribute": .attribute,
        "addition": .addition, "deletion": .deletion,
        "emphasis": .emphasis, "strong": .strong, "link": .link,
    ]
}

extension Theme {
    /// Mid-tone colours that stay readable on both the light and dark Notes backgrounds.
    public static let balanced = Theme(id: "balanced", name: "Balanced (light & dark)", styles: [
        .keyword: TokenStyle(color: RGBColor(hex: 0xC7408A), bold: true),
        .string: TokenStyle(color: RGBColor(hex: 0x2F9A4E)),
        .comment: TokenStyle(color: RGBColor(hex: 0x868B94), italic: true),
        .number: TokenStyle(color: RGBColor(hex: 0xC76B12)),
        .function: TokenStyle(color: RGBColor(hex: 0x3D7FE0)),
        .type: TokenStyle(color: RGBColor(hex: 0x9B5DE5)),
        .builtIn: TokenStyle(color: RGBColor(hex: 0x1A9696)),
        .meta: TokenStyle(color: RGBColor(hex: 0xB07A1E)),
        .variable: TokenStyle(color: RGBColor(hex: 0x1A9696)),
        .tag: TokenStyle(color: RGBColor(hex: 0x3D7FE0)),
        .attribute: TokenStyle(color: RGBColor(hex: 0x9B5DE5)),
        .addition: TokenStyle(color: RGBColor(hex: 0x2F9A4E)),
        .deletion: TokenStyle(color: RGBColor(hex: 0xD9483B)),
        .heading: TokenStyle(color: RGBColor(hex: 0x3D7FE0), bold: true),
        .emphasis: TokenStyle(italic: true),
        .strong: TokenStyle(bold: true),
        .link: TokenStyle(color: RGBColor(hex: 0x3D7FE0)),
    ])

    /// Higher-contrast colours for notes kept in light mode.
    public static let classicLight = Theme(id: "classic-light", name: "Classic Light", styles: [
        .keyword: TokenStyle(color: RGBColor(hex: 0xAD3DA4), bold: true),
        .string: TokenStyle(color: RGBColor(hex: 0xC41A16)),
        .comment: TokenStyle(color: RGBColor(hex: 0x707F8C), italic: true),
        .number: TokenStyle(color: RGBColor(hex: 0x1C00CF)),
        .function: TokenStyle(color: RGBColor(hex: 0x326D74)),
        .type: TokenStyle(color: RGBColor(hex: 0x3900A0)),
        .builtIn: TokenStyle(color: RGBColor(hex: 0x5C2699)),
        .meta: TokenStyle(color: RGBColor(hex: 0x643820)),
        .variable: TokenStyle(color: RGBColor(hex: 0x326D74)),
        .tag: TokenStyle(color: RGBColor(hex: 0x0B4F79)),
        .attribute: TokenStyle(color: RGBColor(hex: 0x5C2699)),
        .addition: TokenStyle(color: RGBColor(hex: 0x22863A)),
        .deletion: TokenStyle(color: RGBColor(hex: 0xB31D28)),
        .heading: TokenStyle(color: RGBColor(hex: 0x0B4F79), bold: true),
        .emphasis: TokenStyle(italic: true),
        .strong: TokenStyle(bold: true),
        .link: TokenStyle(color: RGBColor(hex: 0x0B4F79)),
    ])

    /// Higher-contrast colours for notes kept in dark mode.
    public static let classicDark = Theme(id: "classic-dark", name: "Classic Dark", styles: [
        .keyword: TokenStyle(color: RGBColor(hex: 0xFC5FA3), bold: true),
        .string: TokenStyle(color: RGBColor(hex: 0xFC6A5D)),
        .comment: TokenStyle(color: RGBColor(hex: 0x7F8C98), italic: true),
        .number: TokenStyle(color: RGBColor(hex: 0xD0BF69)),
        .function: TokenStyle(color: RGBColor(hex: 0x67B7A4)),
        .type: TokenStyle(color: RGBColor(hex: 0x5DD8FF)),
        .builtIn: TokenStyle(color: RGBColor(hex: 0xD0A8FF)),
        .meta: TokenStyle(color: RGBColor(hex: 0xFD8F3F)),
        .variable: TokenStyle(color: RGBColor(hex: 0x67B7A4)),
        .tag: TokenStyle(color: RGBColor(hex: 0x5DD8FF)),
        .attribute: TokenStyle(color: RGBColor(hex: 0xD0A8FF)),
        .addition: TokenStyle(color: RGBColor(hex: 0x7EE787)),
        .deletion: TokenStyle(color: RGBColor(hex: 0xFF7B72)),
        .heading: TokenStyle(color: RGBColor(hex: 0x5DD8FF), bold: true),
        .emphasis: TokenStyle(italic: true),
        .strong: TokenStyle(bold: true),
        .link: TokenStyle(color: RGBColor(hex: 0x5DD8FF)),
    ])

    public static let all: [Theme] = [.balanced, .classicLight, .classicDark]

    public static func named(_ id: String?) -> Theme {
        all.first { $0.id == id } ?? .balanced
    }
}
