import AppKit
import OpenBarCore
import SwiftUI
import WidgetKit
@testable import OpenBarWidget

/// Every widget kind at the macOS tile sizes: healthy, warning, critical, and stale data as separate
/// states, empty and missing-metric states, long names, German and Russian, and the full-color,
/// accented, and vibrant rendering modes.
/// Owner during the redesign: the Widgets & web agent (see docs/design/README.md, work split).
///
/// Repeatable renders: the widget views read their clock through `widgetFixedNow` (set to
/// `GalleryFixtures.now`) and format dates in a fixed time zone. Production keeps WidgetKit's live
/// date text. The rendering-mode override approximates WidgetKit's accented and vibrant tinting
/// for layout review only; it is not proof of the system's own container treatment.
@MainActor
enum GalleryWidgetsSection {
    static let small = CGSize(width: 155, height: 155)
    static let medium = CGSize(width: 329, height: 155)
    static let large = CGSize(width: 329, height: 345)
    static let timeZone = TimeZone(identifier: "America/Los_Angeles")!

    static let sizes: [(String, WidgetTileSize, CGSize)] = [
        ("Small", .small, Self.small),
        ("Medium", .medium, Self.medium),
        ("Large", .large, Self.large),
    ]

    static func render(_ gallery: GalleryWriter) throws {
        // DateFormatter-based labels (burn-down axis, reset times) follow the default time zone.
        let savedTimeZone = NSTimeZone.default
        NSTimeZone.default = self.timeZone
        defer { NSTimeZone.default = savedTimeZone }
        try self.renderUsageTiles(gallery)
        try self.renderOtherKinds(gallery)
    }

    private static func renderUsageTiles(_ gallery: GalleryWriter) throws {
        let states: [(String, String, WidgetSnapshot.ProviderEntry, String)] = [
            ("", "", Fixture.claude, "Claude, healthy: the binding lane leads, weekly and today's cost beside it."),
            (
                " · warning",
                "-warning",
                Fixture.codexWarning,
                "Codex at 18% left: triangle + warning color on the value; the meter keeps the provider color."),
            (
                " · critical",
                "-critical",
                Fixture.cursorCritical,
                "Cursor at 6% left: octagon + critical color. Fresh data, so no stale marker."),
            (
                " · stale",
                "-stale",
                Fixture.cursorStale,
                "Cursor updated two days ago: clock + secondary freshness text; the value keeps its normal tone."),
            (
                " · long name",
                "-long-name",
                Fixture.longName,
                "Alibaba Token Plan: the name wraps to two lines before it truncates."),
        ]
        for (label, size, points) in self.sizes {
            for (title, suffix, entry, note) in states {
                try self.add(
                    gallery,
                    title: "Usage tile · \(label)\(title)",
                    name: "usage-\(label.lowercased())\(suffix)",
                    note: note,
                    points: points)
                {
                    self.usage(entry, size: size)
                }
            }
            for (mode, modeName) in [(WidgetRenderingMode.accented, "accented"), (.vibrant, "vibrant")] {
                try self.add(
                    gallery,
                    title: "Usage tile · \(label) · \(modeName) mode",
                    name: "usage-\(label.lowercased())-\(modeName)",
                    note: "Rendering-mode override: provider and tone colors drop out; fill 100 %, track 25 % "
                        + "of the tint, and tone symbols keep their shape.",
                    points: points,
                    mode: mode)
                {
                    self.usage(Fixture.codexWarning, size: size)
                }
            }
            for language in ["de", "ru"] {
                try self.add(
                    gallery,
                    title: "Usage tile · \(label) · \(language)",
                    name: "usage-\(label.lowercased())-\(language)",
                    note: "Long translated reset text wraps to a second line before it shrinks.",
                    points: points,
                    language: language)
                {
                    self.usage(Fixture.claude, size: size)
                }
            }
            try self.add(
                gallery,
                title: "Switcher tile · \(label)",
                name: "switcher-\(label.lowercased())",
                note: "ProviderPagerHeader spans the tile; the shared usage layout sits below it.",
                points: points)
            {
                UsageTile(entry: Fixture.claude, size: size, headerSpansColumns: true) {
                    ProviderPagerHeader(
                        providers: [.claude, .codex, .cursor, .gemini],
                        selected: .claude,
                        updatedAt: Fixture.claude.updatedAt,
                        size: size)
                }
                .environment(\.widgetProviderSelectionOverride) { _ in }
            }
        }
    }

