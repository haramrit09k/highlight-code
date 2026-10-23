#if canImport(AppKit)
import AppKit
import Combine
import HighlightCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// When launched by macOS to run a service, the request arrives right after launch;
    /// the settings window is shown only if none arrives within this delay.
    private static let welcomeDelay: TimeInterval = 0.75
    /// Without the floating button, the app quits after this long without a request,
    /// so it never lingers in the background.
    private static let idleTimeout: TimeInterval = 15 * 60

    private let arguments: [String]
    private let preferences = Preferences.shared
    private var cachedFormatter: SnippetFormatter?
    private var serviceProvider: ServiceProvider?
    private var settingsWindow: NSWindow?
    private var handledRequest = false
    private var idleTimer: Timer?
    private var trustTimer: Timer?
    private var trustRefreshTimer: Timer?
    private var explainedNotesAccessibility = false
    private var subscriptions: Set<AnyCancellable> = []
    private lazy var toolbar = SelectionToolbar { [weak self] text, pasteboard in
        guard let self else { return }
        try self.formatter().write(text, options: self.preferences.renderOptions, to: pasteboard)
        self.noteActivity()
    }

    init(arguments: [String]) {
        self.arguments = arguments
    }

    func formatter() throws -> SnippetFormatter {
        if let cachedFormatter { return cachedFormatter }
        let formatter = SnippetFormatter(highlighter: try CodeHighlighter(bundle: .main))
        cachedFormatter = formatter
        return formatter
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) {
            Snapshotter(preferences: preferences, formatter: formatter).run(outputDirectory: arguments[index + 1])
            return
        }

        NSApp.setActivationPolicy(.accessory)
        DebugLog.write("launched \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "?") from \(Bundle.main.bundlePath)")
        quitOtherCopies()
        let provider = ServiceProvider(
            preferences: preferences,
            formatter: formatter,
            onNotesNeedsAccessibility: { [weak self] in
                DispatchQueue.main.async { self?.explainNotesAccessibility() }
            }
        ) { [weak self] in
            self?.handledRequest = true
            self?.noteActivity()
        }
        serviceProvider = provider
        NSApp.servicesProvider = provider
        NSUpdateDynamicServices()

        preferences.accessibilityTrusted = SelectionToolbar.isTrusted
        preferences.$floatingButton
            .removeDuplicates()
            .sink { [weak self] enabled in
                // @Published fires before the stored value changes, so pass the new value on.
                DispatchQueue.main.async { self?.floatingButtonChanged(enabled) }
            }
            .store(in: &subscriptions)

        // With the floating button on, the app is usually started at login: stay quiet.
        guard !preferences.floatingButton else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.welcomeDelay) { [weak self] in
            guard let self, !self.handledRequest else { return }
            self.showSettings()
        }
    }

    /// Two copies (say, an old download and the one in Applications) would each show a
    /// floating button and answer Services at random, so only the newest launch keeps running.
    private func quitOtherCopies() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        for other in NSRunningApplication.runningApplications(withBundleIdentifier: id) where other != NSRunningApplication.current {
            DebugLog.write("quitting another running copy at \(other.bundleURL?.path ?? "?")")
            other.terminate()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func windowWillClose(_ notification: Notification) {
        trustRefreshTimer?.invalidate()
        noteActivity()
    }

    func showSettings() {
        idleTimer?.invalidate()
        preferences.accessibilityTrusted = SelectionToolbar.isTrusted
        if settingsWindow == nil {
            let window = SettingsView.makeWindow(
                preferences: preferences,
                preview: previewText,
                requestAccessibility: { [weak self] in self?.requestAccessibility() }
            )
            window.delegate = self
            settingsWindow = window
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshTrustWhileSettingsAreOpen()
    }

    /// Access can be granted or revoked in System Settings at any time, and macOS sends no
    /// notification, so keep the status in the settings window current while it is open.
    private func refreshTrustWhileSettingsAreOpen() {
        trustRefreshTimer?.invalidate()
        trustRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let trusted = SelectionToolbar.isTrusted
            guard trusted != self.preferences.accessibilityTrusted else { return }
            self.preferences.accessibilityTrusted = trusted
            if trusted, self.preferences.floatingButton { self.toolbar.start() }
        }
    }

    private func previewText(_ options: RenderOptions) -> NSAttributedString? {
        try? formatter().format(SettingsView.sampleCode, options: options).attributed
    }

    // MARK: Floating button

    private func floatingButtonChanged(_ enabled: Bool) {
        guard enabled else {
            trustTimer?.invalidate()
            toolbar.stop()
            noteActivity()
            return
        }
        idleTimer?.invalidate()
        if SelectionToolbar.isTrusted {
            preferences.accessibilityTrusted = true
            toolbar.start()
        } else {
            SelectionToolbar.requestTrust()
            waitForTrust()
        }
    }

    func requestAccessibility() {
        SelectionToolbar.requestTrust()
        waitForTrust()
    }

    /// Shown (once per launch) when "Highlight Code" is used in Notes without Accessibility
    /// access: Notes then drops the colours, see NotesPaster.
    private func explainNotesAccessibility() {
        guard !explainedNotesAccessibility else { return }
        explainedNotesAccessibility = true
        let alert = NSAlert()
        alert.messageText = "Let Highlight Code paste into Notes?"
        alert.informativeText = """
        Notes only keeps the colours of pasted code when it is pasted with Edit › Paste and \
        Retain Style. With Accessibility access, Highlight Code does that for you.

        Without it, choose Services › Copy Highlighted Code, then Edit › Paste and Retain \
        Style in your note.
        """
        alert.addButton(withTitle: "Grant Access…")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            requestAccessibility()
        }
    }

    /// macOS has no notification for the Accessibility grant, so poll until it arrives.
    private func waitForTrust() {
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, SelectionToolbar.isTrusted else { return }
            timer.invalidate()
            self.preferences.accessibilityTrusted = true
            if self.preferences.floatingButton { self.toolbar.start() }
        }
    }

    // MARK: Idle quit

    private func noteActivity() {
        idleTimer?.invalidate()
        guard !preferences.floatingButton else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idleTimeout, repeats: false) { [weak self] _ in
            guard let self, self.settingsWindow?.isVisible != true, !self.preferences.floatingButton else { return }
            NSApp.terminate(nil)
        }
    }
}
#endif
