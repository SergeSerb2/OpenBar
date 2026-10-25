import OpenBarCore
import SwiftUI

/// Widget-side accessors for the shared design tokens in OpenBarCore.
///
/// The widget cannot import the app module, so this mirrors the small part of `OpenBarTheme` the
/// tiles need. In accented and vibrant rendering modes WidgetKit replaces these colors with its own
/// tint; tiles must still read correctly there through shape, symbol, and text alone.
///
/// Colors come from `WidgetPalette` (below), which resolves each token for the view's own color
/// scheme, contrast, and rendering mode. Widgets always use Iris; the system applies the user's
/// accent in accented mode.
enum WidgetTheme {
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

/// Token colors resolved for one view's environment.
///
/// Views read this instead of the dynamic `NSColor` tokens so that Increase Contrast and the
/// rendering mode are explicit inputs: the widget host does not always hand a high-contrast
/// `NSAppearance` to the drawing code, but SwiftUI always reports `colorSchemeContrast`.
struct WidgetPalette: Equatable {
    var colorScheme: ColorScheme = .light
    var contrast: ColorSchemeContrast = .standard
    /// False in the accented and vibrant appearances, where WidgetKit tints everything one color.
    var isFullColor = true

    func color(_ token: OpenBarDynamicColor) -> Color {
        let value = token.value(isDark: self.colorScheme == .dark, increasedContrast: self.contrast == .increased)
        return Color(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
    }

    /// Unfilled part of a meter. Outside full color the track is a quarter of the tint so the fill,
    /// drawn at full strength, still separates from it.
    var meterTrack: Color {
        self.isFullColor ? self.color(OpenBarPalette.meterTrack) : Color.primary.opacity(0.25)
    }

    /// Meter fill: the provider color in full color, the tint itself otherwise.
    func meterFill(provider: Color) -> Color {
        self.isFullColor ? provider : Color.primary
    }

    /// Hairlines between columns and above cost rows.
    var separator: Color {
        Color.primary.opacity(self.contrast == .increased ? 0.35 : WidgetLayout.separatorOpacity)
    }

    /// Text and symbol color for a quota tone. Normal lanes use the primary label; stale text uses
    /// the secondary label, never the graphics-only stale gray. Outside full color the tone rides on
    /// its symbol shape and words.
    func text(_ tone: OpenBarQuotaTone) -> Color {
        switch tone {
        case .normal:
            return .primary
        case .stale:
            return .secondary
        case .warning, .critical:
            guard self.isFullColor, let token = tone.color else { return .primary }
            return self.color(token)
        }
    }
}

extension EnvironmentValues {
    var widgetPalette: WidgetPalette {
        WidgetPalette(
            colorScheme: self.colorScheme,
            contrast: self.colorSchemeContrast,
            isFullColor: self.widgetIsFullColor)
    }
}
