#if canImport(AppKit)
import AppKit
import HighlightCore

/// `HighlightCode --snapshot <dir>` renders the settings window and a before/after example
/// to PNG files, for documentation and CI. It needs no screen-recording permission.
struct Snapshotter {
    let preferences: Preferences
    let formatter: () throws -> SnippetFormatter

    func run(outputDirectory: String) {
        let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for (name, appearance) in [("settings-light", NSAppearance.Name.aqua), ("settings-dark", .darkAqua)] {
            let window = SettingsView.makeWindow(preferences: preferences) { options in
                try? formatter().format(SettingsView.sampleCode, options: options).attributed
            }
            window.appearance = NSAppearance(named: appearance)
            write(window.contentView, to: directory.appendingPathComponent("\(name).png"),
                  background: .windowBackgroundColor, appearance: window.appearance)
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

    /// - Parameter background: drawn under the view; off-screen rendering skips the
    ///   window background, which would leave dark-mode text on transparent pixels.
    private func write(_ view: NSView?, to url: URL, background: NSColor? = nil, appearance: NSAppearance? = nil) {
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
        var output = rep
        if let background, let flattened = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: flattened)
            let rect = NSRect(origin: .zero, size: flattened.size)
            (appearance ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
                background.setFill()
                rect.fill()
            }
            rep.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
            output = flattened
        }
        try? output.representation(using: .png, properties: [:])?.write(to: url)
        print("Wrote \(url.path)")
    }
}
#endif
