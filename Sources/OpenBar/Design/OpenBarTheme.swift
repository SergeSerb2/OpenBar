import AppKit
import OpenBarCore
import SwiftUI

/// SwiftUI and AppKit accessors for the design tokens in `OpenBarDesignTokens.swift`.
///
/// Views read colors, fonts, and metrics from here instead of literals. Token values live in
/// OpenBarCore so the widget and CLI share them; this file only adapts them to the app's frameworks.
/// See docs/design/README.md for usage rules.
enum OpenBarTheme {
    // MARK: Colors

    enum Colors {
        /// Iris, or the user's system accent when they chose one in System Settings.
        static let accent = Color(nsColor: OpenBarTheme.NSColors.accent)
        static let accentFill = Color(nsColor: OpenBarTheme.NSColors.accentFill)
        static let ok = Color(nsColor: OpenBarPalette.ok.nsColor)
        static let warning = Color(nsColor: OpenBarPalette.warning.nsColor)
        static let critical = Color(nsColor: OpenBarPalette.critical.nsColor)
        static let stale = Color(nsColor: OpenBarPalette.stale.nsColor)
        static let cardFill = Color(nsColor: OpenBarPalette.cardFill.nsColor)
        static let cardStroke = Color(nsColor: OpenBarPalette.cardStroke.nsColor)
        static let meterTrack = Color(nsColor: OpenBarPalette.meterTrack.nsColor)

        static func tone(_ tone: OpenBarQuotaTone) -> Color? {
            tone.color.map { Color(nsColor: $0.nsColor) }
        }

        /// Categorical series color for `index`, or nil past the last slot (fold into "Other").
        static func series(_ index: Int) -> Color? {
            guard OpenBarPalette.categorical.indices.contains(index) else { return nil }
            return Color(nsColor: OpenBarPalette.categorical[index].nsColor)
        }
    }

    /// Dynamic AppKit colors for layer-backed drawing (switcher, menu bar, AppKit rows).
    /// Computed so nonisolated drawing code can read them; each value resolves at draw time.
    enum NSColors {
        static var accent: NSColor {
            NSColor(name: nil) { appearance in
                OpenBarTheme.usesSystemAccent
                    ? NSColor.controlAccentColor
                    : OpenBarPalette.accent.resolvedValue(for: appearance).nsColor
            }
        }

        static var accentFill: NSColor {
            NSColor(name: nil) { appearance in
                OpenBarTheme.usesSystemAccent
                    ? NSColor.controlAccentColor
                    : OpenBarPalette.accentFill.resolvedValue(for: appearance).nsColor
            }
        }

        static var cardFill: NSColor {
            OpenBarPalette.cardFill.nsColor
        }

        static var meterTrack: NSColor {
            OpenBarPalette.meterTrack.nsColor
        }

        static func tone(_ tone: OpenBarQuotaTone) -> NSColor? {
            tone.color?.nsColor
        }
    }

    /// True when the user picked an explicit accent in System Settings → Appearance. With the
    /// default Multicolor choice there is no `AppleAccentColor` value, and the app shows Iris,
    /// matching how first-party apps treat their own accent.
    static var usesSystemAccent: Bool {
        UserDefaults.standard.object(forKey: "AppleAccentColor") != nil
    }

    // MARK: Type

    enum Fonts {
        static func font(_ role: OpenBarTypeRole) -> Font {
            let base: Font = switch role {
            case .title: .title2
            case .cardTitle: .headline
            case .laneTitle: .callout
            case .laneValue: .body
            case .meta: .subheadline
            case .caption: .caption
            case .hero: .system(size: role.size)
            case .code: .system(size: role.size, design: .monospaced)
            }
            let weighted = base.weight(Self.weight(role.weight))
            return role.usesMonospacedDigits ? weighted.monospacedDigit() : weighted
        }

        static func nsFont(_ role: OpenBarTypeRole) -> NSFont {
            let weight = Self.nsWeight(role.weight)
            if role == .code {
                return .monospacedSystemFont(ofSize: role.size, weight: weight)
            }
            return role.usesMonospacedDigits
                ? .monospacedDigitSystemFont(ofSize: role.size, weight: weight)
                : .systemFont(ofSize: role.size, weight: weight)
        }

        static let title = Self.font(.title)
        static let cardTitle = Self.font(.cardTitle)
        static let laneTitle = Self.font(.laneTitle)
        static let laneValue = Self.font(.laneValue)
        static let meta = Self.font(.meta)
        static let caption = Self.font(.caption)
        static let hero = Self.font(.hero)
        static let code = Self.font(.code)

        private static func weight(_ weight: OpenBarTypeRole.Weight) -> Font.Weight {
            switch weight {
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            }
        }

        private static func nsWeight(_ weight: OpenBarTypeRole.Weight) -> NSFont.Weight {
            switch weight {
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            }
        }
    }

    // MARK: Shapes

    static func cardShape() -> RoundedRectangle {
        RoundedRectangle(cornerRadius: OpenBarRadius.card, style: .continuous)
    }
}

extension View {
    /// Soft layered card: one flat fill, no material, no shadow. Adds the `cardStroke` hairline when the
    /// environment reports Increase Contrast, so the default card costs a single shape layer. Pass
    /// `increasedContrast` only to force a state (render-gallery fixtures).
    func openBarCard(increasedContrast: Bool? = nil) -> some View {
        self.modifier(OpenBarCardModifier(increasedContrastOverride: increasedContrast))
    }
}

private struct OpenBarCardModifier: ViewModifier {
    let increasedContrastOverride: Bool?
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let increasedContrast = self.increasedContrastOverride ?? (self.contrast == .increased)
        content
            .padding(.horizontal, OpenBarMenuMetrics.cardPaddingHorizontal)
            .padding(.vertical, OpenBarMenuMetrics.cardPaddingVertical)
            .background {
                OpenBarTheme.cardShape()
                    .fill(OpenBarTheme.Colors.cardFill)
                    .overlay {
                        if increasedContrast {
                            OpenBarTheme.cardShape()
                                .strokeBorder(OpenBarTheme.Colors.cardStroke, lineWidth: 1)
                        }
                    }
            }
    }
}