    private static func renderOtherKinds(_ gallery: GalleryWriter) throws {
        for (label, isLarge, points) in [("Medium", false, self.medium), ("Large", true, self.large)] {
            try self.add(
                gallery,
                title: "History · \(label)",
                name: "history-\(label.lowercased())",
                note: "Daily cost bars: one batched path per series, latest day at full strength, empty days "
                    + "as track stubs.",
                points: points)
            {
                HistoryView(entry: Fixture.claude, isLarge: isLarge)
            }
        }
        try self.add(
            gallery,
            title: "Metric · Small",
            name: "metric-small",
            note: "Compact single-figure widget (today's cost).",
            points: self.small)
        {
            CompactMetricView(entry: Fixture.claude, metric: .todayCost)
        }
        try self.add(
            gallery,
            title: "Metric · Small · not reported",
            name: "metric-small-missing",
            note: "A metric the provider never reports: a muted dash and the reason.",
            points: self.small)
        {
            CompactMetricView(entry: Fixture.cursorCritical, metric: .credits)
        }
        let accounts = Fixture.accounts
        for (label, family, points) in [
            ("Medium", WidgetFamily.systemMedium, self.medium),
            ("Large", WidgetFamily.systemLarge, self.large),
        ] {
            try self.add(
                gallery,
                title: "Accounts · \(label)",
                name: "accounts-\(label.lowercased())",
                note: "Saved accounts, most constrained first, with unified tones.",
                points: points)
            {
                AccountsOverviewTile(entry: accounts, family: family)
            }
        }
        try self.add(
            gallery,
            title: "Empty · Medium",
            name: "empty-medium",
            note: "No enabled provider.",
            points: self.medium)
        {
            WidgetEmptyState(message: W("Enable a provider in OpenBar → Settings → Providers."))
        }
        let burnStates: [(String, String, WidgetSnapshot, WidgetRenderingMode?)] = [
            ("", "", Fixture.burnDown, nil),
            (" · spent", "-spent", Fixture.burnDownSpent, nil),
            (" · accented mode", "-accented", Fixture.burnDown, .accented),
        ]
        for (title, suffix, snapshot, mode) in burnStates {
            try self.add(
                gallery,
                title: "Burn down · Medium\(title)",
                name: "burndown-medium\(suffix)",
                note: "Remaining budget against the ideal steady burn. Plain Path shapes, no Canvas, no gradient.",
                points: self.medium,
                mode: mode,
                padding: 0)
            {
                BurnDownWidgetView(entry: .init(
                    date: GalleryFixtures.now,
                    provider: .claude,
                    window: .session,
                    snapshot: snapshot))
            }
        }
        try self.add(
            gallery,
            title: "Burn down (combined) · Medium",
            name: "burndown-combined-medium",
            note: "Session and weekly burn-down rows in one tile.",
            points: self.medium,
            padding: 0)
        {
            CombinedBurnDownWidgetView(entry: .init(
                date: GalleryFixtures.now,
                provider: .claude,
                snapshot: Fixture.burnDown))
        }
    }

    private static func usage(_ entry: WidgetSnapshot.ProviderEntry, size: WidgetTileSize) -> some View {
        UsageTile(entry: entry, size: size) {
            TileHeader(provider: entry.provider, updatedAt: entry.updatedAt, size: size)
        }
    }

    // MARK: Capture

    // swiftlint:disable:next function_parameter_count
    private static func add(
        _ gallery: GalleryWriter,
        title: String,
        name: String,
        note: String,
        points: CGSize,
        mode: WidgetRenderingMode? = nil,
        padding: CGFloat? = nil,
        language: String = "en",
        @ViewBuilder content: @escaping () -> some View) throws
    {
        try gallery.add(section: "widgets", title: title, name: name, note: note) { appearance in
            try WidgetLocalizationOverride.$language.withValue(language) {
                try GalleryCapture.hosted(
                    self.tile(
                        points: points,
                        appearance: appearance,
                        mode: mode,
                        padding: padding,
                        language: language,
                        content: content),
                    appearance: appearance,
                    backdrop: appearance.desktopBackdrop,
                    padding: 16)
            }
        }
    }

    // Simulates the WidgetKit host: content margins, the 22-pt tile corner, and an opaque stand-in
    // for `.containerBackground(.fill.tertiary, for: .widget)` (a tinted plate in the tinted modes).
    // swiftlint:disable:next function_parameter_count
    private static func tile(
        points: CGSize,
        appearance: GalleryAppearance,
        mode: WidgetRenderingMode?,
        padding: CGFloat?,
        language: String,
        @ViewBuilder content: () -> some View) -> some View
    {
        let margin = padding ?? (points.width < 200 ? 12 : 14)
        let plate = mode == nil
            ? (appearance.isDark ? Color(white: 0.17) : Color(white: 0.98))
            : Color(red: 0.36, green: 0.42, blue: 0.48)
        return content()
            .environment(\.widgetFixedNow, GalleryFixtures.now)
            .environment(\.widgetRenderingModeOverride, mode)
            .environment(\.timeZone, self.timeZone)
            .environment(\.locale, Locale(identifier: language))
            .padding(margin)
            .frame(width: points.width, height: points.height, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(plate))
            .environment(\.colorScheme, mode == nil ? appearance.colorScheme : .dark)
    }

