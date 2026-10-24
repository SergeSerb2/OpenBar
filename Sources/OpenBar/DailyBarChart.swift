import AppKit
import OpenBarCore
import SwiftUI

/// Day-bucketed bar chart shared by the cost, credits, and usage-breakdown submenus.
///
/// Plain shapes and text instead of Swift Charts: Charts renders through RenderBox's Metal backend on
/// macOS 26+, which commits about 100 MB of GPU memory the first time a menu draws a chart. The geometry
/// follows the Charts layout these submenus used: whole-day bars at `ChartBarHoverSelection.barWidthRatio`,
/// a y scale from zero to the tallest mark, and caption dates centered under their bars.
struct DailyBarChart: View {
    struct Day {
        let date: Date
        /// Stacked bottom to top. An empty stack still takes part in hover selection.
        var segments: [Segment]
        /// Height of the incomplete-usage diamond, when the day has one.
        var incompleteMarkerValue: Double?
        let accessibilityValue: String
    }

    struct Segment {
        let value: Double
        let color: Color
    }

    struct YAxis {
        let values: [Double]
        let label: (Double) -> String
    }

    let days: [Day]
    let axisDates: [Date]
    var peak: (date: Date, value: Double)?
    var selectedIndex: Int?
    /// Inset of the first and last day from the plot edges.
    var plotPadding: CGFloat = 0
    var yAxis: YAxis?
    /// Receives the hovered day's index, or nil when the pointer leaves the chart.
    let onHover: (Int?) -> Void

    @Environment(\.locale) private var locale

    private static let selectionBandColor = Color(nsColor: .labelColor).opacity(0.1)
    private static let markerColor = Color.secondary
    /// Diagonal of a diamond covering the 20 square points of the former `symbolSize(20)` point mark.
    private static let markerSize = CGFloat(40).squareRoot()
    /// Swift Charts kept this much room between leading y labels and the plot.
    private static let yAxisSpacing: CGFloat = 9
    private static let yAxisLabelPadding: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let plotHeight = max(0, proxy.size.height - ChartAxisLabelLayout.xAxisHeight)
            let scale = UsageChartScale(values: self.markValues)
            HStack(alignment: .top, spacing: Self.yAxisSpacing) {
                if let yAxis, !yAxis.values.isEmpty {
                    self.yAxisLabels(yAxis, scale: scale, plotHeight: plotHeight)
                }
                GeometryReader { plotProxy in
                    self.plot(
                        frame: CGRect(x: 0, y: 0, width: plotProxy.size.width, height: plotHeight),
                        scale: scale)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityChildren {
            ForEach(self.days.indices, id: \.self) { index in
                let day = self.days[index]
                Text(day.date.formatted(self.dateFormat))
                    .accessibilityValue(day.accessibilityValue)
            }
        }
    }

    private var dateFormat: Date.FormatStyle {
        Date.FormatStyle.dateTime.month(.abbreviated).day().locale(self.locale)
    }

    /// Every value a mark reaches; the y scale tops out at the largest.
    private var markValues: [Double] {
        self.days.flatMap { day in
            [day.segments.reduce(0) { $0 + max(0, $1.value) }] + [day.incompleteMarkerValue].compactMap(\.self)
        } + [self.peak?.value].compactMap(\.self)
    }

    private func yAxisLabels(_ yAxis: YAxis, scale: UsageChartScale, plotHeight: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            ForEach(yAxis.values.indices, id: \.self) { index in
                let value = yAxis.values[index]
                Text(yAxis.label(value))
                    .font(.caption2)
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .padding(.leading, Self.yAxisLabelPadding)
                    .fixedSize()
                    // A zero-height frame centers the label on its value's line.
                    .frame(height: 0)
                    .offset(y: plotHeight * (1 - CGFloat(scale.fraction(for: value))))
            }
        }
        .accessibilityHidden(true)
    }

