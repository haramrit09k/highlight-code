#if canImport(AppKit)
import AppKit
import HighlightCore

/// What the user picked in the language menu.
enum LanguageChoice: Equatable {
    /// Use a Markdown fence if there is one, otherwise auto-detect.
    case automatic
    case language(String)

    var languageID: String? {
        if case .language(let id) = self { return id }
        return nil
    }
}

/// The pop-up menu used by "Highlight Code As…" and the floating button's ▾:
/// Auto-detect, recently used, popular, then every language in a submenu.
/// Typing while it is open jumps to a matching item (standard NSMenu type-select).
final class LanguageMenu: NSObject {
    private let languages: [LanguageInfo]
    private let recentIDs: [String]
    private var choice: LanguageChoice?

    init(languages: [LanguageInfo], recentIDs: [String]) {
        self.languages = languages
        self.recentIDs = recentIDs
    }

    /// Shows the menu and blocks until the user picks something or dismisses it.
    /// - Parameters:
    ///   - point: in `view`'s coordinates, or in screen coordinates when `view` is nil.
    /// - Returns: the choice, or nil when the menu was dismissed.
    func pick(at point: NSPoint, in view: NSView?) -> LanguageChoice? {
        choice = nil
        // Activate while the menu is open so typing goes to the menu (type-select) instead
        // of replacing the selection in Notes; then hand focus straight back.
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        makeMenu().popUp(positioning: nil, at: point, in: view)
        if let previous, previous != NSRunningApplication.current {
            previous.activate(options: [])
        }
        return choice
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Highlight As")
        menu.autoenablesItems = false

        menu.addItem(sectionHeader("Highlight As"))
        let auto = item(title: "Auto-detect", choice: .automatic)
        auto.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)
        menu.addItem(auto)

        let sections = LanguageCatalog.sections(all: languages, recentIDs: recentIDs)
        if !sections.recent.isEmpty {
            menu.addItem(.separator())
            menu.addItem(sectionHeader("Recent"))
            sections.recent.forEach { menu.addItem(item(for: $0)) }
        }
        menu.addItem(.separator())
        menu.addItem(sectionHeader("Popular"))
        sections.popular.forEach { menu.addItem(item(for: $0)) }

        menu.addItem(.separator())
        let allItem = NSMenuItem(title: "All Languages", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "All Languages")
        sections.all.forEach { submenu.addItem(item(for: $0)) }
        allItem.submenu = submenu
        menu.addItem(allItem)
        return menu
    }

    private func item(for language: LanguageInfo) -> NSMenuItem {
        item(title: language.name, choice: .language(language.id))
    }

    private func item(title: String, choice: LanguageChoice) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = choice.languageID
        return item
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) {
            return NSMenuItem.sectionHeader(title: title)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func choose(_ sender: NSMenuItem) {
        choice = (sender.representedObject as? String).map(LanguageChoice.language) ?? .automatic
    }
}
#endif
