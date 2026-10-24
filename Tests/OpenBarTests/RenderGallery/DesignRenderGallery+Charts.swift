import AppKit
import OpenBarCore
import SwiftUI
@testable import OpenBar

/// Submenu, dashboard, and window charts with synthetic data: bars, stacks, lines, heatmap, status rows.
/// Owner during the redesign: the Glyph & Charts agent (see docs/design/README.md, work split).
@MainActor
enum GalleryChartsSection {
    static let menuWidth: CGFloat = 310
    static let dashboardWidth: CGFloat = 640
    /// The heatmap's scroll grid measures through a GeometryReader, so its capture gets an explicit height.
    static let heatmapHeight: CGFloat = 262

    static func render(_ gallery: GalleryWriter) throws {
        // Fixed clock and time zone so day buckets and axis dates repeat exactly (gallery only).
        let savedTimeZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "America/Vancouver") ?? savedTimeZone
        defer {
            NSTimeZone.default = savedTimeZone
            ChartFixtures.removeActivityModeSuite()
        }
        try self.renderCostHistory(gallery)
        try self.renderDailyBarChart(gallery)
        try self.renderCreditsAndBreakdown(gallery)
        try self.renderPlanUtilization(gallery)
        try self.renderStorageAndStatus(gallery)
        try self.renderDashboards(gallery)
        try self.renderLiveUsage(gallery)
    }

    // MARK: Submenu charts

    private static func renderCostHistory(_ gallery: GalleryWriter) throws {
        let daily = ChartFixtures.costDaily(days: 30)
        let total = daily.compactMap(\.costUSD).reduce(0, +)
        try self.submenu(
            gallery,
            title: "Cost history · Claude",
            name: "cost-history",
            note: "CostHistoryChartMenuView, 30 days, cost metric, last day selected by default.",
            CostHistoryChartMenuView(
                provider: .claude,
                daily: daily,
                totalCostUSD: total,
                hidePersonalInfo: false,
                width: self.menuWidth))

        let hovered = CostHistoryChartNavigation()
        hovered.selectedDateKey = ChartFixtures.dayKey(daysAgo: 9)
        try self.submenu(
            gallery,
            title: "Cost history · hovered day",
            name: "cost-history-hover",
            note: "A hovered bar keeps full opacity; the detail rows list that day's models.",
            CostHistoryChartMenuView(
                provider: .claude,
                daily: daily,
                totalCostUSD: total,
                hidePersonalInfo: false,
                width: self.menuWidth,
                navigation: hovered))

        let partial = ChartFixtures.costDaily(days: 30, keep: { $0 % 4 == 0 || $0 < 3 }, incompleteDay: 6)
        try self.submenu(
            gallery,
            title: "Cost history · partial data and incomplete requests",
            name: "cost-history-partial",
            note: "Scattered days; one day carries incomplete requests (diamond marker).",
            CostHistoryChartMenuView(
                provider: .codex,
                daily: partial,
                totalCostUSD: partial.compactMap(\.costUSD).reduce(0, +),
                hidePersonalInfo: false,
                width: self.menuWidth))

        try OpenBarLocalizationOverride.$appLanguage.withValue("de") {
            try self.submenu(
                gallery,
                title: "Cost history · German",
                name: "cost-history-de",
                note: "Long localized labels in the detail rows and footer.",
                CostHistoryChartMenuView(
                    provider: .claude,
                    daily: daily,
                    totalCostUSD: total,
                    hidePersonalInfo: false,
                    width: self.menuWidth)
                    .environment(\.locale, Locale(identifier: "de_DE")))
        }

        try self.submenu(
            gallery,
            title: "Cost history · empty",
            name: "cost-history-empty",
            CostHistoryChartMenuView(
                provider: .claude,
                daily: [],
                totalCostUSD: nil,
                hidePersonalInfo: false,
                width: self.menuWidth))
    }

    private static func renderDailyBarChart(_ gallery: GalleryWriter) throws {
        let color = ChartFixtures.providerColor(.claude)
        let days = (0..<30).map { offset -> DailyBarChart.Day in
            let value = ChartFixtures.wave(offset, base: 9)
            return DailyBarChart.Day(
                date: ChartFixtures.day(daysAgo: 29 - offset),
                segments: [.init(value: value, color: color)],
                accessibilityValue: "")
        }
        let axisDates = [days[0].date, days[29].date]
        let peakValue = days.map { $0.segments[0].value }.max() ?? 0
        let yAxis = DailyBarChart.YAxis(values: [0, peakValue / 2, peakValue]) { "$\(Int($0.rounded()))" }
        try self.chartOnly(
            gallery,
            title: "DailyBarChart · selected bar",
            name: "daily-bar-selected",
            note: "selectedIndex = 21: the selected bar keeps full opacity, the others drop to 55 %.",
            DailyBarChart(
                days: days,
                axisDates: axisDates,
                peak: days.map { (date: $0.date, value: $0.segments[0].value) }.max { $0.value < $1.value },
                selectedIndex: 21,
                yAxis: yAxis,
                onHover: { _ in }))

        let stacked = (0..<30).map { offset -> DailyBarChart.Day in
            DailyBarChart.Day(
                date: ChartFixtures.day(daysAgo: 29 - offset),
                segments: (0..<3).map { series in
                    .init(
                        value: ChartFixtures.wave(offset + series * 7, base: Double(4 - series) * 1.6),
                        color: OpenBarTheme.Colors.series(series) ?? .gray)
                },
                accessibilityValue: "")
        }
        try self.chartOnly(
            gallery,
            title: "DailyBarChart · stacked, three series",
            name: "daily-bar-stacked",
            note: "Chart palette slots 1–3, 2-pt gaps between stacked segments.",
            DailyBarChart(days: stacked, axisDates: axisDates, plotPadding: 32, onHover: { _ in }))

        let partial = days.enumerated().map { index, day -> DailyBarChart.Day in
            var day = day
            if index % 5 == 2 { day.segments = [] }
            if index == 12 { day.incompleteMarkerValue = day.segments.first?.value ?? 0 }
            return day
        }
        try self.chartOnly(
            gallery,
            title: "DailyBarChart · missing days and an incomplete marker",
            name: "daily-bar-partial",
            note: "Days without a value draw track-colored stubs; the diamond marks incomplete requests.",
            DailyBarChart(days: partial, axisDates: axisDates, yAxis: yAxis, onHover: { _ in }))

        try self.chartOnly(
            gallery,
            title: "DailyBarChart · no days",
            name: "daily-bar-empty",
            DailyBarChart(days: [], axisDates: [], onHover: { _ in }))
    }

    private static func renderCreditsAndBreakdown(_ gallery: GalleryWriter) throws {
        try self.submenu(
            gallery,
            title: "Credits history · Codex",
            name: "credits-history",
            note: "CreditsHistoryChartMenuView. Uses Codex's provider color instead of a hardcoded teal.",
            CreditsHistoryChartMenuView(breakdown: ChartFixtures.creditsBreakdown(services: 2), width: self.menuWidth))
        try self.submenu(
            gallery,
            title: "Credits history · empty",
            name: "credits-history-empty",
            CreditsHistoryChartMenuView(breakdown: [], width: self.menuWidth))
        try self.submenu(
            gallery,
            title: "Usage breakdown · five services",
            name: "usage-breakdown",
            note: "UsageBreakdownChartMenuView: stacked services in chart palette order, legend below.",
            UsageBreakdownChartMenuView(
                breakdown: ChartFixtures.creditsBreakdown(services: 5),
                now: GalleryFixtures.now,
                width: self.menuWidth))
        try self.submenu(
            gallery,
            title: "Usage breakdown · empty",
            name: "usage-breakdown-empty",
            UsageBreakdownChartMenuView(breakdown: [], now: GalleryFixtures.now, width: self.menuWidth))
    }

    private static func renderPlanUtilization(_ gallery: GalleryWriter) throws {
        try self.submenu(
            gallery,
            title: "Plan utilization · Claude",
            name: "plan-utilization",
            note: "PlanUtilizationHistoryChartMenuView: session and weekly series; missing windows stay as tracks.",
            PlanUtilizationHistoryChartMenuView(
                provider: .claude,
                histories: [ChartFixtures.sessionHistory(), ChartFixtures.weeklyHistory()],
                width: self.menuWidth,
                referenceDate: GalleryFixtures.now))
        try self.submenu(
            gallery,
            title: "Plan utilization · empty",
            name: "plan-utilization-empty",
            PlanUtilizationHistoryChartMenuView(
                provider: .claude,
                histories: [],
                width: self.menuWidth,
                referenceDate: GalleryFixtures.now))
        try self.submenu(
            gallery,
            title: "Quota burndown · Claude weekly",
            name: "quota-burndown",
            note: "QuotaBurndownChartMenuView: observed remaining (provider color) against the dashed ideal.",
            QuotaBurndownChartMenuView(
                provider: .claude,
                histories: [ChartFixtures.burndownHistory()],
                width: self.menuWidth,
                referenceDate: GalleryFixtures.now))
        try self.submenu(
            gallery,
            title: "Quota burndown · critical",
            name: "quota-burndown-critical",
            note: "7 % left with three days to go: the line drops below the ideal.",
            QuotaBurndownChartMenuView(
                provider: .claude,
                histories: [ChartFixtures.burndownHistory(finalUsed: 93)],
                width: self.menuWidth,
                referenceDate: GalleryFixtures.now))
        try self.submenu(
            gallery,
            title: "Quota burndown · stale",
            name: "quota-burndown-stale",
            note: "Last sample six hours before the clock: the last-known notice explains the age.",
            QuotaBurndownChartMenuView(
                provider: .claude,
                histories: [ChartFixtures.burndownHistory(lastSampleAge: 6 * 3600)],
                width: self.menuWidth,
                referenceDate: GalleryFixtures.now))
        try self.submenu(
            gallery,
            title: "Quota burndown · empty",
            name: "quota-burndown-empty",
            QuotaBurndownChartMenuView(
                provider: .claude,
                histories: [],
                width: self.menuWidth,
                referenceDate: GalleryFixtures.now))
    }

    private static func renderStorageAndStatus(_ gallery: GalleryWriter) throws {
        try self.submenu(
            gallery,
            title: "Storage breakdown · ten items",
            name: "storage-breakdown",
            note: "StorageBreakdownMenuView: segmented strip in chart palette order, tail folded into Other.",
            StorageBreakdownMenuView(footprint: ChartFixtures.storage(count: 10), width: self.menuWidth))
        try self.submenu(
            gallery,
            title: "Storage breakdown · four items",
            name: "storage-breakdown-small",
            StorageBreakdownMenuView(footprint: ChartFixtures.storage(count: 4), width: self.menuWidth))
        try self.submenu(
            gallery,
            title: "Status components",
            name: "status-components",
            note: "StatusComponentsMenuView: operational, degraded, partial and major outage, maintenance, "
                + "unknown, and a collapsed group.",
            StatusComponentsMenuView(components: ChartFixtures.statusComponents, width: self.menuWidth))
        try OpenBarLocalizationOverride.$appLanguage.withValue("de") {
            try self.submenu(
                gallery,
                title: "Status components · German",
                name: "status-components-de",
                StatusComponentsMenuView(components: ChartFixtures.statusComponents, width: self.menuWidth)
                    .environment(\.locale, Locale(identifier: "de_DE")))
        }
    }

    // MARK: Dashboard and window charts

    private static func renderDashboards(_ gallery: GalleryWriter) throws {
        if let group = ChartFixtures.spendGroup() {
            try self.dashboard(
                gallery,
                title: "Spend trend panel",
                name: "spend-trend",
                note: "SpendDashboardTrendPanel: three providers stacked by day, in provider colors.",
                SpendDashboardTrendPanel(group: group, selection: .constant(.daily)))
        }
        if let empty = ChartFixtures.spendGroup(priced: false) {
            try self.dashboard(
                gallery,
                title: "Spend trend panel · no priced spend",
                name: "spend-trend-empty",
                note: "Every source reports tokens without cost: a single meta line in the chart frame.",
                SpendDashboardTrendPanel(group: empty, selection: .constant(.daily)))
        }
        let points = ChartFixtures.activityPoints()
        try self.dashboard(
            gallery,
            title: "Activity heatmap · daily",
            name: "activity-heatmap",
            note: "SpendActivityHeatmapView: single-hue Iris ramp, 5 steps; missing days keep the slashed outline.",
            ChartFixtures.withActivityMode(
                .daily,
                SpendActivityHeatmapView(points: points, now: GalleryFixtures.now, calendar: .current)
                    .frame(height: Self.heatmapHeight, alignment: .top)))
        try self.dashboard(
            gallery,
            title: "Activity heatmap · no activity",
            name: "activity-heatmap-empty",
            ChartFixtures.withActivityMode(
                .daily,
                SpendActivityHeatmapView(
                    points: points.map { .init(day: $0.day, totalTokens: 0) },
                    now: GalleryFixtures.now,
                    calendar: .current)
                    .frame(height: 120, alignment: .top)))
        try self.dashboard(
            gallery,
            title: "Activity heatmap · weekly",
            name: "activity-heatmap-weekly",
            ChartFixtures.withActivityMode(
                .weekly,
                SpendActivityHeatmapView(points: points, now: GalleryFixtures.now, calendar: .current)
                    .frame(height: Self.heatmapHeight, alignment: .top)))
        try gallery.add(
            section: "charts",
            title: "Activity heatmap · ramps",
            name: "activity-ramps",
            note: "SpendActivityPalette levels 0–4 and the unavailable swatch, standard and increased contrast. "
                + "Increase Contrast cannot be adopted offscreen, so the palette is asked directly.")
        { appearance in
            try GalleryCapture.hosted(
                ActivityRamps(colorScheme: appearance.colorScheme),
                appearance: appearance,
                backdrop: .windowBackgroundColor,
                padding: 16)
        }
    }

    private static func renderLiveUsage(_ gallery: GalleryWriter) throws {
        let snapshot = ChartFixtures.liveUsage()
        try self.dashboard(
            gallery,
            title: "OpenAI live usage · all models",
            name: "live-usage",
            note: "OpenAILiveUsageChart: tokens per minute stacked by model, org TPM limit rule, pending tail.",
            OpenAILiveUsageChart(snapshot: snapshot, filter: .allModels, tpmLimit: 90000)
                .frame(width: 560, height: 220))
        try self.dashboard(
            gallery,
            title: "OpenAI live usage · limit off scale",
            name: "live-usage-off-scale",
            note: "The org limit is far above the traffic: an opaque caption replaces the rule.",
            OpenAILiveUsageChart(snapshot: snapshot, filter: .allModels, tpmLimit: 2_000_000)
                .frame(width: 560, height: 220))
        try self.dashboard(
            gallery,
            title: "OpenAI live usage · one model",
            name: "live-usage-model",
            note: "Token kinds for one model: uncached input, output, cached input.",
            OpenAILiveUsageChart(snapshot: snapshot, filter: .model(ChartFixtures.liveModels[0]))
                .frame(width: 560, height: 220))
    }

    // MARK: Capture helpers

    private static func submenu(
        _ gallery: GalleryWriter,
        title: String,
        name: String,
        note: String? = nil,
        _ view: some View) throws
    {
        try gallery.add(section: "charts", title: title, name: name, note: note) { appearance in
            try GalleryCapture.hosted(
                view.openBarLocalized()
                    .frame(width: self.menuWidth)
                    .fixedSize(horizontal: false, vertical: true),
                appearance: appearance,
                backdrop: appearance.menuBackdrop)
        }
    }

    private static func chartOnly(
        _ gallery: GalleryWriter,
        title: String,
        name: String,
        note: String? = nil,
        _ chart: DailyBarChart) throws
    {
        try gallery.add(section: "charts", title: title, name: name, note: note) { appearance in
            try GalleryCapture.hosted(
                chart.frame(width: self.menuWidth - 32, height: 130),
                appearance: appearance,
                backdrop: appearance.menuBackdrop,
                padding: 16)
        }
    }

    private static func dashboard(
        _ gallery: GalleryWriter,
        title: String,
        name: String,
        note: String? = nil,
        _ view: some View) throws
    {
        try gallery.add(section: "charts", title: title, name: name, note: note) { appearance in
            try GalleryCapture.hosted(
                view.openBarLocalized()
                    .frame(width: self.dashboardWidth)
                    .fixedSize(horizontal: false, vertical: true),
                appearance: appearance,
                backdrop: .windowBackgroundColor,
                padding: 16,
                settle: 0.3)
        }
    }
}

