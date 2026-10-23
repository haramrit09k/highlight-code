import Foundation

/// Where to put the floating "Highlight" button for a text selection.
public enum ToolbarPlacement {
    /// - Parameters:
    ///   - selection: the selection's bounds as reported by Accessibility, in global
    ///     coordinates with the origin at the top-left of the primary screen (y grows down).
    ///   - primaryScreenHeight: height of the primary screen, used to flip into AppKit
    ///     coordinates (origin bottom-left, y grows up).
    ///   - visibleFrame: the visible frame (AppKit coordinates) of the screen holding the
    ///     selection; the button is kept inside it.
    ///   - size: the button panel's size.
    /// - Returns: the panel's frame in AppKit coordinates: above the selection's first line,
    ///   or below the selection when there is no room above.
    public static func frame(
        forSelection selection: CGRect,
        primaryScreenHeight: CGFloat,
        visibleFrame: CGRect,
        size: CGSize,
        gap: CGFloat = 8
    ) -> CGRect {
        let top = primaryScreenHeight - selection.minY
        let bottom = primaryScreenHeight - selection.maxY

        var origin = CGPoint(x: selection.minX, y: top + gap)
        if origin.y + size.height > visibleFrame.maxY {
            origin.y = bottom - gap - size.height
        }
        origin.x = min(max(origin.x, visibleFrame.minX + gap), visibleFrame.maxX - size.width - gap)
        origin.y = min(max(origin.y, visibleFrame.minY + gap), visibleFrame.maxY - size.height - gap)
        return CGRect(origin: origin, size: size)
    }
}
