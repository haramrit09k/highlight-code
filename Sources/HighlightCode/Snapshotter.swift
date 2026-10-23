#if canImport(AppKit)
import AppKit
import HighlightCore

private final class SnapshotTarget: NSObject {
    static let shared = SnapshotTarget()
    @objc func noop() {}
}

/// `HighlightCode --snapshot <dir>` renders the settings window and a before/after example
/// to PNG files, for documentation and CI. It needs no screen-recording permission.
struct Snapshotter {
    let preferences: Preferences
    let formatter: () throws -> SnippetFormatter

    func run(outputDirectory: String) {
        let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for (name, appearance) in [("settings-light", NSAppearance.Name.aqua), ("settings-dark", .darkAqua)] {
            let window = SettingsView.makeWindow(preferences: preferences, preview: { options in
                try? formatter().format(SettingsView.sampleCode, options: options).attributed
            })
            window.appearance = NSAppearance(named: appearance)
            write(window.contentView, to: directory.appendingPathComponent("\(name).png"))
        }

        let code = """
        ```swift
        func greet(_ name: String) -> String {
            // Interpolation is highlighted too
            return "Hello, \\(name)!"
        }
        ```
        """
        if let formatted = try? formatter().format(code, options: preferences.renderOptions).attributed {
            let plain = NSAttributedString(string: CodeSnippet.parse(code).code, attributes: [
                .font: NSFont.systemFont(ofSize: 13),
            ])
            write(beforeAfter(plain: plain, highlighted: formatted), to: directory.appendingPathComponent("before-after.png"))
        }
        write(toolbarExample(), to: directory.appendingPathComponent("toolbar.png"))
        captureLanguageMenu(to: directory.appendingPathComponent("language-menu.png"))
    }

    /// The floating button under a selection, on light and dark notes.
    private func toolbarExample() -> NSView {
        let cell = NSSize(width: 460, height: 170)
        let padding: CGFloat = 16
        let container = NSView(frame: NSRect(x: 0, y: 0, width: cell.width * 2 + padding * 3, height: cell.height + padding * 2))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.85, alpha: 1).cgColor
        let code = "pizzaOrder\n    .then(pizza => console.log(pizza))\n    .catch(err => console.log(err))"

        for (column, dark) in [false, true].enumerated() {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let note = NSView(frame: NSRect(x: padding + CGFloat(column) * (cell.width + padding), y: padding, width: cell.width, height: cell.height))
            note.appearance = appearance
            note.wantsLayer = true
            note.layer?.backgroundColor = (dark ? NSColor(white: 0.118, alpha: 1) : .white).cgColor

            let text = NSTextView(frame: NSRect(x: 0, y: 70, width: cell.width, height: 90))
            text.drawsBackground = false
            text.textContainerInset = NSSize(width: 16, height: 10)
            text.textStorage?.setAttributedString(NSAttributedString(string: code, attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.textColor,
                // Stands in for the selection highlight, which is only drawn in a key window.
                .backgroundColor: NSColor(calibratedRed: 1, green: 0.8, blue: 0.3, alpha: dark ? 0.35 : 0.45),
            ]))
            note.addSubview(text)

            let toolbar = ToolbarView(target: SnapshotTarget.shared, highlight: #selector(SnapshotTarget.noop),
                                      chooseLanguage: #selector(SnapshotTarget.noop), vibrant: false)
            toolbar.appearance = appearance
            toolbar.setFrameOrigin(NSPoint(x: 16, y: 70 - 8 - ToolbarView.height))
            note.addSubview(toolbar)
            container.addSubview(note)
        }
        return container
    }

    /// Opens the language menu over a window and captures the screen with `screencapture`.
    /// Best effort: it needs a display (and, outside CI, screen-recording permission).
    private func captureLanguageMenu(to url: URL) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 560), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Highlight Code"
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let languages = (try? CodeHighlighter(bundle: .main).languages) ?? []
        let menu = LanguageMenu(languages: languages, recentIDs: ["javascript", "swift", "python"]).makeMenu()
        let frame = window.frame
        let timer = Timer(timeInterval: 1.0, repeats: false) { _ in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-x", "-R\(Int(frame.minX)),\(Int(NSScreen.main!.frame.height - frame.maxY)),\(Int(frame.width)),\(Int(frame.height))", url.path]
            try? task.run()
            task.waitUntilExit()
            print(FileManager.default.fileExists(atPath: url.path) ? "Wrote \(url.path)" : "Could not capture the language menu")
            menu.cancelTracking()
        }
        RunLoop.main.add(timer, forMode: .common)
        menu.popUp(positioning: nil, at: NSPoint(x: 40, y: window.contentView!.bounds.maxY - 30), in: window.contentView)
        NSApp.terminate(nil)
    }

    /// A 2×2 grid: plain vs highlighted text, each in light and dark text views.
    private func beforeAfter(plain: NSAttributedString, highlighted: NSAttributedString) -> NSView {
        let cell = NSSize(width: 420, height: 120)
        let padding: CGFloat = 16
        let container = NSView(frame: NSRect(x: 0, y: 0, width: cell.width * 2 + padding * 3, height: cell.height * 2 + padding * 3))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.85, alpha: 1).cgColor

        for (row, dark) in [false, true].enumerated() {
            for (column, text) in [plain, highlighted].enumerated() {
                let origin = NSPoint(
                    x: padding + CGFloat(column) * (cell.width + padding),
                    y: padding + CGFloat(1 - row) * (cell.height + padding)
                )
                let view = NSTextView(frame: NSRect(origin: origin, size: cell))
                view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                view.drawsBackground = true
                view.backgroundColor = dark ? NSColor(white: 0.118, alpha: 1) : .white
                view.textContainerInset = NSSize(width: 12, height: 12)
                view.textStorage?.setAttributedString(text)
                // Text without a colour follows the appearance, exactly like in Notes.
                view.textStorage?.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: text.length)) { value, range, _ in
                    if value == nil { view.textStorage?.addAttribute(.foregroundColor, value: NSColor.textColor, range: range) }
                }
                container.addSubview(view)
            }
        }
        return container
    }

    private func write(_ view: NSView?, to url: URL) {
        guard let view else { return }
        view.layoutSubtreeIfNeeded()
        if view.bounds.isEmpty {
            view.setFrameSize(view.fittingSize)
            view.layoutSubtreeIfNeeded()
        }
        guard !view.bounds.isEmpty, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("Could not render \(url.lastPathComponent): view size is \(view.bounds.size)")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("Wrote \(url.path)")
    }
}
#endif
