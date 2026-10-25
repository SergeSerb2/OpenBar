import AppKit
import OpenBarCore
import SwiftUI
import WidgetKit

// MARK: - Entry View

struct BurnDownWidgetView: View {
    @Environment(\.widgetFixedNow) private var fixedNow
    let entry: BurnDownEntry

    var body: some View {
        let state = BurnDownState(
            snapshot: self.entry.snapshot,
            provider: self.entry.provider,
            selection: self.entry.window,
            now: self.fixedNow ?? Date())

        Group {
            if let state, let window = state.selectedWindow {
                BurnDownLayout(
                    window: window,
                    title: state.selectedTitle,
                    provider: self.entry.provider,
                    blankChart: state.blankPrimaryChart,
                    resetsAtOverride: state.selectedResetOverride)
            } else {
                BurnDownEmptyState()
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct BurnDownEmptyState: View {
    var body: some View {
        VStack(spacing: 4) {
            Text(W("Open OpenBar"))
                .font(WidgetTheme.Fonts.cardTitle)
            Text(W("No data"))
                .font(WidgetTheme.Fonts.meta)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(12)
    }
}

// MARK: - Main Layout

private struct BurnDownLayout: View {
    @Environment(\.widgetPalette) private var palette
    @Environment(\.widgetFixedNow) private var fixedNow

    let window: RateWindow
    let title: String
    let provider: UsageProvider
    /// True when the session window is blocked because the weekly budget is exhausted:
    /// suppress the chart and retarget "Resets in" to the weekly reset.
    var blankChart = false
    /// When set, "Resets in" counts down to this date (the weekly reset) instead of the
    /// session window's own reset.
    var resetsAtOverride: Date?

    var body: some View {
        let now = self.fixedNow ?? Date()
        let geom = BurnGeom(window: self.window, now: now)
        let theme = BurnTheme(provider: self.provider, geom: geom, palette: self.palette)
        let windowMins = self.window.windowMinutes ?? 300
        let isDailyWindow = windowMins >= 1440
        let estimatedResetMinutes = self.blankChart || geom.tNow >= 1
            ? nil
            : (1 - geom.tNow) * Double(windowMins)
        let explicitReset = self.blankChart
            ? self.resetsAtOverride
            : self.resetsAtOverride ?? self.window.resetsAt
        let effectiveResetAt = burnEffectiveResetDate(
            explicitResetAt: explicitReset,
            estimatedResetMinutes: estimatedResetMinutes,
            now: now)
        let resetsIn = effectiveResetAt.map { max(0, $0.timeIntervalSince(now) / 60) } ?? 0
        let outInMins = geom.slope < -0.01 ? (geom.vNow / -geom.slope) * Double(windowMins) : Double.infinity
        // Very early in the window a single sample can't forecast a credible run-out: a
        // tiny burst right after reset extrapolates to "runs dry in minutes" even at ~99%
        // remaining. Match the design's fresh-window behaviour ("Runs out: after reset")
        // and only surface the estimate once enough of the window has elapsed to trust the
        // average burn rate.
        let windowEstablished = geom.tNow >= 0.08
        let runsDryBefore = geom.runsOut && outInMins < resetsIn && windowEstablished

        let sign = geom.margin >= 0 ? "+" : "−"
        let badgeNum = "\(sign)\(abs(Int(geom.margin.rounded())))%"
        // Per the design's edge states, "fresh" and "spent" show only the glyph + word
        // (◆ full / ■ spent) with no pace number — the margin is meaningless once the
        // budget is full or gone.
        let showBadgeNumber = !geom.depleted && !geom.fresh
        let statusWord: String = geom.depleted ? W("spent") : geom.fresh ? W("full")
            : geom.status == .ahead ? W("conserving") : geom.status == .behind ? W("over pace") : W("on pace")
        let arrow: String = geom.depleted ? "■" : geom.fresh ? "◆"
            : geom.status == .ahead ? "▲" : geom.status == .behind ? "▼" : "●"

        let axisDates = burnAxisDateRange(
            effectiveResetAt: effectiveResetAt,
            windowMinutes: windowMins,
            now: now)
        let startLabel = burnAxisLabel(axisDates.start, isDailyWindow: isDailyWindow)
        let resetLabel = burnAxisLabel(axisDates.reset, isDailyWindow: isDailyWindow)

        VStack(spacing: 0) {
            // Header: brand + pace badge
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(theme.brandDot)
                            .frame(width: 7, height: 7)
                        Text(burnProviderName(self.provider))
                            .font(WidgetTheme.Fonts.cardTitle)
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                    }
                    Text("\(self.title) · \(burnWindowLabel(self.window.windowMinutes))")
                        .font(WidgetTheme.Fonts.meta)
                        .foregroundStyle(theme.sub)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    if showBadgeNumber {
                        Text(badgeNum)
                            .font(WidgetTheme.Fonts.laneValue)
                            .foregroundStyle(theme.statusColor)
                    }
                    HStack(spacing: 3) {
                        Text(arrow)
                            .font(.system(size: 8))
                            .foregroundStyle(theme.statusColor)
                        Text(statusWord)
                            .font(WidgetTheme.Fonts.meta)
                            .foregroundStyle(theme.sub)
                    }
                }
            }

            // Body: stats + hero / chart
            HStack(alignment: .bottom, spacing: 13) {
                // Left: stats + hero %
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 5) {
                        BurnResetStatRow(resetAt: effectiveResetAt, theme: theme)
                        BurnStatRow(
                            label: geom.depleted ? W("Ran out") : runsDryBefore ? W("Runs out in") : W("Runs out"),
                            value: geom
                                .depleted ? W("budget spent") : runsDryBefore ? "~\(burnFmtDuration(outInMins))" :
                                W("after reset"),
                            theme: theme,
                            tone: geom.depleted ? .critical : runsDryBefore ? .warning : .normal)
                    }
                    .padding(.top, 8)

                    Spacer(minLength: 4)

                    HStack(alignment: .lastTextBaseline, spacing: 5) {
                        Text("\(Int(geom.vNow.rounded()))")
                            .font(WidgetTheme.Fonts.hero(size: 41))
                            .foregroundStyle(geom.depleted ? theme.danger : theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text("%")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(theme.sub)
                        Text(W("left"))
                            .font(WidgetTheme.Fonts.meta)
                            .foregroundStyle(theme.sub)
                    }
                }
                .frame(width: 143, alignment: .leading)

                // Right: chart + axis. Blanked when the session window is blocked by the
                // weekly cap — there's no session burn to chart until the weekly resets.
                VStack(spacing: 2) {
                    if self.blankChart {
                        Color.clear.frame(height: 84)
                        Color.clear.frame(height: 13)
                    } else {
                        BurnChart(geom: geom, theme: theme)
                            .frame(height: 84)

                        BurnAxisRow(
                            startLabel: startLabel,
                            resetLabel: resetLabel,
                            tNow: geom.tNow,
                            theme: theme)
                            .frame(height: 13)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 15)
        .padding(.top, 13)
        .padding(.bottom, 12)
    }
}

// MARK: - Stat Row

private struct BurnStatRow: View {
    let label: String
    let value: String
    let theme: BurnTheme
    let tone: OpenBarQuotaTone

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(W(self.label))
                .font(WidgetTheme.Fonts.meta)
                .foregroundStyle(self.theme.sub)
            Spacer()
            Text(self.value)
                .font(WidgetTheme.Fonts.laneValue)
                .foregroundStyle(self.theme.text(self.tone))
                .lineLimit(1)
        }
    }
}

private struct BurnResetStatRow: View {
    @Environment(\.widgetFixedNow) private var fixedNow
    let resetAt: Date?
    let theme: BurnTheme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(W("Resets in"))
                .font(WidgetTheme.Fonts.meta)
                .foregroundStyle(self.theme.sub)
            Spacer()
            Group {
                if let resetAt {
                    WidgetDateText.offset(resetAt, now: self.fixedNow)
                } else {
                    Text("—")
                }
            }
            .font(WidgetTheme.Fonts.laneValue)
            .foregroundStyle(self.theme.text)
            .lineLimit(1)
        }
    }
}

