import Foundation

/// Where to put the floating "Highlight" button for a text selection.
public enum ToolbarPlacement {
    public enum Edge: String, CaseIterable {
        case above, below
    }

    /// - Parameters:
    ///   - selection: the selection's bounds as reported by Accessibility, in global
    ///     coordinates with the origin at the top-left of the primary screen (y grows down).
    ///   - primaryScreenHeight: height of the primary screen, used to flip into AppKit
    ///     coordinates (origin bottom-left, y grows up).
    ///   - visibleFrame: the visible frame (AppKit coordinates) of the screen holding the
    ///     selection; the button is kept inside it.
    ///   - size: the button panel's size.
    ///   - edge: which side of the selection to prefer. Below is the default because other
    ///     Notes add-ons (such as Pronotes) put their toolbar above the selection.
    /// - Returns: the panel's frame in AppKit coordinates, on the preferred side of the
    ///   selection, or on the other side when the preferred one has no room.
    public static func frame(
        forSelection selection: CGRect,
        primaryScreenHeight: CGFloat,
        visibleFrame: CGRect,
        size: CGSize,
        edge: Edge = .below,
        gap: CGFloat = 8
    ) -> CGRect {
        let aboveY = primaryScreenHeight - selection.minY + gap
        let belowY = primaryScreenHeight - selection.maxY - gap - size.height
        let fitsAbove = aboveY + size.height <= visibleFrame.maxY
        let fitsBelow = belowY >= visibleFrame.minY

        var origin = CGPoint(x: selection.minX, y: 0)
        switch edge {
        case .above: origin.y = fitsAbove || !fitsBelow ? aboveY : belowY
        case .below: origin.y = fitsBelow || !fitsAbove ? belowY : aboveY
        }
        origin.x = min(max(origin.x, visibleFrame.minX + gap), visibleFrame.maxX - size.width - gap)
        origin.y = min(max(origin.y, visibleFrame.minY + gap), visibleFrame.maxY - size.height - gap)
        return CGRect(origin: origin, size: size)
    }
}
