#if canImport(AppKit) && canImport(JavaScriptCore)
import AppKit
@testable import HighlightCore
import XCTest

final class CodeHighlighterTests: XCTestCase {
    private static let script: String = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/highlight.js")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()

    private var highlighter: CodeHighlighter!

    override func setUpWithError() throws {
        highlighter = try CodeHighlighter(script: Self.script)
    }

    func testBundleLoadsAllLanguages() {
        XCTAssertGreaterThanOrEqual(highlighter.supportedLanguages.count, 50)
        for language in CodeHighlighter.autoDetectLanguages {
            XCTAssertTrue(highlighter.supportedLanguages.contains(language), language)
        }
    }

    func testExplicitLanguageAndAlias() {
        let result = highlighter.highlight("def f(): pass", language: "py")
        XCTAssertEqual(result.language, "python")
        XCTAssertEqual(result.runs.first, TokenRun(text: "def", scopes: ["keyword"]))
    }

    func testTextIsPreservedExactly() {
        let code = "if (a < b && c > d) {\n\treturn \"x & y\"; // 👋\n}\n"
        XCTAssertEqual(highlighter.highlight(code).runs.map(\.text).joined(), code)
    }

    func testAutoDetection() {
        let samples: [(String, String)] = [
            ("python", "import os\ndef main(argv):\n    for a in argv:\n        print(f\"hi {a}\")\n"),
            ("javascript", "const add = (a, b) => a + b;\nexport default function App() {\n  return items.map(i => i.id);\n}"),
            ("swift", "struct User: Codable {\n    let name: String\n    var age: Int?\n}\nguard let u = user else { return }"),
            ("go", "package main\nimport \"fmt\"\nfunc main() {\n\tfmt.Println(\"hi\")\n}"),
            ("sql", "SELECT id, name FROM users WHERE age > 21 ORDER BY name;"),
            ("bash", "#!/bin/bash\nfor f in *.txt; do\n  echo \"$f\"\ndone"),
            ("rust", "fn main() {\n    let v: Vec<i32> = vec![1, 2];\n    println!(\"{:?}\", v);\n}"),
            ("java", "public class Main {\n    public static void main(String[] args) {\n        System.out.println(\"x\");\n    }\n}"),
            ("json", "{\"a\": [1, 2, {\"b\": null}]}"),
            ("dockerfile", "FROM node:20\nWORKDIR /app\nCOPY . .\nRUN npm ci\nCMD [\"node\",\"index.js\"]"),
            ("yaml", "name: CI\non: [push]\njobs:\n  build:\n    runs-on: ubuntu-latest"),
        ]
        for (expected, code) in samples {
            XCTAssertEqual(highlighter.highlight(code).language, expected, code)
        }
    }

    func testUnknownLanguageFallsBackToAutoDetection() {
        XCTAssertEqual(highlighter.highlight("SELECT 1 FROM t;", language: "notalanguage").language, "sql")
    }

    func testRendererColoursTokensAndLeavesPlainTextUncoloured() throws {
        let formatter = SnippetFormatter(highlighter: highlighter)
        let output = formatter.format("```python\nreturn x\n```", options: RenderOptions())
        let attributed = output.attributed
        XCTAssertEqual(attributed.string, "return x")
        XCTAssertEqual(output.language, "python")

        let keywordColor = try XCTUnwrap(attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        let expected = try XCTUnwrap(Theme.balanced.style(for: .keyword)?.color)
        XCTAssertEqual(Int((keywordColor.redComponent * 255).rounded()), Int(expected.red))
        XCTAssertNil(attributed.attribute(.foregroundColor, at: 7, effectiveRange: nil))

        let font = try XCTUnwrap(attributed.attribute(.font, at: 7, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(font.isFixedPitch)
        XCTAssertEqual(font.pointSize, 13)
    }

    func testLanguageListForPicker() {
        let languages = highlighter.languages
        XCTAssertGreaterThanOrEqual(languages.count, 50)
        XCTAssertTrue(languages.contains(LanguageInfo(id: "cpp", name: "C++")))
        XCTAssertTrue(languages.contains(LanguageInfo(id: "xml", name: "HTML / XML")))
        XCTAssertFalse(languages.contains { $0.id == "php-template" })
        for id in LanguageCatalog.popularIDs {
            XCTAssertTrue(languages.contains { $0.id == id }, id)
        }
    }

    func testPickedLanguageOverridesFenceAndDetection() {
        let formatter = SnippetFormatter(highlighter: highlighter)
        let fenced = formatter.format("```python\nlet x = 1\n```", language: "swift", options: RenderOptions())
        XCTAssertEqual(fenced.language, "swift")
        XCTAssertEqual(fenced.attributed.string, "let x = 1")

        let picked = formatter.format("SELECT 1 FROM t;", language: "rb", options: RenderOptions())
        XCTAssertEqual(picked.language, "ruby")

        let plain = formatter.format("def f(): pass", language: "plaintext", options: RenderOptions())
        XCTAssertNil(plain.attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil))
    }

    func testSmartQuotedStringsAreHighlightedAndKept() throws {
        // As typed into Notes, with smart quotes and tabs.
        let code = "const pizzaOrder = new Promise((resolve, reject) => {\n\tlet isPizzaReady = true;\n\tif(isPizzaReady) {\n\t\tresolve(\u{201C}Fresh pepperoni pizza!\u{201D}); //success\n\t}\n});"
        let output = SnippetFormatter(highlighter: highlighter).format(code, options: RenderOptions())
        XCTAssertEqual(output.attributed.string, code)
        XCTAssertEqual(output.language, "javascript")

        let quote = (code as NSString).range(of: "\u{201C}Fresh")
        let color = try XCTUnwrap(output.attributed.attribute(.foregroundColor, at: quote.location, effectiveRange: nil) as? NSColor)
        let expected = try XCTUnwrap(Theme.balanced.style(for: .string)?.color)
        XCTAssertEqual(Int((color.greenComponent * 255).rounded()), Int(expected.green))
    }

    func testPasteboardGetsRTFAndPlainText() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("HighlightCodeTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        SnippetFormatter(highlighter: highlighter).write("let a = \"b\"", options: RenderOptions(), to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "let a = \"b\"")
        let rtf = try XCTUnwrap(pasteboard.data(forType: .rtf))
        let text = String(decoding: rtf, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("{\\rtf1"))
        XCTAssertTrue(text.contains("Menlo"))
        XCTAssertTrue(text.contains("\\colortbl"))
    }
}
#endif