// MARK: - Axis Row

private struct BurnAxisRow: View {
    let startLabel: String
    let resetLabel: String
    let tNow: Double
    let theme: BurnTheme

    var body: some View {
        GeometryReader { geo in
            // Hide "now" when it would collide with the start/reset labels. The edge labels
            // are anchored to the ends, so estimate their widths (≈9.5pt monospaced digits)
            // and only show "now" when it clears both with a small gap — otherwise the
            // now-dot on the chart already conveys position. Matches the design's rule that
            // "now" hides near an end label.
            let w = geo.size.width
            let approxChar: CGFloat = 5.8
            let nowX = self.tNow * w
            let nowHalf: CGFloat = 13
            let gap: CGFloat = 6
            let clearsStart = nowX - nowHalf > CGFloat(self.startLabel.count) * approxChar + gap
            let clearsReset = nowX + nowHalf < w - CGFloat(self.resetLabel.count) * approxChar - gap
            let showNow = self.tNow > 0.05 && self.tNow < 0.95 && clearsStart && clearsReset

            ZStack(alignment: .leading) {
                Text(self.startLabel)
                    .font(WidgetTheme.Fonts.caption)
                    .foregroundStyle(self.theme.sub)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showNow {
                    Text(W("now"))
                        .font(WidgetTheme.Fonts.caption.weight(.semibold))
                        .foregroundStyle(self.theme.text)
                        .position(x: nowX, y: geo.size.height / 2)
                }

                Text(self.resetLabel)
                    .font(WidgetTheme.Fonts.caption)
                    .foregroundStyle(self.theme.sub)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

// MARK: - Chart

/// Burn-down chart in plain shapes (docs/design/README.md, 8): the "now" rule and baseline, the ideal
/// steady burn (dashed), the recorded burn (solid) over a flat used-area tint, the projection
/// (dotted), and the "now" point. Combined rows draw per-period usage bars behind the lines.
struct BurnChart: View {
    let geom: BurnGeom
    let theme: BurnTheme
    var periods: Int?

    var body: some View {
        let plot = BurnPlot(periods: self.periods)
        let now = BurnPoint(t: self.geom.tNow, v: self.geom.vNow)
        ZStack {
            if let periods = self.periods {
                ForEach(BurnBarsShape.Kind.allCases, id: \.self) { kind in
                    BurnBarsShape(geom: self.geom, periods: periods, plot: plot, kind: kind)
                        .fill(self.theme.barColor.opacity(kind.opacity))
                }
            }
            BurnGuidesShape(t: self.geom.tNow, plot: plot)
                .stroke(self.theme.chartGrid, lineWidth: 1)
            if self.periods == nil {
                BurnAreaShape(now: now, plot: plot)
                    .fill(self.theme.chartFill)
            }
            BurnLineShape(from: BurnPoint(t: 0, v: 100), to: BurnPoint(t: 1, v: 0), plot: plot)
                .stroke(self.theme.chartIdeal, style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 3]))
            if self.geom.slope < -0.01 {
                BurnLineShape(from: now, to: BurnPoint(t: self.geom.projT, v: self.geom.projV), plot: plot)
                    .stroke(
                        self.theme.chartProj,
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [0.5, 3.5]))
            }
            BurnLineShape(from: BurnPoint(t: 0, v: 100), to: now, plot: plot)
                .stroke(self.theme.chartLine, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            BurnDotShape(center: now, radius: 3.5, plot: plot)
                .fill(self.theme.chartNowDot)
        }
        .flipsForRightToLeftLayoutDirection(true)
        .accessibilityHidden(true)
    }
}

/// A point in chart space: `t` is the position in the window (0...1), `v` the percent left.
struct BurnPoint: Equatable {
    let t: Double
    let v: Double
}

/// Maps chart space into a shape's rectangle, with the insets the "now" point needs.
struct BurnPlot: Equatable {
    let top: CGFloat
    let bottom: CGFloat = 2
    let leading: CGFloat = 1
    let trailing: CGFloat = 1

    init(periods: Int?) {
        self.top = periods == nil ? 8 : 5
    }

    func point(_ point: BurnPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + self.leading + CGFloat(point.t) * (rect.width - self.leading - self.trailing),
            y: rect.minY + self.top + CGFloat(1 - point.v / 100) * (rect.height - self.top - self.bottom))
    }
}

struct BurnLineShape: Shape {
    let from: BurnPoint
    let to: BurnPoint
    let plot: BurnPlot

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: self.plot.point(self.from, in: rect))
        path.addLine(to: self.plot.point(self.to, in: rect))
        return path
    }
}

