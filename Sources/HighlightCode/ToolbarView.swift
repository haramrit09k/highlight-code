#if canImport(AppKit)
import AppKit

/// The floating pill shown next to a selection in Notes:  [ </> Highlight Code | ▾ ]
/// The main half highlights with auto-detection; the chevron opens the language menu.
final class ToolbarView: NSView {
    static let height: CGFloat = 36
    private static let inset: CGFloat = 4

    let highlightButton: HoverButton
    let languageButton: HoverButton

    /// - Parameter vibrant: false draws a solid background instead of the translucent
    ///   material; off-screen snapshots cannot capture the material.
    init(target: AnyObject, highlight: Selector, chooseLanguage: Selector, vibrant: Bool = true) {
        highlightButton = HoverButton(
            title: "Highlight Code",
            symbol: "chevron.left.forwardslash.chevron.right",
            target: target, action: highlight
        )
        highlightButton.toolTip = "Replace the selection with highlighted code (language detected automatically)"
        languageButton = HoverButton(title: nil, symbol: "chevron.down", target: target, action: chooseLanguage)
        languageButton.toolTip = "Choose the language…"
        languageButton.setAccessibilityLabel("Highlight as language")

        let highlightWidth = highlightButton.intrinsicContentSize.width + 28
        let languageWidth: CGFloat = 34
        let size = NSSize(width: Self.inset * 2 + highlightWidth + 1 + languageWidth, height: Self.height)
        super.init(frame: NSRect(origin: .zero, size: size))

        wantsLayer = true
        layer?.cornerRadius = Self.height / 2
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor

        if vibrant {
            let material = NSVisualEffectView(frame: bounds)
            material.material = .popover
            material.state = .active
            material.blendingMode = .behindWindow
            material.autoresizingMask = [.width, .height]
            addSubview(material)
        } else {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }

        let buttonHeight = Self.height - Self.inset * 2
        highlightButton.frame = NSRect(x: Self.inset, y: Self.inset, width: highlightWidth, height: buttonHeight)
        languageButton.frame = NSRect(x: highlightButton.frame.maxX + 1, y: Self.inset, width: languageWidth, height: buttonHeight)
        let divider = NSBox(frame: NSRect(x: highlightButton.frame.maxX, y: 10, width: 1, height: Self.height - 20))
        divider.boxType = .separator

        addSubview(highlightButton)
        addSubview(divider)
        addSubview(languageButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateLayer() {
        super.updateLayer()
        layer?.borderColor = NSColor.separatorColor.cgColor
        if layer?.backgroundColor != nil {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }

    override var wantsUpdateLayer: Bool { true }
}

/// A borderless button with an accent-tinted symbol and a rounded hover highlight.
final class HoverButton: NSButton {
    private var hovering = false {
        didSet { needsDisplay = true }
    }

    init(title: String?, symbol: String, target: AnyObject, action: Selector) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        focusRingType = .none

        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?.withSymbolConfiguration(configuration)
        contentTintColor = .controlAccentColor
        if let title {
            attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ])
            imagePosition = .imageLeading
            imageHugsTitle = true
        } else {
            self.title = ""
            imagePosition = .imageOnly
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        if hovering || isHighlighted {
            NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.16 : 0.09).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        }
        super.draw(dirtyRect)
    }
}
#endif
