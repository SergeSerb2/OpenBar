import OpenBarCore
import SwiftUI

/// The three macOS tile shapes, decoupled from `WidgetFamily` so layouts can be rendered and
/// reasoned about outside a widget host.
enum WidgetTileSize {
    case small
    case medium
    case large

    var heroNumberSize: CGFloat {
        switch self {
        case .small: 24
        case .medium: 34
        case .large: 42
        }
    }

    var markSize: CGFloat {
        self == .small ? WidgetLayout.markSizeSmall : WidgetLayout.markSizeRegular
    }

    /// How many lanes fit below the headline before the tile starts clipping.
    ///
    /// A cost block costs about one lane of height and the history chart about two, so the budget
    /// has to know what else the tile is drawing — a fixed cap either clips a busy provider or
    /// pages a sparse one for no reason.
    func secondaryLaneCapacity(hasMetrics: Bool, hasChart: Bool) -> Int {
        switch self {
        case .small:
            return 2
        case .medium:
            return hasMetrics ? 2 : 3
        case .large:
            var capacity = 6
            if hasChart { capacity -= 2 }
            if hasMetrics { capacity -= 2 }
            return max(1, capacity)
        }
    }

    /// Small tiles list the remaining lanes as figures only: at 131pt of usable height a 7pt bar
    /// costs as much room as the number it duplicates.
    var showsSecondaryBars: Bool {
        self != .small
    }

    /// Large tiles carry the history chart, but only while the quota lanes leave it enough room to
    /// be a chart: squeezed to a few points it is noise, and the dedicated History widget covers
    /// providers with more lanes than that.
    func showsChart(laneCount: Int, hasHistory: Bool) -> Bool {
        self == .large && hasHistory && laneCount <= 3
    }

    var laneSpacing: CGFloat {
        self == .small ? 3 : WidgetLayout.laneSpacing
    }

    /// Days of history the large tile draws (docs/design/README.md, 9.5).
    static let largeHistoryDays = 7
}

// MARK: - Tile

/// Shared body for the usage, switcher, and account widgets across all three families.
///
/// One layout means the widgets cannot drift apart, and every size difference is a value in
/// `WidgetTileSize` rather than a separate near-duplicate view. Each family offers a few denser
/// variants through `ViewThatFits`, so long names, translations, and busy providers drop detail
/// (reset lines, then lanes, then the chart) instead of clipping.
struct UsageTile<Header: View>: View {
    @Environment(\.widgetUsageShowsUsed) private var showsUsed
    @Environment(\.widgetFixedNow) private var fixedNow
    let entry: WidgetSnapshot.ProviderEntry
    let size: WidgetTileSize
    /// Medium tiles nest the header in the headline column (docs/design/README.md, 9.5). Headers
    /// that carry their own controls, like the switcher's pager, need the full width instead.
    var headerSpansColumns: Bool = false
    @ViewBuilder let header: () -> Header

