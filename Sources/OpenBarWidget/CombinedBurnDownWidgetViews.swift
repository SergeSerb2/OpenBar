import AppKit
import OpenBarCore
import SwiftUI
import WidgetKit

// MARK: - Entry View

struct CombinedBurnDownWidgetView: View {
    @Environment(\.widgetFixedNow) private var fixedNow
    let entry: CombinedBurnDownEntry

    var body: some View {
        let state = BurnDownState(
            snapshot: self.entry.snapshot,
            provider: self.entry.provider,
            selection: .session,
            now: self.fixedNow ?? Date())

        Group {
            if let state {
                CombinedBurnDownLayout(state: state, provider: self.entry.provider)
            } else {
                BurnDownEmptyState()
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Layout

private struct CombinedBurnDownLayout: View {
    @Environment(\.widgetPalette) private var palette
    @Environment(\.widgetFixedNow) private var fixedNow

    let state: BurnDownState
    let provider: UsageProvider

    var body: some View {
        let now = self.fixedNow ?? Date()
        let selections = self.state.combinedSelections
        let sessionWindow = self.state.window(for: selections[0])
        let weeklyWindow = self.state.window(for: selections[1])

        let sessionGeom = sessionWindow.map { BurnGeom(window: $0, now: now) }
        let weeklyGeom = weeklyWindow.map { BurnGeom(window: $0, now: now) }

        // Use a neutral baseline theme for the header/hairline colors
        let baseGeom = sessionGeom ?? weeklyGeom ?? BurnGeom(
            window: RateWindow(
                usedPercent: 50,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(2.5 * 3600),
                resetDescription: nil),
            now: now)
        let baseTheme = BurnTheme(provider: self.provider, geom: baseGeom, palette: self.palette)

        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(baseTheme.brandDot)
                        .frame(width: 7, height: 7)
                    Text(burnProviderName(self.provider))
                        .font(WidgetTheme.Fonts.cardTitle)
                        .foregroundStyle(baseTheme.text)
                        .lineLimit(1)
                }
                Spacer()
                Text(selections.map { self.state.title(for: $0) }.joined(separator: " & "))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .font(WidgetTheme.Fonts.caption)
                    .foregroundStyle(baseTheme.sub)
            }

            // Two rows
            VStack(spacing: 0) {
                ForEach(Array(selections.enumerated()), id: \.element) { index, selection in
                    if index > 0 {
                        Rectangle().fill(baseTheme.hair).frame(height: 1)
                    }
                    let title = self.state.title(for: selection)
                    if let window = self.state.window(for: selection) {
                        let geom = BurnGeom(window: window, now: now)
                        CombinedBurnRow(
                            window: window,
                            geom: geom,
                            theme: BurnTheme(provider: self.provider, geom: geom, palette: self.palette),
                            tag: title + " · " + burnCompactWindowLabel(window.windowMinutes, fallback: ""),
                            periods: window.windowMinutes == 300 ? 5 : 7,
                            metric: index == 0 ? .remaining : .pace,
                            blankChart: self.state.blanksChart(for: selection),
                            resetsAtOverride: self.state.blanksChart(for: selection)
                                ? self.state.secondaryWindow?.resetsAt : nil)
                    } else {
                        CombinedEmptyRow(tag: title, theme: baseTheme)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.top, 6)
        }
        .padding(.horizontal, 15)
        .padding(.top, 12)
        .padding(.bottom, 11)
    }
}

// MARK: - Metric

private enum CombinedMetric {
    case remaining // % left (default for 5H)
    case pace // % off ideal pace (default for 7D)
    case used // % consumed
}

// MARK: - Row

private struct CombinedBurnRow: View {
    @Environment(\.widgetFixedNow) private var fixedNow
    let window: RateWindow
    let geom: BurnGeom
    let theme: BurnTheme
    let tag: String
    let periods: Int
    let metric: CombinedMetric
    var blankChart = false
    var resetsAtOverride: Date?

    var body: some View {
        let windowMins = self.window.windowMinutes ?? 300
        let isDailyWindow = windowMins >= 1440

        let heroNum = self.metric == .pace ? abs(Int(self.geom.margin.rounded()))
            : self.metric == .used ? Int((100 - self.geom.vNow).rounded())
            : Int(self.geom.vNow.rounded())
        let suffix = self.metric == .remaining ? W("left") : self.metric == .used ? W("used") : ""
        let prefixArrow = self.metric == .pace

        let paceWord: String = self.geom.depleted ? W("spent") : self.geom.fresh ? W("full")
            : self.geom.status == .ahead ? W("under pace")
            : self.geom.status == .behind ? W("over pace") : W("on pace")
        let arrow: String = self.geom.depleted ? "■" : self.geom.fresh ? "◆"
            : self.geom.status == .ahead ? "▲" : self.geom.status == .behind ? "▼" : "●"

        let explicitReset = self.blankChart
            ? self.resetsAtOverride
            : self.resetsAtOverride ?? self.window.resetsAt
        let now = self.fixedNow ?? Date()
        let estimatedResetMinutes = self.blankChart || self.geom.tNow >= 1
            ? nil
            : (1 - self.geom.tNow) * Double(windowMins)
        let effectiveResetDate = burnEffectiveResetDate(
            explicitResetAt: explicitReset,
            estimatedResetMinutes: estimatedResetMinutes,
            now: now)
        let heroColor = self.geom.depleted ? self.theme.danger : self.theme.statusColor

        HStack(alignment: .center, spacing: 12) {
            // Label column
            VStack(alignment: .leading, spacing: 0) {
                // Line 1: tag + (arrow for non-pace metrics) + pace word
                // For remaining/used: "5H ▼ over pace". For pace: "7D on pace" (arrow is on hero line).
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(self.tag)
                        .font(WidgetTheme.Fonts.caption.weight(.semibold))
                        .foregroundStyle(self.theme.sub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        if !prefixArrow {
                            Text(arrow)
                                .font(.system(size: 8))
                                .foregroundStyle(self.theme.statusColor)
                        }
                        Text(paceWord)
                            .font(WidgetTheme.Fonts.caption.weight(.semibold))
                            .foregroundStyle(self.theme.statusColor)
                    }
                    .lineLimit(1)
                }

                // Line 2: hero number. Pace metric prefixes an arrow glyph.
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    if prefixArrow {
                        Text(arrow)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(heroColor)
                    }
                    Text("\(heroNum)")
                        .font(WidgetTheme.Fonts.hero(size: 27))
                        .foregroundStyle(heroColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("%")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(self.theme.sub)
                    if !suffix.isEmpty {
                        Text(suffix)
                            .font(.system(size: 10))
                            .foregroundStyle(self.theme.sub)
                    }
                }
                .padding(.top, 1)

                // Line 3: reset line — refresh glyph + countdown + compact time
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                        .foregroundStyle(self.theme.sub.opacity(0.85))
                    if let effectiveResetDate {
                        WidgetDateText.offset(effectiveResetDate, now: self.fixedNow)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(self.theme.text)
                            .monospacedDigit()
                        let resetTime = combinedCompactResetTime(
                            effectiveResetDate,
                            isDailyWindow: isDailyWindow,
                            now: now)
                        Text("· \(resetTime)")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(self.theme.text)
                    } else {
                        Text("—")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(self.theme.text)
                    }
                }
                .padding(.top, 2)
                .lineLimit(1)
            }
            .frame(width: 140, alignment: .leading)

            // Chart column — blanked when the session window is blocked by an exhausted
            // weekly cap; there is no session burn to chart until the weekly resets.
            if self.blankChart {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            } else {
                BurnChart(geom: self.geom, theme: self.theme, periods: self.periods)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Empty Row

private struct CombinedEmptyRow: View {
    let tag: String
    let theme: BurnTheme

    var body: some View {
        HStack {
            Text(self.tag)
                .font(WidgetTheme.Fonts.caption.weight(.semibold))
                .foregroundStyle(self.theme.sub)
            Text(W("No data"))
                .font(WidgetTheme.Fonts.caption)
                .foregroundStyle(self.theme.sub)
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Compact reset time helper

/// Formats a reset date compactly: "4:30p", "5p", "Sun 9a".
/// Weekday prefix is added for the 7-day window or when the reset is ≥20h away.
private func combinedCompactResetTime(_ date: Date, isDailyWindow: Bool, now: Date) -> String {
    let includeDay = isDailyWindow || date.timeIntervalSince(now) >= 20 * 3600
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate(includeDay ? "EEEjm" : "jm")
    return formatter.string(from: date)
}
