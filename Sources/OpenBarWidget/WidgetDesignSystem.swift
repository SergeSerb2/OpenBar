import Foundation
import OpenBarCore
import SwiftUI
import WidgetKit

/// Widget catalogs are generated from the app catalogs by sync-widget-locales.mjs.
enum WidgetLocalization {
    static let resourceBundle: Bundle = {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }()

    static var currentBundle: Bundle {
        #if SWIFT_PACKAGE
        let defaultLanguage = TestProcessSafety.isRunning ? "en" : ""
        #else
        let defaultLanguage = ""
        #endif
        let language = WidgetLocalizationOverride.language ?? defaultLanguage
        return self.bundle(language: language)
    }

    static func bundle(language: String, resourceBundle: Bundle = WidgetLocalization.resourceBundle) -> Bundle {
        let language = language.isEmpty
            ? Bundle.preferredLocalizations(from: resourceBundle.localizations).first ?? "en"
            : language
        // Native SwiftPM builds lowercase language-directory names, including region and script suffixes.
        for candidate in [language, language.lowercased()] {
            if let path = resourceBundle.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path)
            {
                return bundle
            }
        }
        return resourceBundle
    }
}

enum WidgetLocalizationOverride {
    @TaskLocal static var language: String?
}

func W(_ key: String, _ arguments: CVarArg...) -> String {
    let bundle = WidgetLocalization.currentBundle
    var value = bundle.localizedString(forKey: key, value: nil, table: nil)
    if value.isEmpty || value == key,
       let path = WidgetLocalization.resourceBundle.path(forResource: "en", ofType: "lproj"),
       let english = Bundle(path: path)
    {
        value = english.localizedString(forKey: key, value: nil, table: nil)
    }
    let language = bundle.bundleURL.deletingPathExtension().lastPathComponent
    let locale = bundle.bundleURL.pathExtension == "lproj"
        ? Locale(identifier: language == "ar" ? "ar@numbers=arab" : language)
        : Locale.current
    return arguments.isEmpty ? value : String(format: value, locale: locale, arguments: arguments)
}

extension EnvironmentValues {
    /// Mirrors the app's "show used instead of remaining" preference into the tiles.
    @Entry var widgetUsageShowsUsed: Bool = false

    /// Snapshot-rendering seam. WidgetKit owns `widgetRenderingMode` and nothing outside a widget
    /// host can set it, so the tinted and clear appearances are unreachable from a preview without
    /// this. Always nil in the shipping widget.
    @Entry var widgetRenderingModeOverride: WidgetRenderingMode?

    /// Native previews keep selection local instead of writing shared widget preferences.
    @Entry var widgetProviderSelectionOverride: ((UsageProvider) -> Void)?

    /// Render-clock seam for repeatable snapshots (the design render gallery). Nil in the shipping
    /// widget, where WidgetKit's live date text and `Date()` drive countdowns and freshness.
    @Entry var widgetFixedNow: Date?

    /// False in the accented and vibrant appearances, where WidgetKit replaces every color with its
    /// own tint: provider and tone colors drop out and shapes, symbols, and text carry the state.
    var widgetIsFullColor: Bool {
        (self.widgetRenderingModeOverride ?? self.widgetRenderingMode) == .fullColor
    }
}

// MARK: - Layout metrics

/// Shared spacing and sizing for the usage and switcher tiles. Widget tiles have a fixed point
/// budget, so every value here is chosen against the macOS tile sizes (155×155, 329×155, 329×345)
/// rather than tuned by eye. See docs/design/README.md, 9.5.
enum WidgetLayout {
    static let sectionSpacing: CGFloat = 10
    static let laneSpacing: CGFloat = 8
    /// Meter thickness on every tile.
    static let barHeight: CGFloat = 7
    /// Gap between a meter's fill and its track: the OpenBar "open" motif.
    static let meterSplitGap = CGFloat(OpenBarMenuMetrics.meterSplitGap)
    static let markSizeSmall: CGFloat = 20
    static let markSizeRegular: CGFloat = 23
    static let separatorOpacity: Double = 0.12
    /// Medium tiles: the headline column is fixed and the lanes column takes the rest.
    static let heroColumnWidth: CGFloat = 140
    static let columnGap: CGFloat = 12
    /// History bars in the large usage tile (the History widget sizes its own chart).
    static let historyChartHeight: CGFloat = 44

