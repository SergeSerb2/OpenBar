import AppKit
import OpenBarCore
import SwiftUI

/// Day-bucketed bar chart shared by the cost, credits, and usage-breakdown submenus.
///
/// Plain shapes and text instead of Swift Charts: Charts renders through RenderBox's Metal backend on
/// macOS 26+, which commits about 100 MB of GPU memory the first time a menu draws a chart. Bars sit in
/// whole-day slots at `ChartBarHoverSelection.barWidthRatio` (hit-testing uses the same slots), the y scale
/// runs from zero to the tallest mark, and caption dates center under their bars. Styling follows
/// docs/design/README.md §8: one batched path per color, a 2-pt gap between bars and stacked segments,
/// a 1-pt baseline, and recessive grid lines at the y-axis ticks.
struct DailyBarChart: View {
    struct Day {
        let date: Date
        /// Stacked bottom to top. An empty stack still takes part in hover selection and draws a
        /// track-colored stub, so a day without a value reads as missing rather than as a gap.
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
    @Environment(\.colorSchemeContrast) private var contrast

    /// The peak day's cap: a thin text-colored tip, so it reads as an annotation, never as a series or a tone.
    private static let peakColor = Color(nsColor: .labelColor)
    private static let peakCapHeight: CGFloat = 3
    /// Incomplete requests are a data-quality warning; the diamond shape carries it without color.
    private static let markerColor = OpenBarTheme.Colors.warning
    private static let stubColor = OpenBarTheme.Colors.meterTrack
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
                    .font(OpenBarTheme.Chart.axisFont)
                    .foregroundStyle(OpenBarTheme.Chart.axisLabelColor)
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
        let marks = self.marks(bars: bars.map { Self.drawnFrame($0.frame) }, y: y)
        let gridValues = OpenBarTheme.Chart.gridValues(self.yAxis?.values ?? [])

        return ZStack(alignment: .topLeading) {
            if !gridValues.isEmpty {
                OpenBarTheme.Chart.gridPath(values: gridValues, width: frame.width, y: y)
                    .stroke(OpenBarTheme.Chart.gridColor(self.contrast), lineWidth: OpenBarTheme.Chart.gridLineWidth)
            }
            ForEach(marks.groups, id: \.color) { group in
                group.path.fill(group.color)
            }
            if !marks.stubs.isEmpty {
                marks.stubs.fill(Self.stubColor)
            }
            if let peakCap = marks.peakCap {
                peakCap.path.fill(Self.peakColor.opacity(peakCap.opacity))
            }
            self.markerPath(bars: bars, y: y).fill(Self.markerColor)
            OpenBarTheme.Chart.baselinePath(width: frame.width, bottom: frame.maxY)
                .stroke(OpenBarTheme.Chart.baselineColor, lineWidth: OpenBarTheme.Chart.baselineWidth)
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

    /// The drawn part of a day slot: the hit-test frame narrowed so neighbors keep a 2-pt gap.
    private static func drawnFrame(_ frame: CGRect) -> CGRect {
        let pitch = frame.width / ChartBarHoverSelection.barWidthRatio
        let width = OpenBarTheme.Chart.barWidth(frame.width, pitch: pitch)
        return CGRect(x: frame.midX - width / 2, y: frame.minY, width: width, height: frame.height)
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

    private struct SegmentGroup {
        let color: Color
        var path: Path
    }

    private struct Marks {
        var groups: [SegmentGroup] = []
        var stubs = Path()
        var peakCap: (path: Path, opacity: Double)?
    }

    /// One path per drawn color. Only the top of each stack is rounded; stacked segments keep a 2-pt
    /// gap. While a day is selected, the other days draw at the dimmed opacity.
    private func marks(bars: [CGRect], y: (Double) -> CGFloat) -> Marks {
        var marks = Marks()
        let calendar = Calendar.current
        for (index, (day, bar)) in zip(self.days, bars).enumerated() {
            let opacity = self.selectedIndex.map { $0 == index ? 1 : OpenBarTheme.Chart.dimmedOpacity } ?? 1
            if day.segments.isEmpty {
                let height = min(OpenBarTheme.Chart.missingStubHeight, bar.height)
                marks.stubs.addPath(ChartBarPath.path(
                    [CGRect(x: bar.minX, y: bar.maxY - height, width: bar.width, height: height)],
                    roundsBottom: false,
                    cornerRadius: height / 2))
                continue
            }
            var base = 0.0
            let segments = day.segments.filter { $0.value > 0 }
            for (offset, segment) in segments.enumerated() {
                let top = base + segment.value
                var rect = CGRect(x: bar.minX, y: y(top), width: bar.width, height: y(base) - y(top))
                if offset > 0 {
                    rect.size.height -= OpenBarTheme.Chart.stackGap(segmentHeight: rect.height)
                }
                let path = offset == segments.count - 1
                    ? ChartBarPath.path([rect], roundsBottom: false)
                    : Path(rect)
                let color = opacity < 1 ? segment.color.opacity(opacity) : segment.color
                if let groupIndex = marks.groups.firstIndex(where: { $0.color == color }) {
                    marks.groups[groupIndex].path.addPath(path)
                } else {
                    marks.groups.append(SegmentGroup(color: color, path: path))
                }
                base = top
            }
            if let peak = self.peak, calendar.isDate(peak.date, inSameDayAs: day.date) {
                let top = y(peak.value)
                let height = min(Self.peakCapHeight, max(0, y(0) - top))
                marks.peakCap = (
                    ChartBarPath.path(
                        [CGRect(x: bar.minX, y: top, width: bar.width, height: height)],
                        roundsBottom: false),
                    opacity)
            }
        }
        return marks
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
        let font = OpenBarTheme.Chart.axisNSFont
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