/// The "now" rule and the baseline, stroked together.
struct BurnGuidesShape: Shape {
    let t: Double
    let plot: BurnPlot

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: self.plot.point(BurnPoint(t: self.t, v: 100), in: rect))
        path.addLine(to: self.plot.point(BurnPoint(t: self.t, v: 0), in: rect))
        path.move(to: self.plot.point(BurnPoint(t: 0, v: 0), in: rect))
        path.addLine(to: self.plot.point(BurnPoint(t: 1, v: 0), in: rect))
        return path
    }
}

/// The used area under the recorded burn, filled flat (no gradient).
struct BurnAreaShape: Shape {
    let now: BurnPoint
    let plot: BurnPlot

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: self.plot.point(BurnPoint(t: 0, v: 100), in: rect))
        path.addLine(to: self.plot.point(self.now, in: rect))
        path.addLine(to: self.plot.point(BurnPoint(t: self.now.t, v: 0), in: rect))
        path.addLine(to: self.plot.point(BurnPoint(t: 0, v: 0), in: rect))
        path.closeSubpath()
        return path
    }
}

struct BurnDotShape: Shape {
    let center: BurnPoint
    let radius: CGFloat
    let plot: BurnPlot

    func path(in rect: CGRect) -> Path {
        let center = self.plot.point(self.center, in: rect)
        return Path(ellipseIn: CGRect(
            x: center.x - self.radius,
            y: center.y - self.radius,
            width: self.radius * 2,
            height: self.radius * 2))
    }
}