    /// The single-metric tile has no lanes to fit around, so its figure runs larger.
    static let compactMetricNumberSize: CGFloat = 36
}

// MARK: - Provider monograms

/// Two-character provider marks.
///
/// Widget tiles are far too narrow for provider display names — the previous chips wrapped
/// mid-word on large and truncated to a single ambiguous glyph on small — so the switcher renders
/// a fixed-width monogram that can never wrap or truncate.
enum ProviderMonogram {
    /// Provider-specific by design: the widget-selectable providers get curated marks because a
    /// mechanical abbreviation collides (Codex/Copilot/Cursor/Claude all start with "C").
    private static let curated: [UsageProvider: String] = [
        .alibaba: "AL",
        .alibabatokenplan: "AT",
        .antigravity: "AG",
        .claude: "CL",
        .codex: "CX",
        .copilot: "CP",
        .cursor: "CU",
        .devin: "DV",
        .gemini: "GE",
        .kilo: "KL",
        .kimi: "KM",
        .minimax: "MX",
        .mistral: "MS",
        .opencode: "OC",
        .opencodego: "OG",
        .qwencloud: "QW",
        .zai: "ZA",
    ]

    static func text(for provider: UsageProvider) -> String {
        if let curated = self.curated[provider] { return curated }
        let name = ProviderDefaults.metadata[provider]?.shortDisplayName ?? provider.rawValue
        return self.derived(from: name)
    }

    /// Initials for a two-word name, otherwise the first two letters. Never empty.
    static func derived(from name: String) -> String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.count >= 2, let first = words[0].first, let second = words[1].first {
            return String([first, second]).uppercased()
        }
        let letters = Array(words.first ?? "")
        guard let first = letters.first else { return "?" }
        return String([first, letters.dropFirst().first ?? first]).uppercased()
    }
}

// MARK: - Contrast

enum WidgetContrast {
    /// Black-vs-white crossover for WCAG relative luminance: below this a white label wins, above
    /// it a black label wins. Solving 1.05/(L+0.05) = (L+0.05)/0.05 gives L ≈ 0.1791.
    private static let crossoverLuminance: Double = 0.1791

    /// Highest-contrast label colour for text drawn on `color`. Brand palettes span very light
    /// (Gemini lilac) to mid (Claude terracotta); picking per colour keeps every mark legible.
    static func label(on color: ProviderColor) -> Color {
        self.relativeLuminance(of: color) > self.crossoverLuminance ? .black : .white
    }

