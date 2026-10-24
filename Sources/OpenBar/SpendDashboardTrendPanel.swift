import AppKit
import OpenBarCore
import SwiftUI

struct SpendDashboardTrendPanel: View {
    let group: SpendDashboardModel.CurrencyGroup
    @Binding var selection: SpendDashboardTrendSection
    var onSelectDay: ((Date) -> Void)?
    var onClearSelectedDay: (() -> Void)?
    @State var navigation = SpendDashboardCurrencyNavigation()

    var body: some View {
        let legendProviders = SpendTrendChartModel(
            group: self.group,
            section: self.activeSection,
            day: self.day,
            overviewInterval: self.navigation.focusedInterval).legendProviders(in: self.group)
        let sourceID = self.navigation.selectedTrendSourceID
            .flatMap { id in legendProviders.contains { $0.id == id } ? id : nil }
        return SpendDashboardPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text(self.activeSection == .hourly ? self.activeSection.title : L("Estimated spend"))
                        .font(OpenBarTheme.Fonts.cardTitle)
                    Spacer()
                    if !self.hourlyDays.isEmpty {
                        Picker(L("Usage & Spend"), selection: self.$selection) {
                            Text(SpendDashboardTrendSection.daily.pickerTitle).tag(SpendDashboardTrendSection.daily)
                            Text(SpendDashboardTrendSection.hourly.pickerTitle).tag(SpendDashboardTrendSection.hourly)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .frame(width: 140)
                        .accessibilityIdentifier("spend-dashboard-trend-picker")
                    }
                }
                if self.activeSection == .hourly, let day = self.day {
                    self.dayNavigation(day)
                } else {
                    HStack {
                        Text(self.scopeText).font(OpenBarTheme.Fonts.meta).foregroundStyle(.secondary)
                        Spacer()
                        if self.navigation.focusedInterval != nil {
                            Button(L("Overview")) { self.navigation.focusedInterval = nil }
                                .controlSize(.small).accessibilityIdentifier("spend-trend-back-overview")
                        }
                    }
                    Text(L("Click a bar to explore. Use the menu below for exact amounts."))
                        .font(OpenBarTheme.Fonts.meta).foregroundStyle(.secondary)
                }

                SpendTrendChart(
                    group: self.group,
                    section: self.activeSection,
                    day: self.day,
                    sourceID: sourceID,
                    overviewInterval: self.navigation.focusedInterval,
                    onSelectDay: { day in
                        self.navigation.focusedDay = self.group.calendar.startOfDay(for: day)
                        self.selection = .hourly
                    },
                    onSelectInterval: { self.navigation.focusedInterval = $0 })
                    .id(self.chartIdentity(sourceID: sourceID))

                MenuBarLayoutChipFlowLayout(spacing: 8) {
                    self.legend(providers: legendProviders, selectedSourceID: sourceID)
                }
            }
        }
        .onChange(of: self.group.selectedDay) { _, selectedDay in
            self.navigation.focusedDay = selectedDay
            self.selection = selectedDay != nil && !self.hourlyDays.isEmpty ? .hourly : .daily
        }
        .onChange(of: self.group.chartDomain) { _, _ in self.navigation.focusedInterval = nil }
        .onChange(of: legendProviders.map(\.id)) { _, ids in
            if let selectedSourceID = self.navigation.selectedTrendSourceID,
               !ids.contains(selectedSourceID) { self.navigation.selectedTrendSourceID = nil }
        }
    }

    private func chartIdentity(sourceID: String?) -> String {
        "\(self.activeSection):\(self.day?.timeIntervalSince1970 ?? 0):"
            + "\(sourceID ?? "all"):\(self.group.chartDomain):"
            + "\(self.navigation.focusedInterval?.start.timeIntervalSince1970 ?? 0)"
    }

    private var scopeText: String {
        let scope = self.navigation.focusedInterval.map { $0.start...$0.end } ?? self.group.chartDomain
        let unit = SpendTrendChartModel.overviewUnit(in: scope, calendar: self.group.calendar)
        let grouping = unit == .month ? L("Monthly") : unit == .weekOfYear ? L("Weekly") : L("Daily")
        return "\(self.dateText(scope.lowerBound)) – "
            + "\(self.dateText(scope.upperBound.addingTimeInterval(-1))) · \(grouping)"
    }

    private var activeSection: SpendDashboardTrendSection {
        self.hourlyDays.isEmpty ? .daily : self.selection
    }

    private var hourlyDays: [Date] {
        SpendTrendChartModel.hourlyDays(self.group)
    }

    private var day: Date? {
        SpendTrendChartModel.focusedDay(self.navigation.focusedDay, group: self.group)
    }

    private func dayNavigation(_ day: Date) -> some View {
        let index = self.hourlyDays.firstIndex(of: day)
        return HStack(spacing: 8) {
            Button {
                self.navigation.focusedDay = self.hourlyDays[max(0, (index ?? 0) - 1)]
            } label: { Image(systemName: "chevron.left") }
                .disabled(index == nil || index == 0)
                .help(L("Previous day"))
                .accessibilityLabel(L("Previous day"))
                .accessibilityIdentifier("spend-trend-previous-day")
            Picker(L("Day"), selection: Binding(
                get: { day },
                set: { self.navigation.focusedDay = $0 }))
            {
                ForEach(self.hourlyDays, id: \.self) { date in
                    Text(self.dateText(date)).tag(date)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 180)
            .accessibilityIdentifier("spend-trend-day-picker")
            Button {
                self.navigation.focusedDay = self.hourlyDays[min(self.hourlyDays.count - 1, (index ?? 0) + 1)]
            } label: { Image(systemName: "chevron.right") }
                .disabled(index == nil || (index ?? 0) >= self.hourlyDays.count - 1)
                .help(L("Next day"))
                .accessibilityLabel(L("Next day"))
                .accessibilityIdentifier("spend-trend-next-day")
            Spacer()
            if let onClearSelectedDay, self.group.selectedDay != nil {
                Button(L("Clear")) {
                    self.selection = .daily
                    onClearSelectedDay()
                }
                .accessibilityIdentifier("spend-trend-clear-day")
            } else if let onSelectDay, self.group.selectedDay == nil {
                Button(L("Models for this day")) { onSelectDay(day) }
                    .accessibilityIdentifier("spend-trend-day-details")
            }
        }
        .controlSize(.small)
    }

    private func legend(providers: [SpendDashboardModel.ProviderRow], selectedSourceID: String?) -> some View {
        ForEach(providers) { provider in
            Button {
                self.navigation.selectedTrendSourceID = self.navigation.selectedTrendSourceID == provider
                    .id ? nil : provider.id
            } label: {
                HStack(spacing: 5) {
                    Circle().fill(Color(nsColor: SpendChartPalette.color(
                        sourceID: provider.id, provider: provider.provider, providers: self.group.providers)))
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    SpendProviderIcon(
                        provider: provider.provider, sourceKind: provider.sourceKind, style: .brand)
                    Text(SpendChartPalette.label(provider, providers: self.group.providers))
                        .font(OpenBarTheme.Fonts.meta)
                        .fixedSize()
                }
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(
                    selectedSourceID == provider.id ? OpenBarTheme.Colors.cardFill : .clear,
                    in: RoundedRectangle(cornerRadius: OpenBarRadius.control, style: .continuous))
                .opacity(selectedSourceID == nil || selectedSourceID == provider.id ? 1 : 0.6)
            }
            .buttonStyle(.plain)
            .help(L("Click to isolate a source. Click again to show all."))
            .accessibilityAddTraits(selectedSourceID == provider.id ? .isSelected : [])
            .accessibilityIdentifier("spend-trend-source-\(provider.id)")
        }
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(
            locale: openBarLocalizedLocale(),
            calendar: self.group.calendar,
            timeZone: self.group.timeZone).year().month(.abbreviated).day())
    }
}