    private func plot(frame: CGRect, scale: UsageChartScale) -> some View {
        let position = self.dayPosition(width: frame.width)
        let bars = position.flatMap { position in
            ChartBarHoverSelection.calendarDayBars(
                dates: self.days.map(\.date),
                plotFrame: frame,
                position: position)
        } ?? []
        let y = { (value: Double) in frame.maxY - frame.height * CGFloat(scale.fraction(for: value)) }

        return ZStack(alignment: .topLeading) {
            ForEach(self.segmentPaths(bars: bars, y: y), id: \.color) { group in
                group.path.fill(group.color)
            }
            self.markerPath(bars: bars, y: y).fill(Self.markerColor)
            if let peak = self.peak, let bar = self.bar(for: peak.date, bars: bars) {
                let capStart = max(peak.value - scale.maximum * 0.05, 0)
                ChartBarPath.path(
                    [CGRect(x: bar.minX, y: y(peak.value), width: bar.width, height: y(capStart) - y(peak.value))],
                    roundsBottom: true)
                    .fill(Color(nsColor: .systemYellow))
            }
            if let index = self.selectedIndex, bars.indices.contains(index) {
                Path(bars[index].frame).fill(Self.selectionBandColor)
            }
            ForEach(self.axisLabels(position: position, frame: frame), id: \.date) { label in
                ChartAxisLabelLayout.xAxisDateLabel(Text(label.text), x: label.x, plotBottom: frame.maxY)
            }
            MouseLocationReader { location in
                self.updateSelection(location: location, plotFrame: frame, bars: bars)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
    }

    /// Plot-relative x for a date over whole days, from the first marked day's start to the last one's end.
    private func dayPosition(width: CGFloat) -> ((Date) -> CGFloat?)? {
        let calendar = Calendar.current
        let marked = self.days.filter { !$0.segments.isEmpty || $0.incompleteMarkerValue != nil }.map(\.date)
        guard let first = marked.min(), let last = marked.max(),
              let start = calendar.dateInterval(of: .day, for: first)?.start,
              let end = calendar.dateInterval(of: .day, for: last)?.end,
              end > start
        else { return nil }
        let span = end.timeIntervalSince(start)
        let range = max(0, width - self.plotPadding * 2)
        return { date in
            self.plotPadding + range * CGFloat(date.timeIntervalSince(start) / span)
        }
    }

    private func bar(for date: Date, bars: [ChartBarHoverSelection.Bar]) -> CGRect? {
        let calendar = Calendar.current
        guard let index = self.days.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: date) }),
              bars.indices.contains(index)
        else { return nil }
        return bars[index].frame
    }

    private struct SegmentGroup {
        let color: Color
        var path: Path
    }

    /// One path per color; only the top of each stack is rounded.
    private func segmentPaths(
        bars: [ChartBarHoverSelection.Bar],
        y: (Double) -> CGFloat) -> [SegmentGroup]
    {
        var groups: [SegmentGroup] = []
        for (day, bar) in zip(self.days, bars) {
            var base = 0.0
            let segments = day.segments.filter { $0.value > 0 }
            for (offset, segment) in segments.enumerated() {
                let top = base + segment.value
                let rect = CGRect(x: bar.frame.minX, y: y(top), width: bar.frame.width, height: y(base) - y(top))
                let path = offset == segments.count - 1
                    ? ChartBarPath.path([rect], roundsBottom: false)
                    : Path(rect)
                if let index = groups.firstIndex(where: { $0.color == segment.color }) {
                    groups[index].path.addPath(path)
                } else {
                    groups.append(SegmentGroup(color: segment.color, path: path))
                }
                base = top
            }
        }
        return groups
    }

    private func markerPath(bars: [ChartBarHoverSelection.Bar], y: (Double) -> CGFloat) -> Path {
        var path = Path()
        let half = Self.markerSize / 2
        for (day, bar) in zip(self.days, bars) {
            guard let value = day.incompleteMarkerValue else { continue }
            let center = CGPoint(x: bar.frame.midX, y: y(value))
            path.addLines([
                CGPoint(x: center.x, y: center.y - half),
                CGPoint(x: center.x + half, y: center.y),
                CGPoint(x: center.x, y: center.y + half),
                CGPoint(x: center.x - half, y: center.y),
            ])
            path.closeSubpath()
        }
        return path
    }

    private struct AxisLabel {
        let date: Date
        let text: String
        let x: CGFloat
    }

    /// Drops a label that would run into the y-axis labels, as Swift Charts did.
    private func axisLabels(position: ((Date) -> CGFloat?)?, frame: CGRect) -> [AxisLabel] {
        guard let position else { return [] }
        let font = NSFont.preferredFont(forTextStyle: .caption2)
        let hasYAxis = !(self.yAxis?.values.isEmpty ?? true)
        return self.axisDates.compactMap { date in
            guard let x = position(date) else { return nil }
            let text = date.formatted(self.dateFormat)
            if hasYAxis {
                let halfWidth = (text as NSString).size(withAttributes: [.font: font]).width / 2
                guard x - halfWidth >= -Self.yAxisSpacing else { return nil }
            }
            return AxisLabel(date: date, text: text, x: frame.minX + x)
        }
    }

    private func updateSelection(location: CGPoint?, plotFrame: CGRect, bars: [ChartBarHoverSelection.Bar]) {
        guard let location else {
            self.onHover(nil)
            return
        }
        guard let selection = ChartBarHoverSelection.selection(at: location, plotFrame: plotFrame, bars: bars)
        else { return }
        if selection.index != self.selectedIndex {
            self.onHover(selection.index)
        }
    }
}