    var body: some View {
        let content = UsageTileContent(entry: self.entry, size: self.size)
        Group {
            switch self.size {
            case .small: self.small(content)
            case .medium: self.medium(content)
            case .large: self.large(content)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Small

    private struct SmallVariant: Hashable {
        let lanes: Int
        let detailWraps: Bool
        let showsMetrics: Bool
    }

    private func small(_ content: UsageTileContent) -> some View {
        // More lanes first; for each lane count, a wrapped reset line before a one-line one.
        var variants = [2, 1, 0].flatMap { lanes in
            [true, false].map { SmallVariant(lanes: lanes, detailWraps: $0, showsMetrics: true) }
        }
        variants.append(SmallVariant(lanes: 0, detailWraps: false, showsMetrics: false))
        return ViewThatFits(in: .vertical) {
            ForEach(variants, id: \.self) { variant in
                self.smallLayout(
                    content,
                    plan: content.plan(maxSecondaryLanes: variant.lanes, reservesOverflowRow: true),
                    metrics: variant.showsMetrics ? content.metrics : [],
                    detailWraps: variant.detailWraps)
            }
        }
    }

    private func smallLayout(
        _ content: UsageTileContent,
        plan: WidgetTilePlan,
        metrics: [WidgetMetricRow],
        detailWraps: Bool) -> some View
    {
        VStack(alignment: .leading, spacing: 0) {
            self.header()
            self.hero(content, plan: plan, spreads: true, detailWraps: detailWraps)
                .padding(.top, 6)
            if !plan.lanes.isEmpty || plan.overflowCount > 0 || !metrics.isEmpty {
                VStack(alignment: .leading, spacing: self.size.laneSpacing) {
                    self.lanes(content, plan: plan, showsResets: false, style: .compact)
                    self.metricRows(metrics)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: Medium

    private struct MediumVariant: Hashable {
        let lanes: Int
        let showsResets: Bool
        let metricLimit: Int
        let detailWraps: Bool
    }

    private func medium(_ content: UsageTileContent) -> some View {
        let capacity = self.size.secondaryLaneCapacity(hasMetrics: !content.metrics.isEmpty, hasChart: false)
        let metricCount = content.metrics.count
        var variants: [MediumVariant] = []
        // More lanes first. For each lane count: lane resets, then a wrapped headline reset, give way first.
        for lanes in stride(from: capacity, through: 0, by: -1) {
            for (showsResets, detailWraps) in [(true, true), (false, true), (true, false), (false, false)] {
                variants.append(MediumVariant(
                    lanes: lanes,
                    showsResets: showsResets,
                    metricLimit: metricCount,
                    detailWraps: detailWraps))
            }
        }
        variants.append(MediumVariant(
            lanes: 0,
            showsResets: false,
            metricLimit: min(1, metricCount),
            detailWraps: false))
        variants.append(MediumVariant(lanes: 0, showsResets: false, metricLimit: 0, detailWraps: false))
        return ViewThatFits(in: .vertical) {
            ForEach(variants.uniqued(), id: \.self) { variant in
                self.mediumLayout(
                    content,
                    plan: content.plan(maxSecondaryLanes: variant.lanes, reservesOverflowRow: true),
                    metrics: Array(content.metrics.prefix(variant.metricLimit)),
                    showsResets: variant.showsResets,
                    detailWraps: variant.detailWraps)
            }
        }
    }

    @ViewBuilder
    private func mediumLayout(
        _ content: UsageTileContent,
        plan: WidgetTilePlan,
        metrics: [WidgetMetricRow],
        showsResets: Bool,
        detailWraps: Bool) -> some View
    {
        // Medium splits into columns only when there is something to fill the right one. A lone
        // "+N more" line stays under the headline instead.
        let hasLanes = !plan.lanes.isEmpty
        if hasLanes || !metrics.isEmpty {
            VStack(alignment: .leading, spacing: WidgetLayout.sectionSpacing) {
                if self.headerSpansColumns {
                    self.header()
                }
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        if self.headerSpansColumns {
                            self.hero(content, plan: plan, spreads: true, detailWraps: detailWraps)
                        } else {
                            self.header()
                            Spacer(minLength: 8)
                            self.hero(content, plan: plan, spreads: false, detailWraps: detailWraps)
                        }
                    }
                    .frame(width: WidgetLayout.heroColumnWidth, alignment: .leading)
                    .frame(maxHeight: .infinity, alignment: .topLeading)

                    WidgetSeparator(axis: .vertical)
                        .padding(.horizontal, WidgetLayout.columnGap)

                    VStack(alignment: .leading, spacing: 0) {
                        if hasLanes {
                            if !metrics.isEmpty {
                                // Level with the header line, as in the mockup's "Today $4.12".
                                self.metricRows(metrics)
                                    .frame(minHeight: self.headerSpansColumns ? 0 : self.size.markSize)
                                Spacer(minLength: 8)
                            } else {
                                Spacer(minLength: 0)
                            }
                            VStack(alignment: .leading, spacing: WidgetLayout.laneSpacing) {
                                self.lanes(content, plan: plan, showsResets: showsResets, style: .regular)
                            }
                        } else {
                            // A single-lane provider: its cost sits level with the reset line.
                            Spacer(minLength: 0)
                            self.metricRows(metrics)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                self.header()
                Spacer(minLength: 8)
                self.hero(content, plan: plan, spreads: false, detailWraps: detailWraps)
                if plan.overflowCount > 0 {
                    self.overflowLine(plan.overflowCount)
                        .padding(.top, 4)
                }
            }
        }
    }

    // MARK: Large

    private struct LargeVariant: Hashable {
        let lanes: Int
        let showsChart: Bool
    }

    private func large(_ content: UsageTileContent) -> some View {
        let capacity = self.size.secondaryLaneCapacity(
            hasMetrics: !content.metrics.isEmpty,
            hasChart: content.hasChart)
        let variants = [
            LargeVariant(lanes: capacity, showsChart: content.hasChart),
            LargeVariant(lanes: capacity, showsChart: false),
            LargeVariant(lanes: min(capacity, 2), showsChart: false),
            LargeVariant(lanes: 0, showsChart: false),
        ]
        return ViewThatFits(in: .vertical) {
            ForEach(variants.uniqued(), id: \.self) { variant in
                self.largeLayout(
                    content,
                    plan: content.plan(maxSecondaryLanes: variant.lanes, reservesOverflowRow: false),
                    showsChart: variant.showsChart)
            }
        }
    }

    private func largeLayout(
        _ content: UsageTileContent,
        plan: WidgetTilePlan,
        showsChart: Bool) -> some View
    {
        VStack(alignment: .leading, spacing: 12) {
            self.header()
            self.hero(content, plan: plan, spreads: false, arrangement: .row)
            if !plan.lanes.isEmpty {
                self.laneGrid(content, lanes: plan.lanes)
            }
            if plan.overflowCount > 0 {
                self.overflowLine(plan.overflowCount)
            }
            // Cost rows and history anchor to the bottom edge, so a sparse provider does not leave
            // a block of empty tile under them.
            Spacer(minLength: 0)
            if !content.metrics.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetSeparator()
                    self.metricRows(content.metrics)
                }
            }
            if showsChart {
                UsageHistoryChart(
                    points: Array(self.entry.dailyUsage.suffix(WidgetTileSize.largeHistoryDays)),
                    color: content.color,
                    currencyCode: self.entry.tokenUsage?.currencyCode,
                    showsRange: false,
                    barHeight: WidgetLayout.historyChartHeight)
            }
        }
    }

    /// Two lanes per row: the large tile is wide enough that a single column wastes half of it. A
    /// single lane takes the full width.
    private func laneGrid(_ content: UsageTileContent, lanes: [WidgetTileLane]) -> some View {
        let perRow = lanes.count == 1 ? 1 : 2
        let rows = stride(from: 0, to: lanes.count, by: perRow).map {
            Array(lanes[$0..<min($0 + perRow, lanes.count)])
        }
        return VStack(alignment: .leading, spacing: WidgetLayout.sectionSpacing) {
            ForEach(rows, id: \.first?.id) { row in
                HStack(alignment: .top, spacing: 16) {
                    ForEach(row) { lane in
                        self.lane(content, lane: lane, showsReset: true, style: .regular)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if row.count < perRow {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                    }
                }
            }
        }
    }

    // MARK: Headline

    @ViewBuilder
    private func hero(
        _ content: UsageTileContent,
        plan: WidgetTilePlan,
        spreads: Bool,
        arrangement: HeroBlock.Arrangement = .stacked,
        detailWraps: Bool = true) -> some View
    {
        if let lane = plan.hero {
            let displayed = WidgetUsageDisplay.percent(
                fromRemaining: lane.remainingPercent,
                showUsed: self.showsUsed)
            HeroBlock(
                value: WidgetFormat.percent(displayed),
                caption: Text(WidgetLaneCopy.caption(title: lane.title, showUsed: self.showsUsed)),
                detail: self.resetText(lane),
                barPercent: displayed ?? 0,
                tone: QuotaSeverity.tone(remaining: lane.remainingPercent),
                color: content.color,
                numberSize: self.size.heroNumberSize,
                spreads: spreads,
                arrangement: arrangement,
                compact: self.size == .small,
                detailWraps: detailWraps)
                .accessibilityElement(children: .combine)
        } else if let fallback = content.fallback {
            HeroBlock(
                value: fallback.value,
                caption: WidgetFormat.tokenRowTitle(
                    fallback.caption,
                    summary: fallback.consumedMetricID == "session-cost" ? self.entry.tokenUsage : nil,
                    entryUpdatedAt: self.entry.updatedAt,
                    now: self.fixedNow),
                detail: fallback.detail.map { Text($0) },
                numberSize: self.size.heroNumberSize,
                spreads: spreads,
                arrangement: arrangement,
                compact: self.size == .small,
                detailWraps: detailWraps)
                .accessibilityElement(children: .combine)
        }
    }

    private func resetText(_ lane: WidgetTileLane) -> Text? {
        let now = self.fixedNow ?? Date()
        return switch WidgetLaneCopy.reset(resetsAt: lane.resetsAt, resetDescription: lane.resetDescription, now: now) {
        case let .date(reset): WidgetDateText.reset(reset, now: self.fixedNow)
        case let .text(value): Text(value)
        case nil: nil
        }
    }

    // MARK: Lanes

    @ViewBuilder
    private func lanes(
        _ content: UsageTileContent,
        plan: WidgetTilePlan,
        showsResets: Bool,
        style: QuotaLaneView.Style) -> some View
    {
        ForEach(plan.lanes) { lane in
            self.lane(content, lane: lane, showsReset: showsResets, style: style)
        }
        if plan.overflowCount > 0 {
            self.overflowLine(plan.overflowCount)
        }
    }

    private func lane(
        _ content: UsageTileContent,
        lane: WidgetTileLane,
        showsReset: Bool,
        style: QuotaLaneView.Style) -> some View
    {
        QuotaLaneView(
            title: lane.title,
            percent: WidgetUsageDisplay.percent(fromRemaining: lane.remainingPercent, showUsed: self.showsUsed),
            remainingPercent: lane.remainingPercent,
            color: content.color,
            showsBar: style == .regular && self.size.showsSecondaryBars,
            reset: showsReset ? self.resetText(lane) : nil,
            style: style)
    }

    private func overflowLine(_ count: Int) -> some View {
        Text(W("+%@ more", String(describing: count)))
            .font(WidgetTheme.Fonts.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: Cost and credit rows

    @ViewBuilder
    private func metricRows(_ lines: [WidgetMetricRow]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(lines) { line in
                    MetricLine(
                        title: WidgetFormat.tokenRowTitle(
                            line.title,
                            summary: ["session-cost", "last30"].contains(line.id) ? self.entry.tokenUsage : nil,
                            entryUpdatedAt: self.entry.updatedAt,
                            now: self.fixedNow),
                        value: line.value,
                        isProminent: line.isProminent)
                }
            }
        }
    }
}

extension Array where Element: Hashable {
    /// Order-preserving de-duplication. `ViewThatFits` traps on repeated child identities.
    fileprivate func uniqued() -> [Element] {
        var seen = Set<Element>()
        return self.filter { seen.insert($0).inserted }
    }
}

/// What a tile can draw for one entry, computed once per render and shared by every layout variant.
struct UsageTileContent {
    let color: Color
    let allLanes: [WidgetTileLane]
    let displayLanes: [WidgetTileLane]
    let hasChart: Bool
    let fallback: WidgetFallbackHeroContent?
    let metrics: [WidgetMetricRow]

    init(entry: WidgetSnapshot.ProviderEntry, size: WidgetTileSize) {
        self.color = WidgetColors.color(for: entry.provider)
        // The provider's compact row cap curates what a tile may LIST; it must not decide which
        // lane is binding. Headline and overflow are computed against the full set.
        let allLanes = WidgetTileLane.lanes(for: entry)
        let limit: Int? = switch size {
        case .small: WidgetUsageRow.smallWidgetRowLimit(for: entry)
        case .medium: WidgetUsageRow.mediumWidgetRowLimit(for: entry)
        case .large: nil
        }
        self.allLanes = allLanes
        self.displayLanes = limit == nil ? allLanes : WidgetTileLane.lanes(for: entry, limit: limit)
        self.hasChart = size.showsChart(laneCount: allLanes.count, hasHistory: !entry.dailyUsage.isEmpty)
        let fallback = allLanes.contains(where: \.isHeadlineCandidate) ? nil : WidgetFallbackHero.make(for: entry)
        self.fallback = fallback
        self.metrics = WidgetMetricRows.rows(
            for: entry,
            size: size,
            secondaryLaneCount: max(0, allLanes.count - 1),
            excluding: fallback?.consumedMetricID)
    }

    func plan(maxSecondaryLanes: Int, reservesOverflowRow: Bool) -> WidgetTilePlan {
        WidgetTilePlan.make(
            lanes: self.allLanes,
            displayCandidates: self.displayLanes,
            maxSecondaryLanes: maxSecondaryLanes,
            reservesOverflowRow: reservesOverflowRow)
    }
}

// MARK: - Metric rows

struct WidgetMetricRow: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
    var isProminent: Bool = false
}

enum WidgetMetricRows {
    /// Cost, credit and balance lines, trimmed to what each tile can show without clipping.
    static func rows(
        for entry: WidgetSnapshot.ProviderEntry,
        size: WidgetTileSize,
        secondaryLaneCount: Int = 0,
        excluding excludedID: String? = nil) -> [WidgetMetricRow]
    {
        let rows = self.allRows(for: entry, size: size, secondaryLaneCount: secondaryLaneCount)
            .filter { $0.id != excludedID }
        return Array(rows.prefix(self.rowCapacity(for: size)))
    }

    /// Hard ceiling per tile so an unusual provider (credits *and* costs *and* a balance) cannot
    /// push the lanes off the tile.
    private static func rowCapacity(for size: WidgetTileSize) -> Int {
        switch size {
        case .small: 1
        case .medium: 2
        case .large: 3
        }
    }

    private static func allRows(
        for entry: WidgetSnapshot.ProviderEntry,
        size: WidgetTileSize,
        secondaryLaneCount: Int) -> [WidgetMetricRow]
    {
        var rows: [WidgetMetricRow] = []
        if size == .small {
            // A small tile spends its height on quota lanes. With none below the headline the room
            // is there, so a single-lane provider gets its cost line instead of empty space.
            guard secondaryLaneCount == 0,
                  let token = entry.tokenUsage ?? WidgetUsageRow.compactTokenUsage(for: entry)
            else {
                return self.balanceRows(for: entry)
            }
            rows.append(self.sessionRow(token: token, entry: entry, isProminent: true, compact: true))
            return rows + self.balanceRows(for: entry)
        }

        if let credits = entry.creditsRemaining {
            rows.append(WidgetMetricRow(id: "credits", title: "Credits", value: WidgetFormat.credits(credits)))
        }
        if let token = entry.tokenUsage {
            // The medium tile's lanes column is ~136 pt wide: money alone fits beside its label there.
            rows.append(self.sessionRow(token: token, entry: entry, isProminent: true, compact: size == .medium))
            if size == .large {
                rows.append(WidgetMetricRow(
                    id: "last30",
                    title: token.last30DaysLabel,
                    value: WidgetFormat.costAndTokens(
                        cost: token.last30DaysCostUSD,
                        tokens: token.last30DaysTokens,
                        currencyCode: token.currencyCode)))
            }
        }
        return rows + self.balanceRows(for: entry)
    }

    private static func sessionRow(
        token: WidgetSnapshot.TokenUsageSummary,
        entry: WidgetSnapshot.ProviderEntry,
        isProminent: Bool,
        compact: Bool = false) -> WidgetMetricRow
    {
        // "$1.56 · 1.1M tokens" does not fit beside its label on a 127pt tile — the label loses and
        // renders as "T…". Prefer money when known, retaining tokens for unpriced history.
        let value = compact
            ? (token.sessionCostUSD.map { WidgetFormat.currency($0, code: token.currencyCode) }
                ?? token.sessionTokens.map(WidgetFormat.tokenCount)
                ?? WidgetFormat.unavailable)
            : WidgetFormat.costAndTokens(
                cost: token.sessionCostUSD,
                tokens: token.sessionTokens,
                currencyCode: token.currencyCode)
        return WidgetMetricRow(
            id: "session-cost",
            title: token.sessionLabel,
            value: value,
            isProminent: isProminent)
    }

    private static func balanceRows(for entry: WidgetSnapshot.ProviderEntry) -> [WidgetMetricRow] {
        var rows: [WidgetMetricRow] = []
        if let balance = WidgetBalanceFormatter.providerBalance(for: entry) {
            rows.append(WidgetMetricRow(id: "provider-balance", title: balance.title, value: balance.value))
        }
        if let balance = WidgetBalanceFormatter.extraUsageBalance(for: entry) {
            rows.append(WidgetMetricRow(id: "extra-usage", title: balance.title, value: balance.value))
        }
        return rows
    }
}

// MARK: - Headline fallback

struct WidgetFallbackHeroContent: Equatable {
    let value: String
    let caption: String
    let detail: String?
    /// The metric row this headline was built from. The tile drops it from the list below so the
    /// same figure is not printed twice.
    let consumedMetricID: String
}

enum WidgetFallbackHero {
    /// Balance-only and credit-only providers report no quota lanes, so the headline falls back to
    /// the figure those tiles do have instead of leaving the tile blank.
    static func make(for entry: WidgetSnapshot.ProviderEntry) -> WidgetFallbackHeroContent? {
        if let balance = WidgetBalanceFormatter.providerBalance(for: entry) {
            return WidgetFallbackHeroContent(
                value: balance.value,
                caption: balance.title,
                detail: nil,
                consumedMetricID: "provider-balance")
        }
        if let cost = WidgetBalanceFormatter.extraUsageCost(for: entry) {
            return WidgetFallbackHeroContent(
                value: WidgetFormat.currency(cost.used, code: cost.currencyCode),
                caption: W("Extra usage balance"),
                detail: nil,
                consumedMetricID: "extra-usage")
        }
        if let credits = entry.creditsRemaining {
            return WidgetFallbackHeroContent(
                value: WidgetFormat.credits(credits),
                caption: W("Credits left"),
                detail: nil,
                consumedMetricID: "credits")
        }
        guard let token = entry.tokenUsage else { return nil }
        guard let cost = token.sessionCostUSD else {
            return token.sessionTokens.map { tokens in
                WidgetFallbackHeroContent(
                    value: UsageFormatter.tokenCountString(tokens),
                    caption: W("%@ tokens", W(token.sessionLabel)),
                    detail: nil,
                    consumedMetricID: "session-cost")
            }
        }
        return WidgetFallbackHeroContent(
            value: WidgetFormat.currency(cost, code: token.currencyCode),
            caption: token.sessionLabel,
            detail: token.sessionTokens.map(WidgetFormat.tokenCount),
            consumedMetricID: "session-cost")
    }
}