/// Swatches for every heatmap level in both contrast variants.
private struct ActivityRamps: View {
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach([ColorSchemeContrast.standard, .increased], id: \.self) { contrast in
                let palette = SpendActivityPalette(colorScheme: self.colorScheme, contrast: contrast)
                HStack(spacing: 6) {
                    Text(contrast == .standard ? "Standard" : "Increased")
                        .font(OpenBarTheme.Fonts.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    ForEach(0...4, id: \.self) { level in
                        palette.cells(
                            [SpendActivityCell(rect: CGRect(x: 0, y: 0, width: 18, height: 18), level: level)],
                            corner: 2.5)
                            .frame(width: 18, height: 18)
                    }
                    palette.cells(
                        [SpendActivityCell(rect: CGRect(x: 0, y: 0, width: 18, height: 18), level: nil)],
                        corner: 2.5)
                        .frame(width: 18, height: 18)
                        .padding(.leading, 8)
                }
            }
        }
        .fixedSize()
    }
}

// MARK: - Fixtures

/// Fixed, fictitious chart data. Model names are invented on purpose.
@MainActor
private enum ChartFixtures {
    /// Read after the section pins the time zone, so day keys match the views' own calendars.
    static var calendar: Calendar {
        Calendar.current
    }

    static var today: Date {
        self.calendar.startOfDay(for: GalleryFixtures.now)
    }