    static func relativeLuminance(of color: ProviderColor) -> Double {
        func linear(_ value: Double) -> Double {
            let clamped = min(1, max(0, value))
            return clamped <= 0.03928 ? clamped / 12.92 : pow((clamped + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }
}

// MARK: - Provider mark

struct ProviderMark: View {
    let provider: UsageProvider
    let isSelected: Bool
    var size: CGFloat = WidgetLayout.markSizeRegular

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.widgetRenderingModeOverride) private var renderingModeOverride

    var body: some View {
        let style = ProviderMarkStyle.resolve(
            renderingMode: self.renderingModeOverride ?? self.renderingMode,
            provider: self.provider,
            isSelected: self.isSelected)
        Text(ProviderMonogram.text(for: self.provider))
            .font(.system(size: self.size * 0.44, weight: .bold, design: .rounded))
            .kerning(-0.3)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(style.foreground)
            .frame(width: self.size, height: self.size)
            .background(
                RoundedRectangle(cornerRadius: OpenBarRadius.chip, style: .continuous)
                    .fill(style.background))
            .accessibilityLabel(Text(ProviderMarkLabel.text(for: self.provider, isSelected: self.isSelected)))
    }
}

struct ProviderMarkStyle {
    let foreground: Color
    let background: Color

    /// Desktop widgets in tinted and clear appearances render through a luminance mask, so a brand
    /// fill carrying a dark label collapses to an empty white square — the monogram disappears
    /// entirely. Outside full colour the mark inverts: a faint plate with a bright label, which
    /// survives the mask.
    static func resolve(
        renderingMode: WidgetRenderingMode,
        provider: UsageProvider,
        isSelected: Bool) -> ProviderMarkStyle
    {
        guard renderingMode == .fullColor else {
            return ProviderMarkStyle(
                foreground: isSelected ? .primary : .primary.opacity(0.7),
                background: .primary.opacity(isSelected ? 0.22 : 0.1))
        }
        guard isSelected else {
            return ProviderMarkStyle(
                foreground: .primary.opacity(0.62),
                background: .primary.opacity(0.08))
        }
        let brand = ProviderBrandColor.resolve(for: provider.instanceID)
        return ProviderMarkStyle(
            foreground: brand.map(WidgetContrast.label(on:)) ?? .white,
            background: WidgetColors.color(for: provider.instanceID))
    }
}

enum ProviderTitle {
    static func text(for provider: UsageProvider, size _: WidgetTileSize) -> String {
        ProviderDefaults.metadata[provider]?.displayName ?? provider.rawValue.capitalized
    }
}

enum ProviderMarkLabel {
    static func text(for provider: UsageProvider, isSelected: Bool) -> String {
        let name = ProviderDefaults.metadata[provider]?.displayName ?? provider.rawValue.capitalized
        return isSelected ? W("%@, selected", name) : name
    }
}

enum ProviderBrandColor {
    /// The raw brand colour behind `WidgetColors.color(for:)`, needed for contrast maths.
    static func resolve(for instanceID: ProviderInstanceID) -> ProviderColor? {
        guard let provider = instanceID.firstPartyProvider else { return nil }
        return ProviderAccentColors.sharedOverride(for: instanceID)
            ?? ProviderDescriptorRegistry.descriptor(for: provider).branding.widgetColor
    }
}

// MARK: - Meter

/// The split meter: a fill capsule from the leading edge, a 1.5-pt gap, then a track capsule
/// (docs/design/README.md, 9.5). The gap is geometry, never a mask or an overlay.
struct QuotaBar: View {
    let percent: Double?
    let color: Color
    var height: CGFloat = WidgetLayout.barHeight

    @Environment(\.widgetPalette) private var palette

    var body: some View {
        let fraction = QuotaBar.fillFraction(self.percent)
        ZStack {
            MeterSegmentShape(fraction: fraction, segment: .track)
                .fill(self.palette.meterTrack)
            MeterSegmentShape(fraction: fraction, segment: .fill)
                .fill(self.palette.meterFill(provider: self.color))
        }
        .frame(height: self.height)
        .flipsForRightToLeftLayoutDirection(true)
        .accessibilityHidden(true)
    }

    static func fillFraction(_ percent: Double?) -> Double {
        guard let percent else { return 0 }
        return min(1, max(0, percent / 100))
    }
}

/// Horizontal extents of a split meter's fill and track, in points from the leading edge.
struct MeterGeometry: Equatable {
    let fill: ClosedRange<CGFloat>?
    let track: ClosedRange<CGFloat>?

    init(fraction: Double, width: CGFloat, height: CGFloat, gap: CGFloat = WidgetLayout.meterSplitGap) {
        let clamped = min(1, max(0, fraction))
        // Floor the fill at the bar's own height so a nearly exhausted lane reads as a visible nub
        // instead of a sliver indistinguishable from an empty track.
        let fillWidth = clamped > 0 ? min(width, max(height, CGFloat(clamped) * width)) : 0
        self.fill = fillWidth > 0 ? 0...fillWidth : nil
        let trackStart = fillWidth > 0 ? fillWidth + gap : 0
        self.track = width - trackStart >= 1 ? trackStart...width : nil
    }
}

struct MeterSegmentShape: Shape {
    enum Segment {
        case fill
        case track
    }

    let fraction: Double
    let segment: Segment

    func path(in rect: CGRect) -> Path {
        let geometry = MeterGeometry(fraction: self.fraction, width: rect.width, height: rect.height)
        guard let span = self.segment == .fill ? geometry.fill : geometry.track else { return Path() }
        let capsule = CGRect(
            x: rect.minX + span.lowerBound,
            y: rect.minY,
            width: span.upperBound - span.lowerBound,
            height: rect.height)
        return Path(roundedRect: capsule, cornerRadius: rect.height / 2, style: .circular)
    }
}

// MARK: - Quota lanes

enum QuotaSeverity {
    /// The lane's tone from what is left, whatever the used/remaining display setting: warning at
    /// 25 % or less, critical at 10 % or less (`OpenBarQuotaTone`, shared with the menu).
    static func tone(remaining: Double?) -> OpenBarQuotaTone {
        OpenBarQuotaTone.resolve(remainingPercent: remaining, isStale: false)
    }
}

/// Warning or critical symbol drawn before a value. A tone is never color alone.
struct ToneSymbol: View {
    let tone: OpenBarQuotaTone
    var size: CGFloat = 10

    @Environment(\.widgetPalette) private var palette

    var body: some View {
        if self.tone == .warning || self.tone == .critical, let name = self.tone.symbolName {
            Image(systemName: name)
                .font(.system(size: self.size, weight: .semibold))
                .foregroundStyle(self.palette.text(self.tone))
                .accessibilityHidden(true)
        }
    }
}

/// One quota lane: title and value, the split meter, and when it frees up.
struct QuotaLaneView: View {
    enum Style {
        /// Title, value, meter, and reset line.
        case regular
        /// Figure-only row for the small tile.
        case compact
    }

    let title: String
    let percent: Double?
    let remainingPercent: Double?
    let color: Color
    var showsBar: Bool = true
    var reset: Text?
    var style: Style = .regular

    @Environment(\.widgetPalette) private var palette

    var body: some View {
        let tone = QuotaSeverity.tone(remaining: self.remainingPercent)
        let regular = self.style == .regular
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(W(self.title))
                    .font(regular ? WidgetTheme.Fonts.laneTitle : WidgetTheme.Fonts.meta)
                    .foregroundStyle(regular ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                HStack(spacing: 3) {
                    ToneSymbol(tone: tone, size: regular ? 10 : 9)
                    Text(WidgetFormat.percent(self.percent))
                        .font(regular ? WidgetTheme.Fonts.laneValue : WidgetTheme.Fonts.meta.weight(.semibold))
                        .foregroundStyle(self.palette.text(tone))
                        .lineLimit(1)
                }
                .fixedSize()
            }
            if self.showsBar {
                QuotaBar(percent: self.percent, color: self.color)
                    .padding(.top, 5)
            }
            if let reset = self.reset {
                reset
                    .font(WidgetTheme.Fonts.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - Headline

/// The tile's headline: one large figure, what it measures, its meter, and when it frees up.
///
/// Tiles lead with the *binding* quota — the lane with the least left — because that is the number
/// that decides whether the user can keep working.
struct HeroBlock: View {
    enum Arrangement {
        /// Figure, caption, meter, reset, top to bottom (small and medium tiles).
        case stacked
        /// Figure with caption and reset beside it, meter below (large tiles).
        case row
    }

    let value: String
    var caption: Text?
    var detail: Text?
    /// Percentage for the meter. `nil` draws no meter.
    var barPercent: Double?
    var tone: OpenBarQuotaTone = .normal
    var color: Color = .secondary
    var numberSize: CGFloat = 34
    /// Pushes the meter and reset line to the bottom of the available height.
    var spreads: Bool = false
    var arrangement: Arrangement = .stacked
    /// Tighter vertical rhythm for the small tile, which has 131 pt for everything.
    var compact: Bool = false

    @Environment(\.widgetPalette) private var palette

    var isUnavailable: Bool {
        self.value == WidgetFormat.unavailable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch self.arrangement {
            case .stacked:
                self.figure
                self.captionText
                    .padding(.top, self.compact ? 0 : 1)
                if self.spreads {
                    Spacer(minLength: self.compact ? 3 : 6)
                }
                self.meter(topPadding: self.spreads ? 0 : 8)
                self.detailText
                    .padding(.top, self.compact ? 3 : 5)
            case .row:
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    self.figure
                    VStack(alignment: .leading, spacing: 1) {
                        self.captionText
                        self.detailText
                    }
                    Spacer(minLength: 0)
                }
                self.meter(topPadding: 8)
            }
        }
    }

    /// A missing figure is drawn small and muted: at headline size the em-dash placeholder reads as
    /// a heavy black bar, which looks like a broken tile rather than "no data".
    private var figure: some View {
        HStack(alignment: .center, spacing: max(3, self.numberSize * 0.1)) {
            if !self.isUnavailable {
                ToneSymbol(tone: self.tone, size: max(10, self.numberSize * 0.4))
            }
            Text(self.value)
                .font(WidgetTheme.Fonts.hero(size: self.isUnavailable ? self.numberSize * 0.5 : self.numberSize))
                .foregroundStyle(self.isUnavailable ? Color.secondary : self.palette.text(self.tone))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    @ViewBuilder
    private var captionText: some View {
        if let caption = self.caption {
            caption
                .font(WidgetTheme.Fonts.meta)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// Reset text wraps to a second line before it shrinks, so long translations stay readable.
    @ViewBuilder
    private var detailText: some View {
        if let detail = self.detail {
            detail
                .font(WidgetTheme.Fonts.meta)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
    }

    @ViewBuilder
    private func meter(topPadding: CGFloat) -> some View {
        if let barPercent = self.barPercent {
            QuotaBar(percent: barPercent, color: self.color)
                .padding(.top, topPadding)
        }
    }
}

// MARK: - Value rows

/// A right-aligned figure with a muted label, used for cost and credit rows.
struct MetricLine: View {
    let title: Text
    let value: String
    var isProminent: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            self.title
                .font(WidgetTheme.Fonts.meta)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Text(self.value)
                .font(self.isProminent ? WidgetTheme.Fonts.meta.weight(.medium) : WidgetTheme.Fonts.meta)
                .foregroundStyle(self.isProminent ? Color.primary : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
                .layoutPriority(1)
        }
    }
}

/// A 1-pt hairline: above cost rows, and between the medium tile's columns.
struct WidgetSeparator: View {
    var axis: Axis = .horizontal

    @Environment(\.widgetPalette) private var palette

    var body: some View {
        Rectangle()
            .fill(self.palette.separator)
            .frame(width: self.axis == .vertical ? 1 : nil, height: self.axis == .horizontal ? 1 : nil)
    }
}

// MARK: - Header

/// Mark, provider name, and freshness. The name wraps to a second line before it truncates, so
/// long provider names stay readable. Small tiles give the freshness its own line: the system's
/// relative date text ("2 minutes") does not fit beside a name in 131 pt.
struct TileHeader: View {
    let provider: ProviderInstanceID
    let updatedAt: Date
    var size: WidgetTileSize = .medium

    var body: some View {
        if self.size == .small {
            VStack(alignment: .leading, spacing: 1) {
                self.nameRow
                FreshnessLabel(updatedAt: self.updatedAt, font: WidgetTheme.Fonts.caption)
                    .padding(.leading, self.size.markSize + 6)
            }
        } else {
            HStack(spacing: 6) {
                self.nameRow
                    .layoutPriority(1)
                Spacer(minLength: 4)
                FreshnessLabel(updatedAt: self.updatedAt)
            }
        }
    }

    private var nameRow: some View {
        HStack(spacing: 6) {
            if let provider = self.provider.firstPartyProvider {
                ProviderMark(provider: provider, isSelected: true, size: self.size.markSize)
            }
            Text(self.displayName)
                .font(WidgetTheme.Fonts.cardTitle)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)
        }
        .frame(minHeight: self.size.markSize)
    }

    private var displayName: String {
        guard let provider = self.provider.firstPartyProvider else {
            return self.provider.rawValue.capitalized
        }
        return ProviderTitle.text(for: provider, size: self.size)
    }
}

/// Snapshot age. Past a day it gains a clock symbol so a silently stale tile cannot be mistaken
/// for live data; the text stays the secondary label color.
struct FreshnessLabel: View {
    let updatedAt: Date
    var font: Font = WidgetTheme.Fonts.meta

    @Environment(\.widgetFixedNow) private var fixedNow

    var body: some View {
        // WidgetKit advances native date text between reloads; a formatted TimelineView string can freeze.
        // fixedSize on live date text can erase the rest of the tile.
        HStack(spacing: 3) {
            if WidgetFreshness.isStale(self.updatedAt, now: self.fixedNow ?? Date()) {
                Image(systemName: "clock")
                    .font(.system(size: 9, weight: .medium))
                    .accessibilityHidden(true)
            }
            WidgetDateText.offset(self.updatedAt, now: self.fixedNow)
        }
        .font(self.font)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

enum WidgetDateText {
    /// Age of `date`. Live system date text in the widget; static text against `now` when a render
    /// clock is injected (gallery and previews only).
    static func offset(_ date: Date, now: Date? = nil) -> Text {
        if #available(macOS 15, *) {
            if let now {
                return Text(now, format: self.ageFormat(date))
            }
            return Text(.currentDate, format: self.ageFormat(date))
        }
        if let now {
            return Text(self.legacyDuration(abs(now.timeIntervalSince(date))))
        }
        return Text(date, style: .relative)
    }

    @available(macOS 15, *)
    static func ageFormat(_ date: Date) -> SystemFormatStyle.DateOffset {
        .init(to: date, allowedFields: [.day, .hour, .minute], maxFieldCount: 2, sign: .never)
    }

    static func reset(_ date: Date, now: Date? = nil) -> Text {
        if #available(macOS 15, *) {
            // System date references update visually in the out-of-process WidgetKit host.
            let reference = now.map { Text($0, format: self.resetFormat(date)) }
                ?? Text(.currentDate, format: self.resetFormat(date))
            return Text("Resets \(reference)", bundle: WidgetLocalization.currentBundle)
        }
        if let now {
            return Text(W("Resets in %@", self.legacyDuration(date.timeIntervalSince(now))))
        }
        return Text("Resets in \(Text(date, style: .relative))", bundle: WidgetLocalization.currentBundle)
    }

    @available(macOS 15, *)
    static func resetFormat(_ date: Date) -> SystemFormatStyle.DateReference {
        .init(to: date, allowedFields: [.day, .hour, .minute], maxFieldCount: 2, thresholdField: .minute)
    }

    private static func legacyDuration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: max(60, interval)) ?? ""
    }
}

enum WidgetFreshness {
    static let staleThreshold: TimeInterval = 24 * 60 * 60

    static func isStale(_ updatedAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(updatedAt) > self.staleThreshold
    }
}

// MARK: - Empty state

struct WidgetEmptyState: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(W("Open OpenBar"))
                .font(WidgetTheme.Fonts.cardTitle)
            Text(self.message)
                .font(WidgetTheme.Fonts.meta)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