/// Per-period usage bars behind a combined row's lines, one batched path per kind. Heights are
/// relative to the ideal pace: one period's ideal share maps to 46 % of the plot height.
struct BurnBarsShape: Shape {
    enum Kind: CaseIterable {
        case completedBase
        case completedOverage
        case partialBase
        case partialOverage
        case future

        var opacity: Double {
            switch self {
            case .completedBase: 0.17
            case .completedOverage: 0.34
            case .partialBase: 0.13
            case .partialOverage: 0.26
            case .future: 0.045
            }
        }
    }

    let geom: BurnGeom
    let periods: Int
    let plot: BurnPlot
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard self.periods > 0 else { return path }
        let width = rect.width - self.plot.leading - self.plot.trailing
        let plotHeight = rect.height - self.plot.top - self.plot.bottom
        let baseline = rect.maxY - self.plot.bottom
        let referenceHeight = 0.46 * plotHeight
        let idealPerPeriod = 100.0 / Double(self.periods)
        let tNow = self.geom.tNow
        let burnRate = tNow > 0.001 ? (100.0 - self.geom.vNow) / tNow : 0.0
        let slotWidth = width / CGFloat(self.periods)

        for index in 0..<self.periods {
            let slotStart = Double(index) / Double(self.periods)
            let slotEnd = Double(index + 1) / Double(self.periods)
            let slotX = rect.minX + self.plot.leading + CGFloat(slotStart) * width
            if slotEnd <= tNow {
                let total = CGFloat(burnRate * (slotEnd - slotStart) / idealPerPeriod) * referenceHeight
                self.addBar(
                    to: &path,
                    x: slotX,
                    width: slotWidth - 1,
                    total: total,
                    reference: referenceHeight,
                    baseline: baseline,
                    base: .completedBase,
                    overage: .completedOverage)
            } else if slotStart < tNow {
                let partial = (tNow - slotStart) / (slotEnd - slotStart)
                let total = CGFloat(burnRate * (tNow - slotStart) / idealPerPeriod) * referenceHeight
                self.addBar(
                    to: &path,
                    x: slotX,
                    width: CGFloat(partial) * (slotWidth - 1),
                    total: total,
                    reference: referenceHeight,
                    baseline: baseline,
                    base: .partialBase,
                    overage: .partialOverage)
            } else if self.kind == .future {
                path.addRect(CGRect(
                    x: slotX,
                    y: baseline - referenceHeight,
                    width: slotWidth - 1,
                    height: referenceHeight))
            }
        }
        return path
    }

    // swiftlint:disable:next function_parameter_count
    private func addBar(
        to path: inout Path,
        x: CGFloat,
        width: CGFloat,
        total: CGFloat,
        reference: CGFloat,
        baseline: CGFloat,
        base: Kind,
        overage: Kind)
    {
        if self.kind == base {
            let height = min(total, reference)
            if height > 0 {
                path.addRect(CGRect(x: x, y: baseline - height, width: width, height: height))
            }
        } else if self.kind == overage, total > reference {
            path.addRect(CGRect(x: x, y: baseline - total, width: width, height: total - reference))
        }
    }
}

