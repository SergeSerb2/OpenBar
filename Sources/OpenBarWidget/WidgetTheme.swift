import AppKit
import OpenBarCore
import SwiftUI

/// Widget-side accessors for the shared design tokens in OpenBarCore.
///
/// The widget cannot import the app module, so this mirrors the small part of `OpenBarTheme` the
/// tiles need. In accented and vibrant rendering modes WidgetKit replaces these colors with its own
/// tint; tiles must still read correctly there through shape, symbol, and text alone.
enum WidgetTheme {
    enum Colors {
        /// Widgets always use Iris; the system applies the user's accent in accented mode.
        static let accent = Color(nsColor: OpenBarPalette.accent.nsColor)
        static let ok = Color(nsColor: OpenBarPalette.ok.nsColor)
        static let warning = Color(nsColor: OpenBarPalette.warning.nsColor)
        static let critical = Color(nsColor: OpenBarPalette.critical.nsColor)
        static let stale = Color(nsColor: OpenBarPalette.stale.nsColor)
        static let meterTrack = Color(nsColor: OpenBarPalette.meterTrack.nsColor)

        static func tone(_ tone: OpenBarQuotaTone) -> Color? {
            tone.color.map { Color(nsColor: $0.nsColor) }
        }
    }

    enum Fonts {
        /// Hero figure. Widgets size it per family, so the size is a parameter.
        static func hero(size: CGFloat = OpenBarTypeRole.hero.size) -> Font {
            .system(size: size, weight: .semibold).monospacedDigit()
        }

        static let cardTitle = Font.headline
        static let laneTitle = Font.callout.weight(.medium)
        static let laneValue = Font.body.weight(.semibold).monospacedDigit()
        static let meta = Font.subheadline.monospacedDigit()
        static let caption = Font.caption
    }
}
