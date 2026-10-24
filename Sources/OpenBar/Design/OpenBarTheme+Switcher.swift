import AppKit
import OpenBarCore

/// Switcher tokens from docs/design/README.md §9.2 that the shared token files do not carry yet.
/// Owned by the Menu agent until the lead folds them into `OpenBarTheme.swift` / `OpenBarDesignTokens.swift`.
extension OpenBarTheme.NSColors {
    /// Hairline around the switcher rail, drawn only with Increase Contrast.
    static var switcherRailStroke: NSColor {
        OpenBarPalette.cardStroke.nsColor
    }

    /// Hover plate behind an unselected switcher segment: `labelColor` at 6 %.
    static var switcherHover: NSColor {
        NSColor.labelColor.withAlphaComponent(0.06)
    }

    /// Weekly-strip track on the selected (`accentFill`) segment: white at 30 %.
    static var switcherSelectedTrack: NSColor {
        NSColor.white.withAlphaComponent(0.3)
    }
}

extension OpenBarTheme {
    /// Switcher geometry and type (§9.2). The rail reuses the card inset and the hairline spacing step.
    enum Switcher {
        /// Rail inset from the menu's content edge, matching the cards below it.
        static let railInset = CGFloat(OpenBarMenuMetrics.cardInset)
        /// Padding between the rail and its segments, on all four sides.
        static let railPadding = CGFloat(OpenBarSpacing.hairline)
        /// Gap between the weekly strip's fill and its track (the "open" motif).
        static let stripSplitGap: CGFloat = 1
        /// Title under the icon in the stacked form: the caption role, medium on the selected segment.
        static let stackedTitleSize = CGFloat(OpenBarTypeRole.caption.size)
        /// Worst-lane quota figure ("62%"), tabular digits.
        static let numeralSize: CGFloat = 10
        /// Filled tone symbol before a warning or critical figure.
        static let numeralSymbolSize: CGFloat = 8
    }
}