// MARK: - Theme

/// Burn-down colors. Status follows the shared tones: on pace or conserving is `ok`, over pace is
/// `warning`, a spent budget is `critical`. Outside full color everything is the tint at varying
/// strength, so the glyphs (▲ ▼ ● ■ ◆) and words carry the status.
struct BurnTheme {
    let text: Color
    let sub: Color
    let hair: Color
    let statusColor: Color
    let warning: Color
    let danger: Color
    let brandDot: Color
    let chartLine: Color
    let chartFill: Color
    let chartIdeal: Color
    let chartProj: Color
    let chartGrid: Color
    let chartNowDot: Color
    let barColor: Color

    init(provider: UsageProvider, geom: BurnGeom, palette: WidgetPalette) {
        self.text = .primary
        self.sub = .secondary
        self.hair = palette.separator
        self.chartGrid = Color.primary.opacity(palette.contrast == .increased ? 0.3 : 0.1)
        self.chartIdeal = .secondary
        self.barColor = .primary
        guard palette.isFullColor else {
            self.statusColor = .primary
            self.warning = .primary
            self.danger = .primary
            self.brandDot = Color.primary.opacity(0.7)
            self.chartLine = .primary
            self.chartFill = Color.primary.opacity(0.12)
            self.chartProj = Color.primary.opacity(0.55)
            self.chartNowDot = .primary
            return
        }
        let ok = palette.color(OpenBarPalette.ok)
        let warning = palette.color(OpenBarPalette.warning)
        let status = geom.status == .behind ? warning : ok
        self.statusColor = status
        self.warning = warning
        self.danger = palette.color(OpenBarPalette.critical)
        self.brandDot = Self.brandDotColor(provider)
        self.chartLine = status
        self.chartFill = status.opacity(0.12)
        self.chartProj = status
        self.chartNowDot = status
    }

    func text(_ tone: OpenBarQuotaTone) -> Color {
        switch tone {
        case .critical: self.danger
        case .warning: self.warning
        case .normal, .stale: self.text
        }
    }

    private static func brandDotColor(_ provider: UsageProvider) -> Color {
        let color = ProviderDescriptorRegistry.descriptor(for: provider).branding.burnDownWidgetColor
        return Color(red: color.red, green: color.green, blue: color.blue)
    }
}

// MARK: - Geometry

struct BurnGeom {
    enum Status { case ahead, onpace, behind }

    let vNow: Double // % remaining (0..100)
    let tNow: Double // position in window (0..1)
    let idealNow: Double // what you should have left = 100 * (1 - tNow)
    let margin: Double // vNow - idealNow; + = conserving, − = over pace
    let slope: Double // %/unit-t (negative = burning)
    let projT: Double // t where projection ends
    let projV: Double // v where projection ends
    let runsOut: Bool // projection hits 0 inside the window

    var status: Status {
        self.margin > 4 ? .ahead : self.margin < -4 ? .behind : .onpace
    }

    var depleted: Bool {
        self.vNow <= 0.5
    }

    var fresh: Bool {
        self.vNow >= 99.5
    }