struct SpendTrendChart: View {
    let group: SpendDashboardModel.CurrencyGroup
    let section: SpendDashboardTrendSection
    let day: Date?
    let sourceID: String?
    var overviewInterval: DateInterval?
    var onSelectDay: ((Date) -> Void)?
    var onSelectInterval: ((DateInterval) -> Void)?
    @State private var inspectedDate: Date?
    @State private var pinnedDate: Date?

    private var model: SpendTrendChartModel {
        SpendTrendChartModel(
            group: self.group,
            section: self.section,
            day: self.day,
            sourceID: self.sourceID,
            overviewInterval: self.overviewInterval)
    }

    var body: some View {
        let model = self.model
        VStack(alignment: .leading, spacing: 10) {
            if self.section == .hourly {
                Text(model.hourlyTimeZoneText)
                    .font(OpenBarTheme.Fonts.meta).foregroundStyle(.secondary)
                    .help(self.group.timeZone.identifier)
                    .accessibilityLabel("\(L("Statistics time zone")): \(model.hourlyTimeZoneText)")
                    .accessibilityIdentifier("spend-trend-time-zone")
            }
            if model.segments.isEmpty {
                Text(model.emptyStateTitle(group: self.group, sourceID: self.sourceID))
                    .font(OpenBarTheme.Fonts.meta)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 210)
            } else {
                self.summary(model)
                self.chart(model)
                self.inspection(model)
            }
        }
    }

    private func summary(_ model: SpendTrendChartModel) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                self.totalSummary(model)
                Spacer()
                self.peakSummary(model)
            }
            VStack(alignment: .leading, spacing: 5) {
                self.totalSummary(model)
                self.peakSummary(model)
            }
        }
        .font(OpenBarTheme.Fonts.meta)
    }

    private func totalSummary(_ model: SpendTrendChartModel) -> some View {
        HStack(spacing: 8) {
            Text(L(model.recordedSpendLabel)).foregroundStyle(.secondary)
            Text(self.costText(model.total)).font(OpenBarTheme.Fonts.laneValue)
        }
    }

    @ViewBuilder
    private func peakSummary(_ model: SpendTrendChartModel) -> some View {
        if let peak = model.peak {
            HStack(spacing: 8) {
                Text(L("Highest recorded spend")).foregroundStyle(.secondary)
                Text("\(self.bucketText(peak.date, model: model)) · \(self.costText(peak.total))").monospacedDigit()
            }
        }
    }

    private func chart(_ model: SpendTrendChartModel) -> some View {
        let topIDs = spendTopOfStackIDs(for: model.segments, key: \.date, id: \.id, stackEnd: \.end)
        let ruleDate = (self.inspectedDate ?? self.pinnedDate).flatMap { model.inspectionDate(at: $0) }
        return SpendTrendPlot(
            model: model,
            roundedTopIDs: topIDs,
            highlightDate: ruleDate.map { self.center(of: $0, unit: model.unit) },
            xTicks: self.section == .hourly
                ? model.hourlyTicks
                : self.strideTicks(model),
            xTickText: { date in
                self.section == .hourly ? model.hourlyAxisText(date) : self.axisText(date, unit: model.unit)
            },
            yTickText: { UsageFormatter.compactCurrencyString($0, currencyCode: self.group.currencyCode) },
            color: { segment in
                Color(nsColor: SpendChartPalette.color(
                    sourceID: segment.sourceID, provider: segment.provider, providers: self.group.providers))
            },
            onHover: { date in self.inspectedDate = date.flatMap { model.inspectionDate(at: $0) } },
            onTap: { location in
                guard let date = model.inspectionDate(at: location) else { return }
                self.pinnedDate = date
                self.inspectedDate = nil
                guard self.section == .daily else { return }
                if model.unit != .day, let interval = model.interval(at: date) {
                    self.onSelectInterval?(interval)
                } else if self.group.hourlyPoints.contains(where: {
                    self.group.calendar.isDate($0.hour, inSameDayAs: date)
                }) {
                    self.onSelectDay?(date)
                }
            })
            .frame(height: 210)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(self.section.title)
            .accessibilityValue(self.section == .hourly
                ? spendDashboardHourlyChartAccessibilityValue(
                    hourCount: model.buckets.count,
                    serviceCount: Set(model.segments.map(\.sourceID)).count)
                : "\(self.groupingText(model)) · \(self.dateText(model.scope.lowerBound)) – "
                + self.dateText(model.scope.upperBound.addingTimeInterval(-1)))
            .accessibilityChildren {
                ForEach(model.segments) { segment in
                    Text("\(self.sourceText(segment)), \(self.bucketText(segment.date, model: model))")
                        .accessibilityValue(self.costText(segment.cost, sourceID: segment.sourceID))
                }
            }
            .accessibilityIdentifier("spend-trend-chart")
    }

    /// Every `tickStride` units from the start of the domain, like the former `.stride(by:count:)` axis.
    private func strideTicks(_ model: SpendTrendChartModel) -> [Date] {
        let count = self.tickStride(model)
        var ticks: [Date] = []
        var date = model.domain.lowerBound
        while date <= model.domain.upperBound, ticks.count < 400 {
            ticks.append(date)
            guard let next = self.group.calendar.date(byAdding: model.unit, value: count, to: date) else { break }
            date = next
        }
        return ticks
    }

    private func inspection(_ model: SpendTrendChartModel) -> some View {
        let date = (self.inspectedDate ?? self.pinnedDate).flatMap { model.inspectionDate(at: $0) }
        let bucket = date.flatMap { model.bucket(at: $0) } ?? (date == nil ? model.peak : nil)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Picker(self.groupingText(model), selection: Binding<Date?>(
                    get: { bucket?.date },
                    set: { self.pinnedDate = $0 }))
                {
                    if bucket == nil {
                        Text(self.bucketText(date ?? model.domain.lowerBound, model: model)).tag(nil as Date?)
                    }
                    ForEach(model.buckets) { item in
                        Text(self.bucketText(item.date, model: model)).tag(Optional(item.date))
                    }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small)
                .frame(maxWidth: 240, alignment: .leading)
                .accessibilityIdentifier("spend-trend-inspection-picker")
                if let bucket, self.section == .daily,
                   model.unit != .day || self.group.hourlyPoints.contains(where: {
                       self.group.calendar.isDate($0.hour, inSameDayAs: bucket.date)
                   })
                {
                    Button(model.unit == .day ? L("Hour") : L("Show details")) {
                        if model.unit == .day {
                            self.onSelectDay?(bucket.date)
                        } else if let interval = model.interval(at: bucket.date) {
                            self.onSelectInterval?(interval)
                        }
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("spend-trend-inspection-details")
                }
                Spacer()
                Text(bucket.map { self.costText($0.total) } ?? L("No data available"))
                    .font(OpenBarTheme.Fonts.laneValue)
            }
            MenuBarLayoutChipFlowLayout(spacing: 12) { self.inspectionRows(bucket) }
        }
        .font(OpenBarTheme.Fonts.meta)
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background(
            OpenBarTheme.Colors.cardFill,
            in: RoundedRectangle(cornerRadius: OpenBarRadius.control, style: .continuous))
        .accessibilityIdentifier("spend-trend-inspection")
    }

    private func inspectionRows(_ bucket: SpendTrendChartModel.Bucket?) -> some View {
        ForEach(bucket?.segments ?? []) { segment in
            HStack(spacing: 5) {
                Circle().fill(Color(nsColor: SpendChartPalette.color(
                    sourceID: segment.sourceID, provider: segment.provider, providers: self.group.providers)))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                SpendProviderIcon(
                    provider: segment.provider,
                    sourceKind: self.group.providers.first { $0.id == segment.sourceID }?.sourceKind ?? .native,
                    style: .brand)
                Text(self.sourceText(segment))
                Text(self.costText(segment.cost, sourceID: segment.sourceID))
            }
        }
    }

    private func center(of date: Date, unit: Calendar.Component) -> Date {
        guard let interval = self.group.calendar.dateInterval(of: unit, for: date)
        else { return date }
        return interval.start.addingTimeInterval(interval.duration / 2)
    }

    private func tickStride(_ model: SpendTrendChartModel) -> Int {
        let days = Double(model.visibleDayCount)
        if model.unit == .month { return max(1, Int(ceil(days / 30 / 4))) }
        if model.unit == .weekOfYear { return max(1, Int(ceil(days / 7 / 4))) }
        return days > 14 ? 7 : days > 7 ? 3 : 1
    }

    private func axisText(_ date: Date, unit: Calendar.Component) -> String {
        let format = Date.FormatStyle(
            locale: openBarLocalizedLocale(),
            calendar: self.group.calendar,
            timeZone: self.group.timeZone)
        if unit == .month { return date.formatted(format.year(.twoDigits).month(.abbreviated)) }
        return date.formatted(format.month().day())
    }

    private func groupingText(_ model: SpendTrendChartModel) -> String {
        switch model.unit {
        case .hour: L("Hour")
        case .month: L("Monthly")
        case .weekOfYear: L("Weekly")
        default: L("Day")
        }
    }

    private func bucketText(_ date: Date, model: SpendTrendChartModel) -> String {
        guard model.unit == .weekOfYear || model.unit == .month,
              let interval = model.interval(at: date) else { return self.dateText(date) }
        return "\(self.dateText(interval.start)) – \(self.dateText(interval.end.addingTimeInterval(-1)))"
    }

    private func dateText(_ date: Date) -> String {
        let format = Date.FormatStyle(
            locale: openBarLocalizedLocale(),
            calendar: self.group.calendar,
            timeZone: self.group.timeZone).year().month(.abbreviated).day()
        let text = date.formatted(format)
        return self.section == .hourly
            ? "\(text) · \(SpendTrendChartModel.hourText(date, calendar: self.group.calendar))" : text
    }

    private func sourceText(_ segment: SpendTrendChartModel.Segment) -> String {
        self.group.providers.first(where: { $0.id == segment.sourceID })
            .map { SpendChartPalette.label($0, providers: self.group.providers) } ?? segment.name
    }

    func costText(_ cost: Double?, sourceID: String? = nil) -> String {
        let source = (sourceID ?? self.sourceID).flatMap { id in self.group.providers.first { $0.id == id } }
        return spendDashboardMetricText(
            cost: cost,
            tokens: nil,
            currencyCode: self.group.currencyCode,
            costIsLowerBound: source.map { $0.costIsLowerBound || $0.incompleteRequestCount > 0 }
                ?? self.group.hasPartialCost)
    }
}

