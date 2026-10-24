import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Color values

/// One sRGB color with alpha. Raw design-token data, shared by the app, the widget, and the CLI.
public struct OpenBarColorValue: Sendable, Equatable, Hashable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(hex: UInt32, alpha: Double = 1) {
        precondition(hex <= 0xFFFFFF, "Design colors use a six-digit RGB hex value.")
        self.red = Double((hex >> 16) & 0xFF) / 255
        self.green = Double((hex >> 8) & 0xFF) / 255
        self.blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    /// Canonical uppercase `#RRGGBB` form, without alpha.
    public var hexString: String {
        func channel(_ value: Double) -> Int {
            Int((min(1, max(0, value)) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", channel(self.red), channel(self.green), channel(self.blue))
    }
}

/// A color that resolves per appearance. Increase Contrast variants default to the regular value.
public struct OpenBarDynamicColor: Sendable, Equatable, Hashable {
    public let light: OpenBarColorValue
    public let dark: OpenBarColorValue
    public let lightHighContrast: OpenBarColorValue
    public let darkHighContrast: OpenBarColorValue

    public init(
        light: OpenBarColorValue,
        dark: OpenBarColorValue,
        lightHighContrast: OpenBarColorValue? = nil,
        darkHighContrast: OpenBarColorValue? = nil)
    {
        self.light = light
        self.dark = dark
        self.lightHighContrast = lightHighContrast ?? light
        self.darkHighContrast = darkHighContrast ?? dark
    }

    public func value(isDark: Bool, increasedContrast: Bool) -> OpenBarColorValue {
        switch (isDark, increasedContrast) {
        case (false, false): self.light
        case (true, false): self.dark
        case (false, true): self.lightHighContrast
        case (true, true): self.darkHighContrast
        }
    }
}

// MARK: - Palette

/// OpenBar's color tokens. See docs/design/README.md for usage rules and contrast checks.
///
/// Text and SF Symbols use the system label colors. These tokens add one signature accent, the
/// quota status tones, and flat surface fills. Provider brand colors stay with `ProviderBranding`.
public enum OpenBarPalette {
    /// "Iris": the signature accent for text, glyph tints, links, and focus.
    public static let accent = OpenBarDynamicColor(
        light: .init(hex: 0x5246E0),
        dark: .init(hex: 0xA39EFF),
        lightHighContrast: .init(hex: 0x3A2FC4),
        darkHighContrast: .init(hex: 0xBDB9FF))

    /// Accent for filled shapes that carry white labels (selected switcher segment, primary buttons).
    public static let accentFill = OpenBarDynamicColor(
        light: .init(hex: 0x5246E0),
        dark: .init(hex: 0x6159F0),
        lightHighContrast: .init(hex: 0x3A2FC4),
        darkHighContrast: .init(hex: 0x5B52EE))

    /// Healthy state: status dots, "lasts to reset" pace. Never used as a chart series.
    public static let ok = OpenBarDynamicColor(
        light: .init(hex: 0x07729A),
        dark: .init(hex: 0x2EC0EA),
        lightHighContrast: .init(hex: 0x05648A),
        darkHighContrast: .init(hex: 0x6FD6F5))

    /// Low quota or a pace that runs out before reset.
    public static let warning = OpenBarDynamicColor(
        light: .init(hex: 0x946200),
        dark: .init(hex: 0xFFC533),
        lightHighContrast: .init(hex: 0x7A4F00),
        darkHighContrast: .init(hex: 0xFFD56B))

    /// Exhausted or nearly exhausted quota, failed refresh, provider outage.
    public static let critical = OpenBarDynamicColor(
        light: .init(hex: 0xB4123F),
        dark: .init(hex: 0xFF6378),
        lightHighContrast: .init(hex: 0x940B33),
        darkHighContrast: .init(hex: 0xFF8A9A))

    /// Stale or unknown data. Graphics only; stale text uses the secondary label color.
    public static let stale = OpenBarDynamicColor(
        light: .init(hex: 0x8A8A8E),
        dark: .init(hex: 0x98989D),
        lightHighContrast: .init(hex: 0x6E6E73),
        darkHighContrast: .init(hex: 0xAEAEB2))

    /// Flat fill for a soft card inside menus and Settings. Works on top of system glass.
    public static let cardFill = OpenBarDynamicColor(
        light: .init(hex: 0x000000, alpha: 0.045),
        dark: .init(hex: 0xFFFFFF, alpha: 0.06),
        lightHighContrast: .init(hex: 0x000000, alpha: 0.08),
        darkHighContrast: .init(hex: 0xFFFFFF, alpha: 0.12))

    /// Hairline around a card. Only drawn when Increase Contrast is on, or on opaque surfaces.
    public static let cardStroke = OpenBarDynamicColor(
        light: .init(hex: 0x000000, alpha: 0.08),
        dark: .init(hex: 0xFFFFFF, alpha: 0.10),
        lightHighContrast: .init(hex: 0x000000, alpha: 0.35),
        darkHighContrast: .init(hex: 0xFFFFFF, alpha: 0.40))

    /// Unfilled part of a meter.
    public static let meterTrack = OpenBarDynamicColor(
        light: .init(hex: 0x000000, alpha: 0.10),
        dark: .init(hex: 0xFFFFFF, alpha: 0.14),
        lightHighContrast: .init(hex: 0x000000, alpha: 0.28),
        darkHighContrast: .init(hex: 0xFFFFFF, alpha: 0.32))

    /// Categorical chart series for non-provider entities (models, storage kinds). Fixed order,
    /// never cycled; fold a seventh series into "Other". Provider series use the provider color.
    public static let categorical: [OpenBarDynamicColor] = [
        .init(light: .init(hex: 0x5246E0), dark: .init(hex: 0x7F78F0)),
        .init(light: .init(hex: 0xEB6834), dark: .init(hex: 0xD95926)),
        .init(light: .init(hex: 0x1BAF7A), dark: .init(hex: 0x199E70)),
        .init(light: .init(hex: 0xEDA100), dark: .init(hex: 0xC98500)),
        .init(light: .init(hex: 0xE87BA4), dark: .init(hex: 0xD55181)),
        .init(light: .init(hex: 0x2A78D6), dark: .init(hex: 0x3987E5)),
    ]
}

// MARK: - Quota tone

/// The status a quota lane reports. Color is never the only cue: each tone has a symbol and a label.
public enum OpenBarQuotaTone: String, Sendable, CaseIterable {
    case normal
    case warning
    case critical
    case stale

    /// Remaining percentage at or below which a lane shows the warning tone.
    public static let warningRemainingPercent: Double = 25
    /// Remaining percentage at or below which a lane shows the critical tone.
    public static let criticalRemainingPercent: Double = 10

    /// Resolves the tone from the remaining percentage, whatever the used/remaining display setting.
    public static func resolve(remainingPercent: Double?, isStale: Bool) -> Self {
        if isStale { return .stale }
        guard let remainingPercent else { return .normal }
        if remainingPercent <= self.criticalRemainingPercent { return .critical }
        if remainingPercent <= self.warningRemainingPercent { return .warning }
        return .normal
    }

    public var color: OpenBarDynamicColor? {
        switch self {
        case .normal: nil
        case .warning: OpenBarPalette.warning
        case .critical: OpenBarPalette.critical
        case .stale: OpenBarPalette.stale
        }
    }

    /// SF Symbol that carries the tone without color. Nil for the normal tone.
    public var symbolName: String? {
        switch self {
        case .normal: nil
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        case .stale: "clock"
        }
    }
}

// MARK: - Metrics

/// 2-point spacing scale. Use these names; do not add one-off values.
public enum OpenBarSpacing {
    public static let hairline: Double = 2
    public static let tight: Double = 4
    public static let compact: Double = 6
    public static let regular: Double = 8
    public static let relaxed: Double = 10
    public static let section: Double = 12
    public static let group: Double = 16
    public static let pane: Double = 20
    public static let page: Double = 24
}

/// Corner radii. All rounded rectangles use the continuous (squircle) style.
public enum OpenBarRadius {
    /// Menu and Settings cards.
    public static let card: Double = 10
    /// Switcher rail and grouped controls.
    public static let rail: Double = 9
    /// Switcher segment, menu selection plate, small buttons.
    public static let control: Double = 7
    /// Sidebar symbol tiles and provider marks.
    public static let chip: Double = 5
    /// Chart bar data ends.
    public static let chartBar: Double = 2
}

/// Fixed menu geometry, in points.
public enum OpenBarMenuMetrics {
    /// Inset from the menu's content edge to a card.
    public static let cardInset: Double = 8
    /// Gap between two stacked cards. Replaces separator items between card sections.
    public static let cardGap: Double = 6
    /// Padding inside a card.
    public static let cardPaddingHorizontal: Double = 12
    public static let cardPaddingVertical: Double = 10
    /// Gap between quota lanes inside a card.
    public static let laneSpacing: Double = 10
    /// Lane title row to meter, and meter to detail row.
    public static let laneInnerSpacing: Double = 5
    /// Meter height. The track is a capsule; markers are 1-point gaps, never overlays.
    public static let meterHeight: Double = 6
    /// Gap between a meter's fill and its track (the "open" gap).
    public static let meterSplitGap: Double = 1.5
    /// Provider logo size in card headers and the switcher.
    public static let logoSize: Double = 16
    /// Switcher segment height.
    public static let switcherSegmentHeight: Double = 30
}

/// Menu bar glyph geometry for the template image, in points. Drawn on a 2x pixel grid.
public enum OpenBarGlyphMetrics {
    public static let canvasHeight: Double = 18
    /// Width of the "Meter bars" glyph canvas.
    public static let canvasWidth: Double = 18
    /// Rail length and thickness. The session rail is above the weekly rail.
    public static let railLength: Double = 16
    public static let primaryRailHeight: Double = 5
    public static let secondaryRailHeight: Double = 3.5
    public static let railGap: Double = 2.5
    /// Gap between fill and track. The OpenBar "open" motif.
    public static let splitGap: Double = 1
    /// Track opacity. Increase Contrast raises it to `trackAlphaHighContrast`.
    public static let trackAlpha: Double = 0.28
    public static let trackAlphaHighContrast: Double = 0.45
    /// Whole-glyph opacity for stale data.
    public static let staleAlpha: Double = 0.5
}

// MARK: - Type

/// Type scale. Sizes are macOS points; `textStyle` names the SwiftUI text style each role maps to.
public enum OpenBarTypeRole: String, Sendable, CaseIterable {
    /// Settings pane and dashboard titles.
    case title
    /// Provider name in card headers.
    case cardTitle
    /// Quota lane title ("Session", "Weekly").
    case laneTitle
    /// Quota figure ("62% left"). Monospaced digits.
    case laneValue
    /// Reset time, updated time, plan, pace. Secondary color.
    case meta
    /// Chart axes, footers, legal text.
    case caption
    /// Large figure in widgets and dashboard totals. Monospaced digits.
    case hero
    /// Paths, hex values, commands.
    case code

    public enum Weight: String, Sendable {
        case regular
        case medium
        case semibold
        case bold
    }

    public var size: Double {
        switch self {
        case .title: 17
        case .cardTitle: 13
        case .laneTitle: 12
        case .laneValue: 13
        case .meta: 11
        case .caption: 10
        case .hero: 28
        case .code: 11
        }
    }

    public var weight: Weight {
        switch self {
        case .title, .cardTitle, .laneValue, .hero: .semibold
        case .laneTitle: .medium
        case .meta, .caption, .code: .regular
        }
    }

    public var usesMonospacedDigits: Bool {
        switch self {
        case .laneValue, .hero, .meta: true
        default: false
        }
    }
}

// MARK: - AppKit bridge

#if canImport(AppKit)
extension OpenBarColorValue {
    public var nsColor: NSColor {
        NSColor(srgbRed: self.red, green: self.green, blue: self.blue, alpha: self.alpha)
    }
}

extension OpenBarDynamicColor {
    private static let appearanceNames: [NSAppearance.Name] = [
        .aqua,
        .darkAqua,
        .accessibilityHighContrastAqua,
        .accessibilityHighContrastDarkAqua,
    ]

    /// A dynamic `NSColor` that resolves at draw time for the drawing appearance.
    public var nsColor: NSColor {
        let token = self
        return NSColor(name: nil) { appearance in
            token.resolvedValue(for: appearance).nsColor
        }
    }

    public func resolvedValue(for appearance: NSAppearance) -> OpenBarColorValue {
        let match = appearance.bestMatch(from: Self.appearanceNames) ?? .aqua
        switch match {
        case .darkAqua: return self.dark
        case .accessibilityHighContrastAqua: return self.lightHighContrast
        case .accessibilityHighContrastDarkAqua: return self.darkHighContrast
        default: return self.light
        }
    }
}
#endif
