import OpenBarCore
import SwiftUI

@MainActor
struct QuotaBurndownChartMenuView: View {
    private struct Series: Identifiable {
        let id: String
        let title: String
        let model: QuotaBurndownModel
        let lastKnownUsageMessage: String
    }

    private let series: [Series]
    private let width: CGFloat
    private let color: Color

    @State private var selectedSeriesID: String?

    init(
        provider: UsageProvider,
        histories: [PlanUtilizationSeriesHistory],
        width: CGFloat,
        referenceDate: Date = Date())
    {
        self.series = PlanUtilizationHistoryChartMenuView.visibleSeries(
            histories: histories, provider: provider, snapshot: nil).compactMap { series in
            let history = series.history
            guard [.session, .weekly, .monthly, .opus].contains(history.name),
                  let latest = history.entries.last,
                  let reset = latest.resetsAt,
                  latest.capturedAt <= referenceDate,
                  reset > referenceDate
            else { return nil }
            let window = ProviderDescriptorRegistry.descriptor(for: provider).pace.resolvedResetWindowForPace(
                RateWindow(
                    usedPercent: latest.usedPercent,
                    windowMinutes: history.windowMinutes,
                    resetsAt: reset,
                    resetDescription: nil))
            guard let model = QuotaBurndownModel(history: history, window: window, now: latest.capturedAt)
            else { return nil }
            return Series(
                id: series.id,
                title: series.title,
                model: model,
                lastKnownUsageMessage: LastKnownUsagePresentation.message(
                    capturedAt: latest.capturedAt,
                    now: referenceDate))
        }
        self.width = width
        let accent = ProviderAccentPalette.color(for: provider)
        self.color = Color(red: accent.red, green: accent.green, blue: accent.blue)
    }

    var body: some View {
        let selected = self.series.first(where: { $0.id == self.selectedSeriesID }) ?? self.series.first

        VStack(alignment: .leading, spacing: 10) {
            if self.series.count > 1 {
                Picker(selection: Binding(
                    get: { selected?.id ?? "" },
                    set: { self.selectedSeriesID = $0 }))
                {
                    ForEach(self.series) { series in
                        Text(series.title).tag(series.id)
                    }
                } label: {
                    EmptyView()
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            if let selected {
                QuotaBurndownPlot(model: selected.model, color: self.color)
                    .frame(height: 130)
                    .accessibilityElement()
                    .accessibilityLabel(L("Usage remaining"))
                    .accessibilityValue(selected.model.samples.last.map {
                        "\($0.remainingPercent.formatted(.number.precision(.fractionLength(0))))%"
                    } ?? L("No data"))

                HStack {
                    self.axisLabel(for: selected.model.start, model: selected.model, alignment: .leading)
                    Spacer()
                    self.axisLabel(for: selected.model.reset, model: selected.model, alignment: .trailing)
                }
                .font(OpenBarTheme.Chart.axisFont)
                .foregroundStyle(OpenBarTheme.Chart.axisLabelColor)

                if let remaining = selected.model.samples.last?.remainingPercent {
                    Text("\(remaining.formatted(.number.precision(.fractionLength(0))))% \(L("Usage remaining"))")
                        .font(OpenBarTheme.Fonts.meta)
                        .foregroundStyle(.secondary)
                }
                Text(selected.lastKnownUsageMessage)
                    .font(OpenBarTheme.Fonts.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L("No data"))
                    .font(OpenBarTheme.Fonts.meta)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 146)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minWidth: self.width, maxWidth: .infinity, alignment: .topLeading)
        .openBarLocalized()
    }

    var hasSeries: Bool {
        !self.series.isEmpty
    }

    private func axisLabel(
        for date: Date,
        model: QuotaBurndownModel,
        alignment: HorizontalAlignment) -> some View
    {
        VStack(alignment: alignment, spacing: 2) {
            if model.reset.timeIntervalSince(model.start) >= 86400 {
                Text(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()
                        .locale(openBarLocalizedLocale())))
            }
            Text(date.formatted(.dateTime.hour().minute().locale(openBarLocalizedLocale())))
        }
        .accessibilityElement(children: .combine)
    }

    #if DEBUG
    var _seriesTitlesForTesting: [String: String] {
        Dictionary(uniqueKeysWithValues: self.series.map { ($0.id, $0.title) })
    }

    var _seriesSampleCountsForTesting: [String: Int] {
        Dictionary(uniqueKeysWithValues: self.series.map { ($0.id, $0.model.samples.count) })
    }

    var _seriesLastKnownMessagesForTesting: [String: String] {
        Dictionary(uniqueKeysWithValues: self.series.map { ($0.id, $0.lastKnownUsageMessage) })
    }

    var _seriesStartsForTesting: [String: Date] {
        Dictionary(uniqueKeysWithValues: self.series.map { ($0.id, $0.model.start) })
    }

    var _seriesRemainingForTesting: [String: Double] {
        Dictionary(uniqueKeysWithValues: self.series.compactMap { series in
            series.model.samples.last.map { (series.id, $0.remainingPercent) }
        })
    }
    #endif
}

/// Ideal and observed remaining quota from the window start to its reset, on a 0–100% scale.
///
/// Plain shapes and text instead of Swift Charts, which renders through RenderBox's Metal backend on
/// macOS 26+ and commits about 100 MB of GPU memory the first time a menu draws a chart.
private struct QuotaBurndownPlot: View {
    let model: QuotaBurndownModel
    let color: Color
    @Environment(\.colorSchemeContrast) private var contrast