/// Stacked spend bars with a fixed leading y-axis, drawn with plain shapes and text. Swift Charts renders
/// through RenderBox's Metal backend on macOS 26+, which commits about 100 MB of GPU memory the first time
/// a window draws a chart. Styling follows docs/design/README.md §8: one path per source and opacity, a
/// 2-pt gap between bars and stacked segments, a 1-pt baseline, at most three grid lines, caption axes.
private struct SpendTrendPlot: View {
    let model: SpendTrendChartModel
    let roundedTopIDs: Set<String>
    /// The inspected bucket. Its bars keep full opacity while the others dim.
    let highlightDate: Date?
    let xTicks: [Date]
    let xTickText: (Date) -> String
    let yTickText: (Double) -> String
    let color: (SpendTrendChartModel.Segment) -> Color
    /// Receives the hovered date, or nil when the pointer leaves the plot.
    let onHover: (Date?) -> Void
    let onTap: (Date) -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    /// Room between the first and last bars and the plot edges.
    private static let edgePadding: CGFloat = 18
    private static let barWidthRatio: CGFloat = 0.72
    private static let yAxisSpacing: CGFloat = 4
    private static let tickLength: CGFloat = 3

    private var isHourly: Bool {
        self.model.section == .hourly
    }

    /// Height below the plot for ticks and one line of callout labels.
    private var xAxisHeight: CGFloat {
        self.isHourly ? 23 : 19
    }

