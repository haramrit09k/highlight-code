@testable import HighlightCore
import XCTest

final class LanguageCatalogTests: XCTestCase {
    private let pairs: [(id: String, name: String)] = [
        ("rust", "Rust"), ("php", "php"), ("php-template", "PHP template"), ("xml", "HTML, XML"),
        ("python", "Python"), ("python-repl", "python-repl"), ("bash", "Bash"), ("ocaml", "OCaml"),
    ]

    func testHidesEmbeddedGrammarsRenamesAndSorts() {
        let names = LanguageCatalog.languages(fromHighlightJS: pairs).map(\.name)
        XCTAssertEqual(names, ["Bash", "HTML / XML", "OCaml", "PHP", "Python", "Rust"])
    }

    func testSectionsPutRecentFirstWithoutDuplicatingPopular() {
        let all = LanguageCatalog.languages(fromHighlightJS: pairs)
        let sections = LanguageCatalog.sections(all: all, recentIDs: ["rust", "python", "missing"])
        XCTAssertEqual(sections.recent.map(\.id), ["rust", "python"])
        XCTAssertFalse(sections.popular.contains { $0.id == "rust" || $0.id == "python" })
        XCTAssertEqual(sections.popular.map(\.id), ["php", "bash", "xml"])
        XCTAssertEqual(sections.all, all)
    }

    func testRecentLanguagesMoveToFrontAndAreCapped() {
        var recent = RecentLanguages()
        for id in ["a", "b", "c", "d", "e", "f"] { recent.use(id) }
        XCTAssertEqual(recent.ids, ["f", "e", "d", "c", "b"])
        recent.use("d")
        XCTAssertEqual(recent.ids, ["d", "f", "e", "c", "b"])
        XCTAssertEqual(RecentLanguages(ids: ["1", "2", "3", "4", "5", "6"]).ids.count, RecentLanguages.limit)
    }
}
