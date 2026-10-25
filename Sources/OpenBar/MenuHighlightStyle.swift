import OpenBarCore
import SwiftUI

extension EnvironmentValues {
    @Entry var menuItemHighlighted: Bool = false
    /// Optional live-refresh monitor injected into menu card views so the provider card
    /// subtitle can reflect the in-flight "Refreshing…" state in place while the NSMenu
    /// stays open, without rebuilding the menu during AppKit tracking.
    @Entry var menuCardRefreshMonitor: MenuCardRefreshMonitor?
}

/// Text and fill colors for hosted menu rows. A highlighted row sits on the accent fill, so every
/// role switches to the selected-menu-item text color (spec §9.2 "Highlight").
enum MenuHighlightStyle {
    static let selectionText = Color(nsColor: .selectedMenuItemTextColor)
    static let normalPrimaryText = Color(nsColor: .labelColor)
    static let normalSecondaryText = Color(nsColor: .secondaryLabelColor)
    static let normalTertiaryText = Color(nsColor: .tertiaryLabelColor)

    static func primary(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText : self.normalPrimaryText
    }

    static func secondary(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText : self.normalSecondaryText
    }

    static func tertiary(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText.opacity(0.7) : self.normalTertiaryText
    }

    static func error(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText : OpenBarTheme.Colors.critical
    }

    /// Emphasis for a card's status label (for example the active account).
    /// A highlighted row still uses the selection color so contrast is kept.
    static func accent(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText : OpenBarTheme.Colors.accent
    }

    static func progressTrack(_ highlighted: Bool) -> Color {
        highlighted
            ? self.selectionText.opacity(OpenBarMenuStyle.highlightedTrackOpacity)
            : OpenBarTheme.Colors.meterTrack
    }

    static func progressTint(_ highlighted: Bool, fallback: Color) -> Color {
        highlighted ? self.selectionText : fallback
    }

    static func selectionBackground(_ highlighted: Bool) -> Color {
        highlighted ? OpenBarTheme.Colors.accentFill : .clear
    }
}