    var body: some View {
        GeometryReader { proxy in
            let plotHeight = max(0, proxy.size.height - self.xAxisHeight)
            let gridValues = OpenBarTheme.Chart.gridValues(Self.yTicks(upperBound: self.model.yDomain.upperBound))
            HStack(alignment: .top, spacing: Self.yAxisSpacing) {
                self.yAxisLabels([0] + gridValues, plotHeight: plotHeight)
                GeometryReader { plot in
                    ZStack(alignment: .topLeading) {
                        OpenBarTheme.Chart.gridPath(values: gridValues, width: plot.size.width) {
                            self.y($0, plotHeight: plotHeight)
                        }
                        .stroke(
                            OpenBarTheme.Chart.gridColor(self.contrast),
                            lineWidth: OpenBarTheme.Chart.gridLineWidth)
                        OpenBarTheme.Chart.baselinePath(width: plot.size.width, bottom: plotHeight)
                            .stroke(OpenBarTheme.Chart.baselineColor, lineWidth: OpenBarTheme.Chart.baselineWidth)
                        if self.model.needsScrolling {
                            ScrollView(.horizontal) {
                                self.content(
                                    width: self.scrollWidth(visibleWidth: plot.size.width),
                                    plotHeight: plotHeight)
                                    .frame(height: plot.size.height)
                            }
                            .defaultScrollAnchor(.trailing)
                        } else {
                            self.content(width: plot.size.width, plotHeight: plotHeight)
                        }
                    }
                }
            }
        }
    }

