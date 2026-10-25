import OpenBarCore
import SwiftUI

struct ProviderDetailSectionsContent: View {
    let sections: [ProviderDetailSection]
    let chartColor: Color
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: OpenBarSpacing.section) {
            ForEach(Array(self.sections.enumerated()), id: \.offset) { index, section in
                if index > 0 {
                    Divider()
                }
                self.section(section)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Status tone of a row (spec §2.2). Meters keep the provider color; the tone marks the value.
    private static func tone(_ severity: ProviderDetailSection.Row.Severity?) -> OpenBarQuotaTone {
        switch severity {
        case .warning: .warning
        case .critical: .critical
        case .normal, nil: .normal
        }
    }

    private func section(_ section: ProviderDetailSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = section.title {
                Text(title)
                    .font(OpenBarTheme.Fonts.laneTitle)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
            }
            ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(row.label)
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 1) {
                            HStack(spacing: OpenBarSpacing.tight) {
                                let tone = Self.tone(row.severity)
                                let toneColor = tone.menuColor(highlighted: self.isHighlighted)
                                if let toneColor, let symbolName = tone.symbolName {
                                    Label(
                                        tone == .critical ? L("quota_warning_critical") :
                                            L("quota_warning_warning"),
                                        systemImage: symbolName)
                                        .labelStyle(.iconOnly)
                                        .foregroundStyle(toneColor)
                                }
                                Text(row.value)
                                    .foregroundStyle(toneColor ?? MenuHighlightStyle.primary(self.isHighlighted))
                                    .fontWeight(.medium)
                            }
                            if let secondaryValue = row.secondaryValue {
                                Text(secondaryValue)
                                    .font(OpenBarTheme.Fonts.caption)
                                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            }
                        }
                    }
                    .font(OpenBarTheme.Fonts.meta)
                    .lineLimit(1)
                    if let progress = row.progress {
                        // The ratio is provider data left unclamped by contract; only the bar's fill
                        // is clamped here, the "used / total" caption keeps the raw numbers.
                        UsageProgressBar(
                            percent: min(100, max(0, progress.usedPercent)),
                            tint: self.chartColor,
                            accessibilityLabel: row.label)
                    }
                }
            }
            if let chart = section.chart {
                ProviderDetailChartContent(chart: chart, color: self.chartColor)
            }
        }
    }
}

private struct ProviderDetailChartContent: View {
    let chart: ProviderDetailSection.Chart
    let color: Color
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if self.chart.title != nil || self.chart.unit != nil {
                HStack(spacing: 6) {
                    if let title = self.chart.title {
                        Text(title)
                            .font(.caption2.weight(.semibold))
                    }
                    Spacer(minLength: 0)
                    if let unit = self.chart.unit {
                        Text(unit)
                            .font(.caption2)
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .lineLimit(1)
            }
            Group {
                switch self.chart.kind {
                case .bars:
                    self.bars
                case .line:
                    self.line
                }
            }
            .frame(height: 58)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(self.accessibilityLabel)
        }
    }

    private var bars: some View {
        MenuUsageBarStrip(
            points: self.chart.points.enumerated().map { index, point in
                .init(id: String(index), value: point.value)
            },
            baseColor: self.color)
    }

    /// Plain shapes rather than `Canvas`: a Canvas renders through RenderBox's Metal backend, which commits
    /// ~100 MB of GPU memory the first time the menu draws it.
    private var line: some View {
        let values = self.chart.points.map(\.value)
        return ZStack {
            ProviderDetailLinePath(values: values)
                .stroke(
                    self.isHighlighted ? .white.opacity(0.82) : self.color,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            ProviderDetailLinePath(values: values, dotRadius: 1.5)
                .fill(self.isHighlighted ? .white : self.color)
        }
        .clipped()
        .overlay(alignment: .bottomLeading) {
            Rectangle()
                .fill(MenuHighlightStyle.secondary(self.isHighlighted).opacity(0.22))
                .frame(height: 1)
        }
    }

    private var accessibilityLabel: String {
        let title = self.chart.title.map { "\($0): " } ?? ""
        let unit = self.chart.unit.map { " \($0)" } ?? ""
        let points = self.chart.points.map { "\($0.label) \($0.value)\(unit)" }.joined(separator: ", ")
        return title + points
    }
}

/// The detail line chart's polyline, or a dot per point when `dotRadius` is set.
private struct ProviderDetailLinePath: Shape {
    let values: [Double]
    var dotRadius: CGFloat?

    func path(in rect: CGRect) -> Path {
        let scale = UsageChartScale(values: self.values)
        let points = self.values.enumerated().map { index, value in
            let x = self.values.count == 1
                ? rect.width / 2
                : rect.width * CGFloat(index) / CGFloat(self.values.count - 1)
            let y = rect.height * (1 - CGFloat(scale.fraction(for: value)))
            return CGPoint(x: rect.minX + x, y: rect.minY + y)
        }
        var path = Path()
        if let dotRadius {
            for point in points {
                path.addEllipse(in: CGRect(
                    x: point.x - dotRadius,
                    y: point.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2))
            }
        } else {
            path.addLines(points)
        }
        return path
    }
}
