import AppKit
import OpenBarCore
import SwiftUI

/// Tokens per minute over the live-usage window, stacked by model, or by token kind for one model.
///
/// Plain shapes and text instead of Swift Charts: Charts renders through RenderBox's Metal backend on
/// macOS 26+, which commits about 100 MB of GPU memory the first time a window draws a chart. The layout
/// and tick choices follow what the Swift Charts version produced; styling follows docs/design/README.md
/// §8 (chart palette in order, 2-pt gaps, a 1-pt baseline, at most three grid lines, a dashed limit rule).
struct OpenAILiveUsageChart: View {
    let snapshot: OpenAILiveUsageSnapshot
    let filter: OpenAILiveUsageModelFilter
    var tpmLimit: Int?
    @State private var selectedMinute: Date?
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorSchemeContrast) private var contrast

    private struct Segment {
        let minute: Date
        let label: String
        let tokens: Int
        var baseline: Int = 0
    }

    private enum Layout {
        /// Space under the plot for the time labels and the legend.
        static let seriesLegendInset: CGFloat = 36
        static let kindLegendInset: CGFloat = 38
        static let tickLength: CGFloat = 4
        static let labelGap: CGFloat = 4
        static let xLabelTop: CGFloat = 4.5
        static let legendSymbolGap: CGFloat = 5
        static let legendItemSpacing: CGFloat = 8
        /// Room the limit rule's caption needs above the rule inside the plot.
        static let limitCaptionHeight: CGFloat = 13
        /// Swift Charts kept annotations this far from the mark they label.
        static let annotationSpacing: CGFloat = 4
        static let barCornerRadius = OpenBarTheme.Chart.barCornerRadius
    }

    /// Model series (top five plus "Other") and token kinds take the chart palette in order.
    private static func seriesColor(at index: Int) -> Color {
        OpenBarTheme.Chart.seriesColor(index)
    }

    var body: some View {
        GeometryReader { proxy in
            self.chart(size: proxy.size)
        }
        .overlay(alignment: .bottomLeading) {
            self.legend
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            if let limit = self.tpmLimit, !self.showsLimitRule {
                Text(L("Org limit %@ TPM (off scale)", ProviderRateLimitNumber.format(limit)))
                    .font(OpenBarTheme.Fonts.caption).foregroundStyle(.secondary)
                    .padding(4)
                    .chartTooltipBackground(cornerRadius: OpenBarRadius.chip)
                    .padding(.leading, 4)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Tokens per minute"))
        .accessibilityChildren {
            ForEach(self.snapshot.series(for: self.filter).filter { !$0.isPending }, id: \.start) { point in
                Text(point.start.formatted(date: .omitted, time: .shortened))
                    .accessibilityValue(L(
                        "%@ tokens · %@ requests",
                        OpenAILiveUsageView.count(point.totalTokens),
                        OpenAILiveUsageView.count(point.requests)))
            }
        }
    }

    // MARK: - Plot

    private struct Geometry {
        let plot: CGRect
        let domain: ClosedRange<Date>
        let yTop: Double
        let yStep: Double

        func x(_ date: Date) -> CGFloat {
            let span = self.domain.upperBound.timeIntervalSince(self.domain.lowerBound)
            guard span > 0 else { return self.plot.minX }
            return self.plot.minX + self.plot.width * CGFloat(date.timeIntervalSince(self.domain.lowerBound) / span)
        }

        func y(_ tokens: Double) -> CGFloat {
            guard self.yTop > 0 else { return self.plot.maxY }
            return self.plot.maxY - self.plot.height * CGFloat(tokens / self.yTop)
        }

        func date(at x: CGFloat) -> Date? {
            guard self.plot.width > 0, x >= self.plot.minX, x <= self.plot.maxX else { return nil }
            let span = self.domain.upperBound.timeIntervalSince(self.domain.lowerBound)
            return self.domain.lowerBound.addingTimeInterval(span * Double((x - self.plot.minX) / self.plot.width))
        }
    }

    private func chart(size: CGSize) -> some View {
        let geometry = self.geometry(size: size)
        let ticks = self.yTicks(geometry)
        return ZStack(alignment: .topLeading) {
            self.grid(geometry, ticks: ticks)
            if let pendingStart = self.pendingStart {
                let rect = CGRect(
                    x: geometry.x(pendingStart),
                    y: geometry.plot.minY,
                    width: geometry.plot.maxX - geometry.x(pendingStart),
                    height: geometry.plot.height)
                Path(rect).fill(OpenBarTheme.Colors.cardFill)
                Text(L("reporting…")).font(OpenBarTheme.Fonts.caption).foregroundStyle(.secondary).fixedSize()
                    .padding(4)
                    .frame(width: 0, height: 0, alignment: .topTrailing)
                    .position(x: rect.maxX - Layout.annotationSpacing, y: rect.minY + Layout.annotationSpacing)
            }
            ForEach(self.barLayers(geometry), id: \.id) { layer in
                layer.path.fill(layer.color)
            }
            if let limit = self.tpmLimit, self.showsLimitRule {
                let y = geometry.y(Double(limit))
                Path { path in
                    path.move(to: CGPoint(x: geometry.plot.minX, y: y))
                    path.addLine(to: CGPoint(x: geometry.plot.maxX, y: y))
                }
                .stroke(OpenBarTheme.Chart.ruleColor, style: OpenBarTheme.Chart.ruleStyle)
                Text(L("Org limit %@ TPM", ProviderRateLimitNumber.format(limit)))
                    .font(OpenBarTheme.Fonts.caption).foregroundStyle(.secondary).fixedSize()
                    .frame(width: 0, height: 0, alignment: .bottomTrailing)
                    .position(x: geometry.plot.maxX, y: y - Layout.annotationSpacing)
            }
            self.axisLabels(geometry, ticks: ticks)
            if let point = self.selectedPoint {
                let x = geometry.x(point.start.addingTimeInterval(30))
                FittedTooltipLayout(
                    centerX: x,
                    top: geometry.plot.minY,
                    bounds: geometry.plot.minX...geometry.plot.maxX)
                {
                    self.tooltip(point)
                }
                .allowsHitTesting(false)
            }
            MouseLocationReader { location in
                let minute = location.flatMap { geometry.date(at: $0.x) }
                if minute != self.selectedMinute {
                    self.selectedMinute = minute
                }
            }
            .frame(width: geometry.plot.width, height: geometry.plot.height)
            .offset(x: geometry.plot.minX, y: geometry.plot.minY)
        }
    }

    private func geometry(size: CGSize) -> Geometry {
        let inset = self.isModelFilter ? Layout.kindLegendInset : Layout.seriesLegendInset
        let plotHeight = max(0, size.height - inset)
        let scale = self.yScale(plotHeight: plotHeight)
        // Swift Charts sized the label column in a first pass that ignored the limit caption, and kept that
        // width when the caption then raised the scale.
        let firstPass = self.yScale(plotHeight: nil)
        let labels = Self.labeledTicks(Self.yTickValues(top: scale.top, step: scale.step))
            + Self.labeledTicks(Self.yTickValues(top: firstPass.top, step: firstPass.step))
        let labelWidth = labels.map { Self.textWidth(OpenAILiveUsageView.count(Int($0))) }.max() ?? 0
        let trailing = scale.top > 0 ? ceil(labelWidth + Layout.tickLength + Layout.labelGap) : 0
        return Geometry(
            plot: CGRect(x: 0, y: 0, width: max(0, size.width - trailing), height: plotHeight),
            domain: self.domain,
            yTop: scale.top,
            yStep: scale.step)
    }

    private struct BarLayer {
        let id: Int
        let color: Color
        let path: Path
    }

    /// One path per color and opacity. Stacked model bars round only the top of each stack; the token-kind
    /// bars are separate floating ranges, rounded on every corner. Neighboring minutes and stacked segments
    /// keep a 2-pt gap where the width allows; while a minute is hovered, the others dim.
    private func barLayers(_ geometry: Geometry) -> [BarLayer] {
        var paths: [Int: Path] = [:]
        var colors: [Int: Color] = [:]
        let segments = self.segments
        let selectedMinute = self.selectedPoint?.start
        let topIndexes = Dictionary(grouping: segments.indices.filter { segments[$0].tokens > 0 }) {
            segments[$0].minute
        }.compactMapValues(\.last)
        for (index, segment) in segments.enumerated() where segment.tokens > 0 {
            let slotMinX = geometry.x(segment.minute)
            let slotMaxX = geometry.x(segment.minute.addingTimeInterval(60))
            let width = OpenBarTheme.Chart.barWidth(slotMaxX - slotMinX, pitch: slotMaxX - slotMinX)
            let minX = (slotMinX + slotMaxX - width) / 2
            let maxX = minX + width
            let base = segment.baseline + self.stackBase(index, segments: segments)
            let top = geometry.y(Double(base + segment.tokens))
            let bottom = geometry.y(Double(base))
            var rect = self.isModelFilter
                ? CGRect(x: minX, y: top, width: maxX - minX, height: bottom - top)
                : self.stackedSegmentRect(minX: minX, maxX: maxX, top: top, bottom: bottom)
            if base > 0 {
                rect.size.height -= OpenBarTheme.Chart.stackGap(segmentHeight: rect.height)
            }
            let roundsTop = self.isModelFilter || topIndexes[segment.minute] == index
            let radius = roundsTop ? min(Layout.barCornerRadius, rect.width / 2, rect.height / 2) : 0
            let bottomRadius = self.isModelFilter ? radius : 0
            let isDimmed = selectedMinute.map { $0 != segment.minute } ?? false
            let kind = self.colorKey(for: segment)
            let key = (
                id: kind.id * 2 + (isDimmed ? 1 : 0),
                color: isDimmed ? kind.color.opacity(OpenBarTheme.Chart.dimmedOpacity) : kind.color)
            colors[key.id] = key.color
            paths[key.id, default: Path()].addRoundedRect(
                in: rect,
                cornerRadii: RectangleCornerRadii(
                    topLeading: radius,
                    bottomLeading: bottomRadius,
                    bottomTrailing: bottomRadius,
                    topTrailing: radius))
        }
        return paths.keys.sorted().compactMap { id in
            guard let path = paths[id], let color = colors[id] else { return nil }
            return BarLayer(id: id, color: color, path: path)
        }
    }

    /// Swift Charts aligned stacked segment boundaries to device pixels, rounding toward the baseline,
    /// so neighboring segments meet without a hairline of background between them.
    private func stackedSegmentRect(minX: CGFloat, maxX: CGFloat, top: CGFloat, bottom: CGFloat) -> CGRect {
        let scale = max(self.displayScale, 1)
        let snap = { (value: CGFloat) in (value * scale).rounded(.up) / scale }
        return CGRect(x: minX, y: snap(top), width: maxX - minX, height: snap(bottom) - snap(top))
    }

    /// Model-wide stacks grow from the sum of earlier segments in the same minute.
    private func stackBase(_ index: Int, segments: [Segment]) -> Int {
        guard !self.isModelFilter else { return 0 }
        var base = 0
        var cursor = index - 1
        while cursor >= 0, segments[cursor].minute == segments[index].minute {
            base += max(0, segments[cursor].tokens)
            cursor -= 1
        }
        return base
    }

    /// Token kinds in stack order (uncached input, output, cached input) take palette slots 1–3.
    private func colorKey(for segment: Segment) -> (id: Int, color: Color) {
        if case .model = self.filter {
            let index = self.kindIndex(segment.label)
            return (index, Self.seriesColor(at: index))
        }
        let names = self.legendSeriesNames
        let index = names.firstIndex(of: segment.label) ?? 0
        return (index, Self.seriesColor(at: index))
    }

    private func kindIndex(_ label: String) -> Int {
        if label == L("Output") { return 1 }
        if label == L("Cached input") { return 2 }
        return 0
    }

    /// Recessive horizontal grid at the labeled ticks and a 1-pt baseline. No vertical grid: short ticks
    /// below the baseline anchor the time labels.
    private func grid(_ geometry: Geometry, ticks: [Double]) -> some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                for tick in Self.labeledTicks(ticks) where tick > 0 {
                    let y = geometry.y(tick)
                    path.move(to: CGPoint(x: geometry.plot.minX, y: y))
                    path.addLine(to: CGPoint(x: geometry.plot.maxX + Layout.tickLength, y: y))
                }
            }
            .stroke(OpenBarTheme.Chart.gridColor(self.contrast), lineWidth: OpenBarTheme.Chart.gridLineWidth)
            Path { path in
                let y = geometry.plot.maxY + OpenBarTheme.Chart.baselineWidth / 2
                path.move(to: CGPoint(x: geometry.plot.minX, y: y))
                path.addLine(to: CGPoint(x: geometry.plot.maxX + Layout.tickLength, y: y))
                for tick in self.xTicks {
                    let x = geometry.x(tick)
                    path.move(to: CGPoint(x: x, y: geometry.plot.maxY))
                    path.addLine(to: CGPoint(x: x, y: geometry.plot.maxY + Layout.tickLength))
                }
            }
            .stroke(OpenBarTheme.Chart.baselineColor, lineWidth: OpenBarTheme.Chart.baselineWidth)
        }
    }

    /// Zero plus at most three grid values, so the labels and the grid stay in step.
    private static func labeledTicks(_ ticks: [Double]) -> [Double] {
        guard !ticks.isEmpty else { return [] }
        return [0] + OpenBarTheme.Chart.gridValues(ticks)
    }

    private func axisLabels(_ geometry: Geometry, ticks: [Double]) -> some View {
        let format = Date.FormatStyle.dateTime.hour().minute()
        let chartWidth = geometry.plot.maxX + (geometry.yTop > 0
            ? Layout.tickLength + Layout.labelGap + self.yLabelWidth(ticks) : 0)
        let xLabels = self.xTicks.compactMap { tick -> (date: Date, text: String, x: CGFloat)? in
            let text = tick.formatted(format)
            let x = geometry.x(tick) + Layout.labelGap
            // Swift Charts dropped a time label that would run past the chart's trailing edge.
            guard x + Self.textWidth(text) <= chartWidth + 0.5 else { return nil }
            return (tick, text, x)
        }
        return ZStack(alignment: .topLeading) {
            ForEach(Self.labeledTicks(ticks), id: \.self) { tick in
                Text(OpenAILiveUsageView.count(Int(tick)))
                    .font(OpenBarTheme.Chart.axisFont)
                    .foregroundStyle(OpenBarTheme.Chart.axisLabelColor)
                    .fixedSize()
                    .frame(width: 0, height: 0, alignment: .leading)
                    .position(
                        x: geometry.plot.maxX + Layout.tickLength + Layout.labelGap,
                        y: geometry.y(tick))
            }
            ForEach(xLabels, id: \.date) { label in
                Text(label.text)
                    .font(OpenBarTheme.Chart.axisFont)
                    .foregroundStyle(OpenBarTheme.Chart.axisLabelColor)
                    .fixedSize()
                    .frame(width: 0, height: 0, alignment: .topLeading)
                    .position(x: label.x, y: geometry.plot.maxY + Layout.xLabelTop)
            }
        }
        .accessibilityHidden(true)
    }

    private func yLabelWidth(_ ticks: [Double]) -> CGFloat {
        Self.labeledTicks(ticks).map { Self.textWidth(OpenAILiveUsageView.count(Int($0))) }.max() ?? 0
    }

    private static func textWidth(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: OpenBarTheme.Chart.axisNSFont]).width
    }

    // MARK: - Scales

    /// Swift Charts' automatic y ticks for this chart: a 1/2/2.5/5 step that splits the scale into three or
    /// four intervals with the tightest top, leaving room for the limit caption when the rule is drawn.
    private func yScale(plotHeight: CGFloat?) -> (top: Double, step: Double) {
        var maximum = Double(self.stackTotals.max() ?? 0)
        if let limit = self.tpmLimit, self.showsLimitRule {
            maximum = max(maximum, Double(limit))
            if let plotHeight, plotHeight > Layout.limitCaptionHeight {
                maximum = max(maximum, Double(limit) * plotHeight / (plotHeight - Layout.limitCaptionHeight))
            }
        }
        return Self.niceScale(maximum: maximum)
    }

    static func niceScale(maximum: Double) -> (top: Double, step: Double) {
        guard maximum > 0, maximum.isFinite else { return (0, 0) }
        let magnitude = floor(log10(maximum))
        var best: (top: Double, step: Double)?
        for exponent in stride(from: magnitude - 2, through: magnitude + 1, by: 1) {
            for multiplier in [1.0, 2, 2.5, 5] {
                let step = multiplier * pow(10, exponent)
                let intervals = (maximum / step).rounded(.up)
                guard (3...4).contains(intervals) else { continue }
                let top = intervals * step
                if best.map({ top < $0.top }) ?? true {
                    best = (top, step)
                }
            }
        }
        return best ?? (maximum, maximum)
    }

    private static func yTickValues(top: Double, step: Double) -> [Double] {
        guard top > 0, step > 0 else { return [] }
        return stride(from: 0.0, through: top + step / 2, by: step)
            .filter { $0 <= top * (1 + 1e-9) && $0 == $0.rounded() }
    }

    private func yTicks(_ geometry: Geometry) -> [Double] {
        Self.yTickValues(top: geometry.yTop, step: geometry.yStep)
    }

    /// Time ticks from the first stride boundary in the window, using the smallest stride that keeps
    /// six or fewer ticks, as `AxisMarks(values: .automatic(desiredCount: 6))` did.
    private var xTicks: [Date] {
        let calendar = Calendar.current
        let domain = self.domain
        let strides: [(Calendar.Component, Int)] = [
            (.minute, 1), (.minute, 2), (.minute, 5), (.minute, 10), (.minute, 15), (.minute, 30),
            (.hour, 1), (.hour, 2), (.hour, 3), (.hour, 6), (.hour, 12),
        ]
        for (component, count) in strides {
            guard var tick = calendar.dateInterval(of: component, for: domain.lowerBound)?.start else { continue }
            if tick < domain.lowerBound,
               let next = calendar.date(byAdding: component, value: 1, to: tick)
            {
                tick = next
            }
            var ticks: [Date] = []
            while tick <= domain.upperBound, ticks.count <= 6 {
                ticks.append(tick)
                guard let next = calendar.date(byAdding: component, value: count, to: tick) else { break }
                tick = next
            }
            if ticks.count <= 6 { return ticks }
        }
        return [domain.lowerBound]
    }

    // MARK: - Data

    private var isModelFilter: Bool {
        if case .model = self.filter { return true }
        return false
    }

    private var showsLimitRule: Bool {
        guard let tpmLimit else { return false }
        return OpenAILiveUsageLimitsPolicy.showsRule(limit: tpmLimit, points: self.snapshot.series(for: self.filter))
    }

    private var segments: [Segment] {
        switch self.filter {
        case .allModels:
            let stacks = self.snapshot.stackedByModel()
            if stacks.isEmpty {
                return self.snapshot.series(for: .allModels).filter { !$0.isPending }.map {
                    Segment(minute: $0.start, label: L("All models"), tokens: 0)
                }
            }
            return stacks.filter { !$0.isPending }.map {
                Segment(
                    minute: $0.minute,
                    label: $0.modelOrOther == "Other" ? L("Other") : $0.modelOrOther,
                    tokens: $0.tokens)
            }
        case .model:
            return self.snapshot.series(for: self.filter).filter { !$0.isPending }.flatMap { point in
                [
                    Segment(
                        minute: point.start,
                        label: L("Uncached input"),
                        tokens: point.uncachedInputTokens),
                    Segment(
                        minute: point.start,
                        label: L("Output"),
                        tokens: point.outputTokens,
                        baseline: point.uncachedInputTokens),
                    Segment(
                        minute: point.start,
                        label: L("Cached input"),
                        tokens: point.cachedInputTokens,
                        baseline: point.uncachedInputTokens + point.outputTokens),
                ]
            }
        }
    }

    /// Height of each minute's stack, which the y scale has to reach.
    private var stackTotals: [Int] {
        Dictionary(grouping: self.segments, by: \.minute).values.map { segments in
            self.isModelFilter
                ? segments.map { $0.baseline + max(0, $0.tokens) }.max() ?? 0
                : segments.reduce(0) { $0 + max(0, $1.tokens) }
        }
    }

    /// Series in the order they first appear; each takes the next chart palette slot.
    private var legendSeriesNames: [String] {
        var names: [String] = []
        for segment in self.segments where !names.contains(segment.label) {
            names.append(segment.label)
        }
        return names
    }

    private var pendingStart: Date? {
        self.snapshot.series(for: .allModels).first(where: \.isPending)?.start
    }

    private var domain: ClosedRange<Date> {
        let first = self.snapshot.minutes.first?.start ?? self.snapshot.fetchedAt
        let end = self.snapshot.minutes.last?.start.addingTimeInterval(60) ?? first.addingTimeInterval(60)
        return first...max(first, end)
    }

    private var selectedPoint: OpenAILiveUsageSnapshot.Point? {
        guard let selectedMinute else { return nil }
        return self.snapshot.series(for: self.filter).first {
            $0.start <= selectedMinute && selectedMinute < $0.start.addingTimeInterval(60)
        }
    }

    // MARK: - Legend and tooltip

    @ViewBuilder
    private var legend: some View {
        if case .model = self.filter {
            HStack(spacing: 12) {
                self.legendItem(L("Uncached input"), color: Self.seriesColor(at: 0))
                self.legendItem(L("Cached input"), color: Self.seriesColor(at: 2))
                self.legendItem(L("Output"), color: Self.seriesColor(at: 1))
            }
            .font(OpenBarTheme.Fonts.caption)
        } else {
            HStack(spacing: Layout.legendItemSpacing) {
                ForEach(Array(self.legendSeriesNames.enumerated()), id: \.offset) { index, name in
                    self.legendItem(name, color: Self.seriesColor(at: index), spacing: Layout.legendSymbolGap)
                }
            }
            .font(OpenBarTheme.Fonts.caption)
        }
    }

    private func legendItem(_ title: String, color: Color, spacing: CGFloat = 4) -> some View {
        HStack(spacing: spacing) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).foregroundStyle(.secondary)
        }
    }

    private func tooltip(_ point: OpenAILiveUsageSnapshot.Point) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(point.start.formatted(date: .omitted, time: .shortened)).fontWeight(.semibold)
            if point.isPending {
                Text(L("reporting…"))
            } else {
                Text(L(
                    "%@ tokens · %@ requests",
                    OpenAILiveUsageView.count(point.totalTokens),
                    OpenAILiveUsageView.count(point.requests)))
                Text(L(
                    "Uncached input %@ · cached input %@ · output %@",
                    OpenAILiveUsageView.count(point.uncachedInputTokens),
                    OpenAILiveUsageView.count(point.cachedInputTokens),
                    OpenAILiveUsageView.count(point.outputTokens)))
                if point.batchTokens > 0 {
                    Text(L(
                        "Batch API %@ · not counted in %% of limit",
                        OpenAILiveUsageView.count(point.batchTokens)))
                }
                if self.filter == .allModels {
                    ForEach(
                        self.snapshot.minutes.first(where: { $0.start == point.start })?.models ?? [],
                        id: \.name)
                    { model in
                        Text("\(model.name): \(OpenAILiveUsageView.count(model.totalTokens))")
                    }
                }
            }
        }
        .font(OpenBarTheme.Fonts.meta)
        .padding(8)
        .chartTooltipBackground()
    }
}

/// Centers the tooltip on the selected minute and slides it to stay inside the plot, like the
/// `.fit` overflow resolution of the Swift Charts annotation it replaces.
private struct FittedTooltipLayout: Layout {
    let centerX: CGFloat
    let top: CGFloat
    let bounds: ClosedRange<CGFloat>

    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache _: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in rect: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let x = max(self.bounds.lowerBound, min(self.centerX - size.width / 2, self.bounds.upperBound - size.width))
            subview.place(
                at: CGPoint(x: rect.minX + x, y: rect.minY + self.top),
                anchor: .topLeading,
                proposal: ProposedViewSize(size))
        }
    }
}