    static let models = ["orbit-large", "orbit-mini", "quill-2"]
    static let liveModels = ["orbit-large", "orbit-mini", "quill-2", "lumen-fast"]

    static func day(daysAgo: Int) -> Date {
        self.calendar.date(byAdding: .day, value: -daysAgo, to: self.today) ?? self.today
    }

    static func dayKey(daysAgo: Int) -> String {
        let components = self.calendar.dateComponents([.year, .month, .day], from: self.day(daysAgo: daysAgo))
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// Deterministic, gently varying values around `base` (no randomness, so renders diff cleanly).
    static func wave(_ index: Int, base: Double) -> Double {
        let phase = Double(index)
        let value = 0.55 + 0.3 * sin(phase * 0.7) + 0.25 * sin(phase * 1.9 + 1.3)
        return (base * max(0.12, value) * 100).rounded() / 100
    }

    static func providerColor(_ provider: UsageProvider) -> Color {
        let color = ProviderAccentPalette.color(for: provider)
        return Color(red: color.red, green: color.green, blue: color.blue)
    }

    static func costDaily(
        days: Int,
        keep: (Int) -> Bool = { _ in true },
        incompleteDay: Int? = nil) -> [CostUsageDailyReport.Entry]
    {
        (0..<days).reversed().filter(keep).map { daysAgo in
            let cost = self.wave(daysAgo, base: 12)
            let breakdowns = self.models.enumerated().map { index, model in
                CostUsageDailyReport.ModelBreakdown(
                    modelName: model,
                    costUSD: (cost * [0.62, 0.28, 0.10][index] * 100).rounded() / 100,
                    totalTokens: Int(cost * [52000, 41000, 30000][index]),
                    incompleteRequestCount: daysAgo == incompleteDay && index == 0 ? 3 : nil)
            }
            return CostUsageDailyReport.Entry(
                date: self.dayKey(daysAgo: daysAgo),
                inputTokens: Int(cost * 90000),
                outputTokens: Int(cost * 20000),
                totalTokens: Int(cost * 110_000),
                requestCount: Int(cost * 14),
                costUSD: cost,
                modelsUsed: self.models,
                modelBreakdowns: breakdowns)
        }
    }

    static func creditsBreakdown(services: Int) -> [OpenAIDashboardDailyBreakdown] {
        let names = ["CLI", "GitHub Code Review", "Cloud tasks", "IDE extension", "Slack"]
        return (0..<30).reversed().compactMap { daysAgo in
            guard daysAgo % 7 != 3 else { return nil }
            let usage = names.prefix(services).enumerated().map { index, name in
                OpenAIDashboardServiceUsage(
                    service: name,
                    creditsUsed: self.wave(daysAgo + index * 5, base: Double(services - index) * 6))
            }
            return OpenAIDashboardDailyBreakdown(
                day: self.dayKey(daysAgo: daysAgo),
                services: usage,
                totalCreditsUsed: usage.reduce(0) { $0 + $1.creditsUsed })
        }
    }

    static func sessionHistory() -> PlanUtilizationSeriesHistory {
        let window: TimeInterval = 5 * 3600
        let latestReset = GalleryFixtures.now.addingTimeInterval(2 * 3600 + 14 * 60)
        let entries = (0..<26).compactMap { period -> PlanUtilizationHistoryEntry? in
            guard period % 9 != 4 else { return nil }
            let reset = latestReset.addingTimeInterval(-Double(period) * window)
            return PlanUtilizationHistoryEntry(
                capturedAt: reset.addingTimeInterval(-window / 3),
                usedPercent: min(100, self.wave(period, base: 80)),
                resetsAt: reset)
        }
        return PlanUtilizationSeriesHistory(name: .session, windowMinutes: 300, entries: entries.reversed())
    }

    static func weeklyHistory() -> PlanUtilizationSeriesHistory {
        let window: TimeInterval = 7 * 86400
        let latestReset = GalleryFixtures.now.addingTimeInterval(3 * 86400 + 4 * 3600)
        let entries = (0..<10).map { period in
            let reset = latestReset.addingTimeInterval(-Double(period) * window)
            return PlanUtilizationHistoryEntry(
                capturedAt: reset.addingTimeInterval(-86400),
                usedPercent: min(100, self.wave(period + 3, base: 90)),
                resetsAt: reset)
        }
        return PlanUtilizationSeriesHistory(name: .weekly, windowMinutes: 10080, entries: entries.reversed())
    }

    static func burndownHistory(finalUsed: Double = 59, lastSampleAge: TimeInterval = 60)
        -> PlanUtilizationSeriesHistory
    {
        let reset = GalleryFixtures.now.addingTimeInterval(3 * 86400 + 4 * 3600)
        let start = reset.addingTimeInterval(-7 * 86400)
        let elapsed = GalleryFixtures.now.addingTimeInterval(-lastSampleAge).timeIntervalSince(start)
        let entries = (0...12).map { step in
            let fraction = Double(step) / 12
            let used = finalUsed * pow(fraction, 1.15) + (step % 3 == 1 && step < 12 ? 2 : 0)
            return PlanUtilizationHistoryEntry(
                capturedAt: start.addingTimeInterval(elapsed * fraction),
                usedPercent: min(100, used),
                resetsAt: reset)
        }
        return PlanUtilizationSeriesHistory(name: .weekly, windowMinutes: 10080, entries: entries)
    }

    static func storage(count: Int) -> ProviderStorageFootprint {
        let names = [
            "sessions", "projects", "cache", "logs", "shell-snapshots", "todos", "statsig", "ide", "plugins",
            "downloads",
        ]
        let components = (0..<count).map { index in
            ProviderStorageFootprint.Component(
                path: "/Users/alex/.example-agent/\(names[index % names.count])",
                totalBytes: Int64(Double(1_800_000_000) / pow(1.75, Double(index))))
        }
        return ProviderStorageFootprint(
            provider: .claude,
            totalBytes: components.reduce(0) { $0 + $1.totalBytes },
            paths: ["/Users/alex/.example-agent"],
            missingPaths: [],
            unreadablePaths: [],
            components: components,
            updatedAt: GalleryFixtures.now)
    }

    static let statusComponents: [ProviderStatusComponent] = [
        .init(id: "api", name: "API", indicator: .none, status: "operational"),
        .init(id: "console", name: "Console", indicator: .minor, status: "degraded_performance"),
        .init(id: "code", name: "Code assistant", indicator: .major, status: "partial_outage"),
        .init(id: "auth", name: "Sign-in", indicator: .critical, status: "major_outage"),
        .init(id: "billing", name: "Billing", indicator: .maintenance, status: "under_maintenance"),
        .init(id: "docs", name: "Docs", indicator: .unknown, status: "unknown"),
        .init(
            id: "regions",
            name: "Regions",
            indicator: .minor,
            status: "degraded_performance",
            children: [
                .init(id: "us", name: "US", indicator: .none, status: "operational"),
                .init(id: "eu", name: "EU", indicator: .minor, status: "degraded_performance"),
            ]),
    ]

    static func spendGroup(priced: Bool = true) -> SpendDashboardModel.CurrencyGroup? {
        let providers: [(String, UsageProvider, String, Double)] = [
            ("claude", .claude, "Claude", 9),
            ("codex", .codex, "Codex", 5),
            ("cursor", .cursor, "Cursor", 2.5),
        ]
        let inputs = providers.enumerated().map { index, provider in
            let daily = (0..<30).reversed().compactMap { daysAgo -> CostUsageDailyReport.Entry? in
                guard (daysAgo + index) % 6 != 0 || index == 0 else { return nil }
                let cost = self.wave(daysAgo + index * 4, base: provider.3)
                return CostUsageDailyReport.Entry(
                    date: self.dayKey(daysAgo: daysAgo),
                    inputTokens: nil,
                    outputTokens: nil,
                    totalTokens: Int(cost * 100_000),
                    costUSD: priced ? cost : nil,
                    modelsUsed: nil,
                    modelBreakdowns: nil)
            }
            let snapshot = CostUsageTokenSnapshot(
                sessionTokens: nil,
                sessionCostUSD: nil,
                last30DaysTokens: daily.compactMap(\.totalTokens).reduce(0, +),
                last30DaysCostUSD: priced ? daily.compactMap(\.costUSD).reduce(0, +) : nil,
                daily: daily,
                updatedAt: GalleryFixtures.now)
            return SpendDashboardModel.ProviderInput(
                id: provider.0,
                provider: provider.1,
                displayName: provider.2,
                snapshot: snapshot)
        }
        return SpendDashboardModel.build(
            inputs: inputs,
            requestedDays: 30,
            now: GalleryFixtures.now,
            calendar: self.calendar).groups.first
    }

    static func activityPoints() -> [SpendDashboardModel.TokenActivityPoint] {
        (0..<365).map { daysAgo in
            let day = self.day(daysAgo: daysAgo)
            if (40..<46).contains(daysAgo) {
                return .init(day: day, totalTokens: nil)
            }
            let weekday = self.calendar.component(.weekday, from: day)
            let isWeekend = weekday == 1 || weekday == 7
            let active = daysAgo < 220 && (daysAgo * 7 + 3) % 11 != 0 && !(isWeekend && daysAgo % 3 != 0)
            let tokens = active ? Int(self.wave(daysAgo, base: 4_000_000)) : 0
            return .init(day: day, totalTokens: tokens)
        }
    }

    private static let activityModeSuiteName = "openbar.render-gallery.charts"

    /// Renders `content` with its `@AppStorage` view mode backed by a throwaway defaults suite.
    static func withActivityMode(_ mode: SpendActivityViewMode, _ content: some View) -> some View {
        let defaults = UserDefaults(suiteName: self.activityModeSuiteName) ?? .standard
        defaults.removePersistentDomain(forName: self.activityModeSuiteName)
        defaults.set(mode.rawValue, forKey: "spendActivityViewMode")
        return content.defaultAppStorage(defaults)
    }

    static func removeActivityModeSuite() {
        UserDefaults(suiteName: self.activityModeSuiteName)?.removePersistentDomain(forName: self.activityModeSuiteName)
    }

    static func liveUsage() -> OpenAILiveUsageSnapshot {
        let fetchedAt = GalleryFixtures.now
        let start = fetchedAt.addingTimeInterval(-60 * 60)
        let minutes = (0..<60).map { index in
            // The last two minutes have not reported yet, so the chart shows its pending tail.
            let reported = index < 58
            let models = self.liveModels.enumerated().map { modelIndex, name in
                let input = reported ? Int(self.wave(index + modelIndex * 9, base: Double(4 - modelIndex) * 9000)) : 0
                return OpenAILiveUsageSnapshot.ModelUsage(
                    name: name,
                    inputTokens: input,
                    cachedInputTokens: input * (modelIndex + 1) / 6,
                    outputTokens: input / 4,
                    requests: max(1, input / 1500))
            }
            return OpenAILiveUsageSnapshot.Minute(start: start.addingTimeInterval(Double(index) * 60), models: models)
        }
        return OpenAILiveUsageSnapshot(minutes: minutes, windowMinutes: 60, fetchedAt: fetchedAt, projectID: nil)
    }
}
