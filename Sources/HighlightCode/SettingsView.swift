#if canImport(AppKit)
import AppKit
import HighlightCore
import SwiftUI

/// The window shown when the app is opened directly: setup steps, style options and a
/// live preview on light and dark note backgrounds.
struct SettingsView: View {
    static let sampleCode = """
    from dataclasses import dataclass

    @dataclass
    class Card:
        term: str
        score: int = 0  # 0 = new

        def review(self, ok: bool):
            self.score += 1 if ok else -1
            return max(self.score, 0)
    """

    @ObservedObject var preferences: Preferences
    let preview: (RenderOptions) -> NSAttributedString?
    let requestAccessibility: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    step(1, "Select code in a note. Markdown fences such as ```python set the language.")
                    step(2, "Click the floating Highlight Code button (see below), or right-click the selection and choose Services › Highlight Code.")
                    step(3, "Optional: give it a shortcut in System Settings › Keyboard › Keyboard Shortcuts › Services › Text.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            } label: {
                Text("How to use").font(.headline)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        if preferences.accessibilityTrusted {
                            Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Accessibility access needed for colours in Notes", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Button("Grant Access…", action: requestAccessibility)
                        }
                    }
                    if !preferences.accessibilityTrusted {
                        Text("Already switched on in System Settings? macOS ties the permission to one exact build of the app, so after an update the old entry no longer applies. Select Highlight Code in Privacy & Security › Accessibility, remove it with –, then click Grant Access… again.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Toggle("Show a “Highlight Code” button when I select text in Notes", isOn: $preferences.floatingButton)
                    if preferences.floatingButton {
                        Toggle("Open at login, so the button is always available", isOn: $preferences.openAtLogin)
                            .padding(.leading, 20)
                    }
                    Text("Notes only keeps the colours of pasted code when it is pasted with Edit › Paste and Retain Style. Accessibility access lets Highlight Code do that for you, and see your selection for the floating button, the same way screen readers do. Notes itself is never modified.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            } label: {
                Text("Apple Notes").font(.headline)
            }
            GroupBox {
                HStack(spacing: 24) {
                    Picker("Theme", selection: $preferences.themeID) {
                        ForEach(Theme.all) { theme in
                            Text(theme.name).tag(theme.id)
                        }
                    }
                    .frame(maxWidth: 280)
                    Stepper("Font size: \(Int(preferences.fontSize)) pt", value: $preferences.fontSize, in: Preferences.fontSizes)
                    Spacer()
                }
                .padding(6)
            } label: {
                Text("Style").font(.headline)
            }
            HStack(spacing: 12) {
                previewCard(dark: false)
                previewCard(dark: true)
            }
            HStack {
                Button("Open Keyboard Shortcuts…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Spacer()
                Text("Runs only when you use it; nothing leaves your Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 720)
        // Normally the window paints this; drawing it here keeps off-screen snapshots
        // (which start from white) correct in dark mode.
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("Highlight Code").font(.title.bold())
                Text("Syntax highlighting for code snippets in Apple Notes.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            Text(text)
        }
    }

    private func previewCard(dark: Bool) -> some View {
        let text = preview(preferences.renderOptions).map(Self.swiftUIText) ?? Text("Preview unavailable")
        return VStack(alignment: .leading, spacing: 8) {
            Text(dark ? "Dark note" : "Light note")
                .font(.caption)
                .foregroundStyle(.secondary)
            text
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(dark ? Color(white: 0.118) : .white))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12)))
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    /// Converts AppKit attributes to SwiftUI ones; uncoloured runs use the primary text colour,
    /// just as they would in a note.
    static func swiftUIText(_ attributed: NSAttributedString) -> Text {
        var result = AttributedString()
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            var run = AttributedString(attributed.attributedSubstring(from: range).string)
            if let font = attributes[.font] as? NSFont {
                run.font = Font(font as CTFont)
            }
            if let color = attributes[.foregroundColor] as? NSColor {
                run.foregroundColor = Color(nsColor: color)
            }
            result += run
        }
        return Text(result)
    }

    static func makeWindow(
        preferences: Preferences,
        preview: @escaping (RenderOptions) -> NSAttributedString?,
        requestAccessibility: @escaping () -> Void = {}
    ) -> NSWindow {
        let controller = NSHostingController(rootView: SettingsView(
            preferences: preferences, preview: preview, requestAccessibility: requestAccessibility
        ))
        let window = NSWindow(contentViewController: controller)
        // SwiftUI sizes the window lazily on first display; size it now so it centres
        // correctly and can be rendered off-screen by the snapshot mode.
        window.setContentSize(controller.view.fittingSize)
        window.title = "Highlight Code"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        return window
    }
}
#endif