    private static let gridValues: [Double] = [0, 50, 100]
    /// Gap between the plot and its trailing percentage labels.
    private static let labelSpacing: CGFloat = 4
    /// Swift Charts reserved this width for the "100" label column.
    private static let labelColumnMinWidth: CGFloat = 20
    /// Diameter of a circle covering the 35 square points of the former `symbolSize(35)` point mark.
    private static let currentDotDiameter = 2 * (35 / CGFloat.pi).squareRoot()

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: Self.labelSpacing) {
                GeometryReader { plot in
                    self.plot(size: plot.size)
                }
                ZStack(alignment: .topLeading) {
                    ForEach(Self.gridValues, id: \.self) { value in
                        Text(value, format: .number)
                            .font(OpenBarTheme.Chart.axisFont)
                            .foregroundStyle(OpenBarTheme.Chart.axisLabelColor)
                            .fixedSize()
                            // A zero-height frame centers the label on its grid line.
                            .frame(height: 0)
                            .offset(y: proxy.size.height * (1 - value / 100))
                    }
                }
                .frame(minWidth: Self.labelColumnMinWidth, alignment: .leading)
            }
        }
    }

    private func plot(size: CGSize) -> some View {
        let span = max(self.model.reset.timeIntervalSince(self.model.start), 1)
        let point = { (sample: QuotaBurndownModel.Sample) in
            CGPoint(
                x: size.width * CGFloat(sample.date.timeIntervalSince(self.model.start) / span),
                y: size.height * (1 - CGFloat(sample.remainingPercent) / 100))
        }
        let y = { (value: Double) in size.height * (1 - CGFloat(value) / 100) }
        return ZStack(alignment: .topLeading) {
            OpenBarTheme.Chart.gridPath(
                values: OpenBarTheme.Chart.gridValues(Self.gridValues),
                width: size.width,
                y: y)
                .stroke(OpenBarTheme.Chart.gridColor(self.contrast), lineWidth: OpenBarTheme.Chart.gridLineWidth)
            OpenBarTheme.Chart.baselinePath(width: size.width, bottom: size.height)
                .stroke(OpenBarTheme.Chart.baselineColor, lineWidth: OpenBarTheme.Chart.baselineWidth)
            Path { $0.addLines(self.model.ideal.map(point)) }
                .stroke(OpenBarTheme.Chart.ruleColor, style: OpenBarTheme.Chart.ruleStyle)
            Path { $0.addLines(self.model.samples.map(point)) }
                .stroke(
                    self.color,
                    style: StrokeStyle(lineWidth: OpenBarTheme.Chart.lineWidth, lineCap: .round, lineJoin: .round))
            if let current = self.model.samples.last {
                let center = point(current)
                let diameter = Self.currentDotDiameter
                Path(ellipseIn: CGRect(
                    x: center.x - diameter / 2,
                    y: center.y - diameter / 2,
                    width: diameter,
                    height: diameter))
                    .fill(self.color)
            }
        }
    }
}
