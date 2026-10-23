#if canImport(AppKit)
import AppKit
import HighlightCore
import ServiceManagement

/// Settings shared by the Services, the floating button and the settings window.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    static let fontSizes: ClosedRange<Double> = 9...24

    private let defaults: UserDefaults

    @Published var themeID: String {
        didSet { defaults.set(themeID, forKey: "theme") }
    }

    @Published var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: "fontSize") }
    }

    /// Show the floating "Highlight Code" button when text is selected in Notes.
    @Published var floatingButton: Bool {
        didSet { defaults.set(floatingButton, forKey: "floatingButton") }
    }

    /// Which side of the selection the floating button prefers.
    @Published var toolbarEdge: ToolbarPlacement.Edge {
        didSet { defaults.set(toolbarEdge.rawValue, forKey: "toolbarEdge") }
    }

    /// Languages recently picked in the language menu, newest first.
    @Published var recentLanguages: RecentLanguages {
        didSet { defaults.set(recentLanguages.ids, forKey: "recentLanguages") }
    }

    /// Whether the Accessibility permission (needed by the floating button) is granted.
    /// Not persisted: macOS is the source of truth, and AppDelegate keeps it current.
    @Published var accessibilityTrusted = false

    /// Mirrors the app's login item, which keeps the floating button available after a restart.
    @Published var openAtLogin: Bool {
        didSet {
            guard openAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if openAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Highlight Code: could not change login item: \(error)")
                DispatchQueue.main.async { self.openAtLogin = SMAppService.mainApp.status == .enabled }
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        themeID = Theme.named(defaults.string(forKey: "theme")).id
        let stored = defaults.double(forKey: "fontSize")
        fontSize = Self.fontSizes.contains(stored) ? stored : 13
        floatingButton = defaults.bool(forKey: "floatingButton")
        toolbarEdge = ToolbarPlacement.Edge(rawValue: defaults.string(forKey: "toolbarEdge") ?? "") ?? .below
        recentLanguages = RecentLanguages(ids: defaults.stringArray(forKey: "recentLanguages") ?? [])
        openAtLogin = SMAppService.mainApp.status == .enabled
    }

    func noteUsed(_ choice: LanguageChoice) {
        if let id = choice.languageID { recentLanguages.use(id) }
    }

    var renderOptions: RenderOptions {
        RenderOptions(theme: Theme.named(themeID), fontSize: CGFloat(fontSize))
    }
}
#endif
