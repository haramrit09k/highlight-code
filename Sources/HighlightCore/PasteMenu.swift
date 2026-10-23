import Foundation

/// Picks the Edit menu item to paste highlighted code into Apple Notes with.
///
/// Notes keeps the colour and font of pasted rich text only with Edit › Paste and Retain
/// Style, which has no keyboard shortcut. Plain Paste (⌘V) keeps bold and italic but drops
/// colours, and Paste and Match Style (⌥⇧⌘V) drops all formatting.
public enum PasteMenu {
    public struct Item: Equatable {
        public var title: String
        /// The shortcut's character, e.g. "V", or nil when the item has none.
        public var key: String?
        /// kAXMenuItemCmdModifiersAttribute: 0 = ⌘ only, 1 = ⇧, 2 = ⌥, 4 = ⌃, 8 = no ⌘.
        public var modifiers: Int

        public init(title: String, key: String? = nil, modifiers: Int = 0) {
            self.title = title
            self.key = key
            self.modifiers = modifiers
        }

        var isPaste: Bool { key?.uppercased() == "V" && modifiers == 0 }
        var isPasteAndMatchStyle: Bool { key?.uppercased() == "V" && modifiers == 3 }
    }

    /// The Edit menu is the one holding ⌘V Paste.
    public static func isEditMenu(_ items: [Item]) -> Bool {
        items.contains { $0.isPaste }
    }

    /// Returns the index of the item to press in the Edit menu's `items`:
    /// 1. "Paste and Retain Style", by title (English);
    /// 2. otherwise the item right after Paste and Match Style when it has no shortcut,
    ///    which is where Notes puts it in every language;
    /// 3. otherwise plain Paste.
    public static func indexToPress(in items: [Item]) -> Int? {
        if let index = items.firstIndex(where: { $0.title.localizedCaseInsensitiveContains("retain style") }) {
            return index
        }
        if let match = items.firstIndex(where: \.isPasteAndMatchStyle),
           items.indices.contains(match + 1), items[match + 1].key == nil, !items[match + 1].title.isEmpty {
            return match + 1
        }
        return items.firstIndex(where: \.isPaste)
    }
}