    // MARK: Fixtures

    @MainActor
    private enum Fixture {
        static let now = GalleryFixtures.now

        static func entry(
            _ provider: UsageProvider,
            updatedAgo: TimeInterval = 60,
            primaryUsed: Double,
            primaryMinutes: Int = 300,
            primaryReset: TimeInterval = 2 * 3600 + 14 * 60,
            secondaryUsed: Double?,
            secondaryReset: TimeInterval = 3 * 86400 + 4 * 3600,
            credits: Double? = nil,
            token: WidgetSnapshot.TokenUsageSummary? = nil,
            daily: [WidgetSnapshot.DailyUsagePoint] = []) -> WidgetSnapshot.ProviderEntry
        {
            WidgetSnapshot.ProviderEntry(
                provider: provider,
                updatedAt: self.now.addingTimeInterval(-updatedAgo),
                primary: RateWindow(
                    usedPercent: primaryUsed,
                    windowMinutes: primaryMinutes,
                    resetsAt: self.now.addingTimeInterval(primaryReset),
                    resetDescription: nil),
                secondary: secondaryUsed.map {
                    RateWindow(
                        usedPercent: $0,
                        windowMinutes: 10080,
                        resetsAt: self.now.addingTimeInterval(secondaryReset),
                        resetDescription: nil)
                },
                tertiary: nil,
                creditsRemaining: credits,
                codeReviewRemainingPercent: nil,
                tokenUsage: token,
                dailyUsage: daily)
        }

        static let claude = entry(
            .claude,
            primaryUsed: 38,
            secondaryUsed: 59,
            token: WidgetSnapshot.TokenUsageSummary(
                sessionCostUSD: 4.12,
                sessionTokens: 1_200_000,
                last30DaysCostUSD: 88.4,
                last30DaysTokens: 31_000_000,
                updatedAt: now.addingTimeInterval(-60)),
            daily: daily(costs: [2.1, 3.4, 0, 5.2, 4.4, 6.8, 3.1, 2.7, 0, 4.9, 7.4, 5.6, 3.8, 4.12]))

        static let codexWarning = entry(
            .codex,
            updatedAgo: 120,
            primaryUsed: 82,
            primaryReset: 38 * 60,
            secondaryUsed: 48,
            secondaryReset: 5 * 86400 + 2 * 3600,
            credits: 1243.4)

        static let cursorCritical = entry(
            .cursor, primaryUsed: 94, primaryMinutes: 43200, primaryReset: 9 * 86400, secondaryUsed: nil)

        static let cursorStale = entry(
            .cursor,
            updatedAgo: 2 * 86400 + 3 * 3600,
            primaryUsed: 44,
            primaryMinutes: 43200,
            primaryReset: 9 * 86400,
            secondaryUsed: nil)

        static let longName = entry(.alibabatokenplan, primaryUsed: 12, secondaryUsed: 64)

        static let accounts: OpenBarWidgetEntry = {
            let accounts: [WidgetSnapshot.AccountEntry] = [9.0, 18, 54, 82, 97].enumerated().map { index, left in
                .init(
                    id: "fixture-\(index + 1)",
                    provider: .codex,
                    label: "Account \(index + 1)",
                    usage: entry(.codex, updatedAgo: 300, primaryUsed: 0, secondaryUsed: 100 - left))
            }
            return OpenBarWidgetEntry(date: now, provider: .codex, snapshot: WidgetSnapshot(
                entries: [],
                accounts: accounts,
                enabledProviders: [.codex],
                generatedAt: now))
        }()

        static let burnDown = WidgetSnapshot(
            entries: [entry(
                .claude,
                primaryUsed: 58,
                primaryReset: 2 * 3600 + 30 * 60,
                secondaryUsed: 31,
                secondaryReset: 4 * 86400 + 6 * 3600)],
            generatedAt: now)

        static let burnDownSpent = WidgetSnapshot(
            entries: [entry(
                .claude,
                primaryUsed: 100,
                primaryReset: 3600 + 30 * 60,
                secondaryUsed: 88,
                secondaryReset: 2 * 86400)],
            generatedAt: now)

        private static func daily(costs: [Double]) -> [WidgetSnapshot.DailyUsagePoint] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            return costs.enumerated().map { index, cost in
                let day = self.now.addingTimeInterval(-Double(costs.count - 1 - index) * 86400)
                return WidgetSnapshot.DailyUsagePoint(
                    dayKey: formatter.string(from: day),
                    totalTokens: Int(cost * 290_000),
                    costUSD: cost)
            }
        }
    }
}