    /// The scrollable plot shows the model's visible duration at a time, like `chartXVisibleDomain`.
    private func scrollWidth(visibleWidth: CGFloat) -> CGFloat {
        let domain = self.model.domain.upperBound.timeIntervalSince(self.model.domain.lowerBound)
        guard self.model.visibleDuration > 0, domain > 0 else { return visibleWidth }
        return visibleWidth * CGFloat(domain / self.model.visibleDuration)
    }

    private func content(width: CGFloat, plotHeight: CGFloat) -> some View {
        let x = { (date: Date) in self.x(date, width: width) }
        return ZStack(alignment: .topLeading) {
            ForEach(self.barGroups(x: x, plotHeight: plotHeight), id: \.id) { group in
                group.path.fill(group.color)
            }
            self.xAxis(width: width, plotHeight: plotHeight)
        }
        .frame(width: width, alignment: .topLeading)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case let .active(location):
                self.onHover(self.date(at: location, width: width, plotHeight: plotHeight))
            case .ended:
                self.onHover(nil)
            }
        }
        .onTapGesture { location in
            guard let date = self.date(at: location, width: width, plotHeight: plotHeight) else { return }
            self.onTap(date)
        }
    }

    private struct BarGroup {
        let id: String
        let color: Color
        var path: Path
    }

    /// One path per source and opacity. Only the top segment of each stack has rounded corners, and a
    /// stacked segment leaves a 2-pt gap above the one below it.
    private func barGroups(x: (Date) -> CGFloat, plotHeight: CGFloat) -> [BarGroup] {
        var groups: [BarGroup] = []
        for segment in self.model.segments {
            guard let interval = self.model.calendar.dateInterval(of: self.model.unit, for: segment.date) else {
                continue
            }
            let start = x(interval.start)
            let end = x(interval.end)
            let width = OpenBarTheme.Chart.barWidth((end - start) * Self.barWidthRatio, pitch: end - start)
            let top = self.y(segment.end, plotHeight: plotHeight)
            var rect = CGRect(
                x: (start + end - width) / 2,
                y: top,
                width: width,
                height: self.y(segment.start, plotHeight: plotHeight) - top)
            if segment.start > 0 {
                rect.size.height -= OpenBarTheme.Chart.stackGap(segmentHeight: rect.height)
            }
            let path = self.roundedTopIDs.contains(segment.id)
                ? ChartBarPath.path([rect], roundsBottom: false)
                : Path(rect)
            let isDimmed = self.highlightDate.map { !interval.contains($0) } ?? false
            let id = "\(segment.sourceID)|\(isDimmed)"
            if let index = groups.firstIndex(where: { $0.id == id }) {
                groups[index].path.addPath(path)
            } else {
                let color = self.color(segment)
                groups.append(BarGroup(
                    id: id,
                    color: isDimmed ? color.opacity(OpenBarTheme.Chart.dimmedOpacity) : color,
                    path: path))
            }
        }
        return groups
    }

    @ViewBuilder
    private func xAxis(width: CGFloat, plotHeight: CGFloat) -> some View {
        // Short ticks below the baseline anchor the labels; there is no vertical grid.
        Path { path in
            for tick in self.xTicks {
                let tickX = self.x(tick, width: width)
                path.move(to: CGPoint(x: tickX, y: plotHeight))
                path.addLine(to: CGPoint(x: tickX, y: plotHeight + Self.tickLength))
            }
        }
        .stroke(OpenBarTheme.Chart.baselineColor, lineWidth: OpenBarTheme.Chart.gridLineWidth)
        ForEach(self.xTicks, id: \.self) { tick in
            // Edge labels start beside their tick; inner hourly labels center below theirs.
            let placement: (alignment: Alignment, dx: CGFloat, dy: CGFloat) =
                if !self.isHourly || tick == self.model.domain.lowerBound {
                    (.topLeading, 4, 4)
                } else if tick == self.model.domain.upperBound {
                    (.topTrailing, -4, 4)
                } else {
                    (.top, 0, 8)
                }
            Text(self.xTickText(tick))
                .font(self.isHourly ? OpenBarTheme.Chart.axisFont.monospacedDigit() : OpenBarTheme.Chart.axisFont)
                .foregroundStyle(OpenBarTheme.Chart.axisLabelColor)
                .fixedSize()
                .frame(width: 0, height: 0, alignment: placement.alignment)
                .position(x: self.x(tick, width: width) + placement.dx, y: plotHeight + placement.dy)
        }
    }

    private func yAxisLabels(_ ticks: [Double], plotHeight: CGFloat) -> some View {
        // Swift Charts started the plot on a whole point after its labels.
        WholePointWidthLayout {
            self.yAxisLabelStack(ticks, plotHeight: plotHeight)
        }
        .accessibilityHidden(true)
    }

    private func yAxisLabelStack(_ ticks: [Double], plotHeight: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            ForEach(ticks, id: \.self) { value in
                Text(self.yTickText(value))
                    .font(OpenBarTheme.Chart.axisFont)
                    .foregroundStyle(OpenBarTheme.Chart.axisLabelColor)
                    .fixedSize()
                    // A zero-height frame centers the label on its grid line.
                    .frame(height: 0)
                    .offset(y: self.y(value, plotHeight: plotHeight))
            }
        }
    }

    private func x(_ date: Date, width: CGFloat) -> CGFloat {
        let span = self.model.domain.upperBound.timeIntervalSince(self.model.domain.lowerBound)
        guard span > 0 else { return width / 2 }
        let range = max(0, width - Self.edgePadding * 2)
        return Self.edgePadding + range * CGFloat(date.timeIntervalSince(self.model.domain.lowerBound) / span)
    }

    private func y(_ value: Double, plotHeight: CGFloat) -> CGFloat {
        let upper = self.model.yDomain.upperBound
        guard upper > 0 else { return plotHeight }
        return plotHeight * (1 - CGFloat(min(max(value / upper, 0), 1)))
    }

    private func date(at location: CGPoint, width: CGFloat, plotHeight: CGFloat) -> Date? {
        guard location.y >= 0, location.y <= plotHeight, location.x >= 0, location.x <= width else { return nil }
        let range = width - Self.edgePadding * 2
        guard range > 0 else { return nil }
        let span = self.model.domain.upperBound.timeIntervalSince(self.model.domain.lowerBound)
        let fraction = Double((location.x - Self.edgePadding) / range)
        return self.model.domain.lowerBound.addingTimeInterval(span * fraction)
    }

    /// Round values from zero to the top of the domain, like the former `.automatic(desiredCount: 4)` axis.
    static func yTicks(upperBound: Double, desiredCount: Int = 4) -> [Double] {
        guard upperBound > 0, upperBound.isFinite else { return [0] }
        let raw = upperBound / Double(desiredCount)
        let magnitude = pow(10, floor(log10(raw)))
        let normalized = raw / magnitude
        let factor: Double = normalized >= 50.squareRoot() ? 10 : normalized >= 10.squareRoot() ? 5
            : normalized >= 2.squareRoot() ? 2 : 1
        let step = factor * magnitude
        guard step > 0, step.isFinite else { return [0] }
        let count = min(Int((upperBound / step).rounded(.down)), 20)
        return (0...count).map { Double($0) * step }
    }
}

/// Rounds its single subview's width up to a whole point and aligns it to the trailing edge.
private struct WholePointWidthLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(proposal) ?? .zero
        return CGSize(width: size.width.rounded(.up), height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        guard let subview = subviews.first else { return }
        let size = subview.sizeThatFits(proposal)
        subview.place(
            at: CGPoint(x: bounds.maxX - size.width, y: bounds.minY),
            proposal: ProposedViewSize(size))
    }
}