    init(window: RateWindow, now: Date = Date()) {
        let remaining = max(0, min(100, window.remainingPercent))
        self.vNow = remaining

        let t: Double
        if let resetsAt = window.resetsAt, let windowMins = window.windowMinutes, windowMins > 0 {
            let minutesUntilReset = max(0, resetsAt.timeIntervalSince(now) / 60)
            let minutesElapsed = Double(windowMins) - minutesUntilReset
            t = max(0.001, min(0.999, minutesElapsed / Double(windowMins)))
        } else {
            t = max(0.001, min(0.999, window.usedPercent / 100.0))
        }
        self.tNow = t
        self.idealNow = 100.0 * (1.0 - t)
        self.margin = remaining - self.idealNow

        let slope = t > 0.001 ? (remaining - 100.0) / t : -remaining
        self.slope = slope

        if slope < -0.01 {
            let tOut = t + remaining / -slope
            if tOut <= 1.0 {
                self.projT = tOut
                self.projV = 0
                self.runsOut = true
            } else {
                self.projT = 1.0
                self.projV = max(0, remaining + slope * (1.0 - t))
                self.runsOut = false
            }
        } else {
            self.projT = 1.0
            self.projV = remaining
            self.runsOut = false
        }
    }
}

// MARK: - Helpers

func burnWindowLabel(_ windowMinutes: Int?) -> String {
    guard let mins = windowMinutes else { return W("Usage limit") }
    if mins < 60 {
        return W("%@-minute limit", String(describing: mins))
    }
    if mins % 1440 == 0 { return W("%@-day limit", String(describing: mins / 1440)) }
    if mins % 60 == 0 { return W("%@-hour limit", String(describing: mins / 60)) }
    return W("%@-minute limit", String(describing: mins))
}

func burnEffectiveResetDate(
    explicitResetAt: Date?,
    estimatedResetMinutes: Double?,
    now: Date) -> Date?
{
    if let explicitResetAt {
        return explicitResetAt > now ? explicitResetAt : nil
    }
    guard let estimatedResetMinutes, estimatedResetMinutes > 0 else { return nil }
    return now.addingTimeInterval(estimatedResetMinutes * 60)
}

func burnAxisDateRange(
    effectiveResetAt: Date?,
    windowMinutes: Int,
    now: Date) -> (start: Date, reset: Date)
{
    let reset = effectiveResetAt ?? now
    return (reset.addingTimeInterval(-Double(windowMinutes) * 60), reset)
}

func burnCompactWindowLabel(_ windowMinutes: Int?, fallback: String) -> String {
    guard let minutes = windowMinutes else { return fallback }
    if minutes > 1440, minutes % 1440 == 0 { return W("%@D", String(describing: minutes / 1440)) }
    if minutes % 60 == 0 { return W("%@H", String(describing: minutes / 60)) }
    return W("%@M", String(describing: minutes))
}

func burnFmtDuration(_ minutes: Double) -> String {
    guard minutes.isFinite, minutes > 0 else { return "—" }
    if minutes >= 1440 {
        let d = Int(minutes / 1440)
        let h = Int(minutes / 60) % 24
        return W("%@d %@h", String(describing: d), String(describing: h))
    }
    let h = Int(minutes / 60)
    let m = Int(minutes) % 60
    if h <= 0 {
        return W("%@m", String(describing: max(1, m)))
    }
    return W("%@h %@m", String(describing: h), String(describing: String(format: "%02d", m)))
}

func burnAxisLabel(_ date: Date, isDailyWindow: Bool) -> String {
    let f = DateFormatter()
    if isDailyWindow {
        // A rolling multi-day window's start and reset fall on the same weekday, so "EEE"
        // would print the same label at both ends ("Sat … Sat"). Use a numeric date so the
        // two ends are distinguishable.
        f.setLocalizedDateFormatFromTemplate("Md")
    } else {
        f.dateStyle = .none
        f.timeStyle = .short
    }
    return f.string(from: date)
}

func burnProviderName(_ provider: UsageProvider) -> String {
    ProviderDefaults.metadata[provider]?.displayName ?? provider.rawValue.capitalized
}
