@testable import HighlightCore
import XCTest

final class HighlightHTMLParserTests: XCTestCase {
    func testPlainTextAndEntities() {
        let runs = HighlightHTMLParser.parse("a &lt; b &amp;&amp; c &gt; &quot;d&quot; &#x27;e&#39;")
        XCTAssertEqual(runs, [TokenRun(text: "a < b && c > \"d\" 'e'")])
    }

    func testSpansBecomeScopes() {
        let html = #"<span class="hljs-keyword">def</span> <span class="hljs-title function_">f</span>(x)"#
        XCTAssertEqual(HighlightHTMLParser.parse(html), [
            TokenRun(text: "def", scopes: ["keyword"]),
            TokenRun(text: " "),
            TokenRun(text: "f", scopes: ["title.function"]),
            TokenRun(text: "(x)"),
        ])
    }

    func testNestedSpans() {
        let html = #"<span class="hljs-string">`a<span class="hljs-subst">${b}</span>`</span>"#
        XCTAssertEqual(HighlightHTMLParser.parse(html), [
            TokenRun(text: "`a", scopes: ["string"]),
            TokenRun(text: "${b}", scopes: ["string", "subst"]),
            TokenRun(text: "`", scopes: ["string"]),
        ])
    }

    func testMultiPartScopeNames() {
        XCTAssertEqual(HighlightHTMLParser.scope(fromSpanTag: #"span class="hljs-title class_ inherited__""#), "title.class.inherited")
        XCTAssertEqual(HighlightHTMLParser.scope(fromSpanTag: #"span class="hljs-meta""#), "meta")
    }

    func testUnknownEntityIsKeptVerbatim() {
        XCTAssertEqual(HighlightHTMLParser.parse("&nope; & x"), [TokenRun(text: "&nope; & x")])
    }

    func testPreservesWhitespaceAndUnicode() {
        let html = "\t<span class=\"hljs-string\">\"héllo 👋\"</span>\n"
        XCTAssertEqual(HighlightHTMLParser.parse(html).map(\.text).joined(), "\t\"héllo 👋\"\n")
    }
}

final class CodeSnippetTests: XCTestCase {
    func testTextWithoutFenceIsUnchanged() {
        XCTAssertEqual(CodeSnippet.parse("let x = 1\n"), CodeSnippet(code: "let x = 1\n"))
    }

    func testFenceSetsLanguageAndIsRemoved() {
        XCTAssertEqual(CodeSnippet.parse("```Python\nprint(1)\n```"), CodeSnippet(code: "print(1)", language: "python"))
    }

    func testFenceWithInfoStringAndTrailingNewline() {
        XCTAssertEqual(CodeSnippet.parse("\n```js title=\"a.js\"\nf()\n```\n"), CodeSnippet(code: "f()\n", language: "js"))
    }

    func testFenceWithoutLanguage() {
        XCTAssertEqual(CodeSnippet.parse("```\nx\n```"), CodeSnippet(code: "x", language: nil))
    }

    func testUnclosedFenceStillDropsOpeningLine() {
        XCTAssertEqual(CodeSnippet.parse("```go\nfunc main() {}"), CodeSnippet(code: "func main() {}", language: "go"))
    }
}

final class ThemeTests: XCTestCase {
    func testScopeFallsBackToLessSpecificName() {
        XCTAssertEqual(Theme.role(forScope: "title.function.invoke"), .function)
        XCTAssertEqual(Theme.role(forScope: "title.class.inherited"), .type)
        XCTAssertNil(Theme.role(forScope: "params"))
    }

    func testInnermostColourWinsAndUnknownScopesInherit() {
        let theme = Theme.balanced
        XCTAssertEqual(theme.style(forScopes: ["string", "subst"]).color, theme.style(for: .variable)?.color)
        XCTAssertEqual(theme.style(forScopes: ["title.function", "params"]).color, theme.style(for: .function)?.color)
        XCTAssertNil(theme.style(forScopes: []).color)
    }

    func testBalancedThemeIsReadableOnLightAndDarkNotes() {
        let light = RGBColor(hex: 0xFFFFFF), dark = RGBColor(hex: 0x1E1E1E)
        for (role, style) in Theme.balanced.styles {
            guard let color = style.color else { continue }
            XCTAssertGreaterThanOrEqual(color.contrast(with: light), 3.3, "\(role) on light")
            XCTAssertGreaterThanOrEqual(color.contrast(with: dark), 3.3, "\(role) on dark")
        }
    }

    func testClassicThemesMeetTextContrastOnTheirBackground() {
        for (theme, background) in [(Theme.classicLight, RGBColor(hex: 0xFFFFFF)), (.classicDark, RGBColor(hex: 0x1E1E1E))] {
            for (role, style) in theme.styles {
                guard let color = style.color else { continue }
                XCTAssertGreaterThanOrEqual(color.contrast(with: background), 4.0, "\(theme.id) \(role)")
            }
        }
    }

    func testUnknownThemeFallsBackToBalanced() {
        XCTAssertEqual(Theme.named("nope"), .balanced)
        XCTAssertEqual(Theme.named("classic-dark"), .classicDark)
    }
}

final class SmartQuotesTests: XCTestCase {
    func testStraightensCurlyQuotes() {
        XCTAssertEqual(SmartQuotes.straightened("resolve(\u{201C}Fresh!\u{201D}); it\u{2019}s"), "resolve(\"Fresh!\"); it's")
    }

    func testRestoreKeepsOriginalCharactersAndScopes() {
        let original = "x = \u{201C}hi\u{201D} // \u{2018}ok\u{2019}"
        let runs = [
            TokenRun(text: "x = "),
            TokenRun(text: "\"hi\"", scopes: ["string"]),
            TokenRun(text: " "),
            TokenRun(text: "// 'ok'", scopes: ["comment"]),
        ]
        XCTAssertEqual(SmartQuotes.restore(runs, from: original), [
            TokenRun(text: "x = "),
            TokenRun(text: "\u{201C}hi\u{201D}", scopes: ["string"]),
            TokenRun(text: " "),
            TokenRun(text: "// \u{2018}ok\u{2019}", scopes: ["comment"]),
        ])
    }

    func testRestoreLeavesMismatchedRunsAlone() {
        let runs = [TokenRun(text: "abc")]
        XCTAssertEqual(SmartQuotes.restore(runs, from: "abcd"), runs)
    }
}
