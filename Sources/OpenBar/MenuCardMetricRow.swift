import OpenBarCore
import SwiftUI

/// One quota lane (spec §9.2 "Lanes"): title and value, the meter, then the reset text with the
/// pace forecast. Live text updates draw over the geometry measured from `layoutMetric`, so an open
/// menu never changes height.
struct MetricRow: View {
    let metric: UsageMenuCardView.Model.Metric
    let layoutMetric: UsageMenuCardView.Model.Metric
    let title: String
    let progressColor: Color
    var compact = false
    /// Provider name spoken before the lane title, so VoiceOver users hear which card a lane is in.
    var accessibilityProviderName: String?
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: OpenBarMenuStyle.laneInnerSpacing) {
            if let statusText = self.metric.statusText {
                Text(self.title)
                    .font(OpenBarTheme.Fonts.laneTitle)
                    .lineLimit(1)
                Text(statusText)
                    .font(OpenBarTheme.Fonts.meta)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
            } else {
                self.titleRow
                UsageProgressBar(
                    percent: self.metric.percent,
                    tint: self.progressColor,
                    accessibilityLabel: self.metric.percentStyle.accessibilityLabel,
                    pacePercent: self.metric.pacePercent,
                    paceOnTop: self.metric.paceOnTop,
                    warningMarkerPercents: self.metric.warningMarkerPercents,
                    workdayMarkerPercents: self.metric.workdayMarkerPercents,
                    workdayTickAppearance: self.metric.workdayTickAppearance)
                if !self.compact {
                    self.detailLines
                }
            }
        }
        .help(self.metric.helpText ?? "")
        // One read-only element per lane (spec §10): its description already speaks the percent, tone,
        // reset, pace, and markers, so the meter shapes and tone symbols are not separate elements.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.accessibilityDescription)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(self.metric.cardStyle ? OpenBarMenuStyle.cardPaddingVertical : 0)
        .background {
            if self.metric.cardStyle {
                RoundedRectangle(cornerRadius: OpenBarRadius.control, style: .continuous)
                    .fill(self.isHighlighted
                        ? MenuHighlightStyle.selectionText.opacity(0.2)
                        : OpenBarTheme.Colors.cardFill)
            }
        }
    }

    // MARK: Accessibility

    private var accessibilityDescription: String {
        let presentation = self.metric.lanePresentation
        var parts = [self.accessibilityProviderName, self.title].compactMap(\.self)
        if let statusText = self.metric.statusText {
            parts.append(statusText)
            return parts.joined(separator: ", ")
        }
        parts.append(self.metric.percentLabel)
        switch self.metric.quotaTone {
        case .warning: parts.append(L("quota_warning_warning"))
        case .critical: parts.append(L("quota_warning_critical"))
        case .normal, .stale: break
        }
        if !self.compact {
            parts.append(contentsOf: [
                presentation.resetText,
                presentation.pace?.text,
                presentation.estimateText,
                self.metric.detailText,
                self.metric.dailyTargetText,
            ].compactMap(\.self))
        }
        if let markers = UsageProgressBar.markerAccessibilityText(
            warningPercents: self.metric.warningMarkerPercents,
            workdayPercents: self.metric.workdayMarkerPercents,
            workdayAppearance: self.metric.workdayTickAppearance)
        {
            parts.append(markers)
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    // MARK: Title and value

    private var titleRow: some View {
        let tone = self.metric.quotaTone
        let toneColor = tone.menuColor(highlighted: self.isHighlighted)
        return HStack(alignment: .firstTextBaseline, spacing: OpenBarSpacing.regular) {
            Text(self.title)
                .font(OpenBarTheme.Fonts.laneTitle)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: OpenBarSpacing.regular)
            HStack(alignment: .firstTextBaseline, spacing: OpenBarSpacing.tight) {
                if let toneColor, let symbolName = tone.symbolName {
                    MenuToneSymbol(systemName: symbolName, color: toneColor, size: 11)
                }
                Text(self.metric.percentLabel)
                    .font(OpenBarTheme.Fonts.laneValueEmphasis)
                    .foregroundStyle(toneColor ?? MenuHighlightStyle.primary(self.isHighlighted))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
        }
    }

    // MARK: Detail lines

    @ViewBuilder
    private var detailLines: some View {
        let live = self.metric.lanePresentation
        let layout = self.layoutMetric.lanePresentation
        if layout.resetText != nil || layout.pace != nil {
            MetricDetailRow(live: live, layout: layout, isHighlighted: self.isHighlighted)
        }
        if let layoutEstimate = layout.estimateText {
            self.layoutPreservingText(live.estimateText, layoutText: layoutEstimate, lineLimit: 2)
        }
        if let layoutDetailText = self.layoutMetric.detailText {
            self.layoutPreservingText(self.metric.detailText, layoutText: layoutDetailText, lineLimit: 1)
        }
        if let layoutTarget = self.layoutMetric.dailyTargetText {
            self.layoutPreservingText(self.metric.dailyTargetText, layoutText: layoutTarget, lineLimit: 2)
        }
    }

    private func layoutPreservingText(
        _ text: String?,
        layoutText: String,
        lineLimit: Int) -> some View
    {
        Text(layoutText)
            .font(OpenBarTheme.Fonts.meta)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            // Freeze the measured height, but let updates use the entire metric row width.
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) {
                if let text, !text.isEmpty {
                    Text(text)
                        .font(OpenBarTheme.Fonts.meta)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(lineLimit)
                        .truncationMode(.tail)
                }
            }
            .clipped()
    }
}

/// Reset text, then the pace forecast on its own line. Each line has the full lane width and wraps
/// to a second line before truncating (spec §10, "Text size"). Live text draws over the geometry
/// measured from the layout presentation, so an open menu keeps its height.
private struct MetricDetailRow: View {
    let live: UsageMenuCardView.Model.Metric.LanePresentation
    let layout: UsageMenuCardView.Model.Metric.LanePresentation
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: OpenBarSpacing.hairline) {
            if let layoutReset = self.layout.resetText {
                self.reserved(self.resetLabel(layoutReset)) {
                    self.resetLabel(self.live.resetText ?? layoutReset)
                }
            }
            if let layoutPace = self.layout.pace {
                self.reserved(self.paceLabel(layoutPace)) {
                    if let pace = self.live.pace {
                        self.paceLabel(pace)
                    }
                }
            }
        }
    }

    /// Measures `layout`, then draws `content` over that space.
    private func reserved(
        _ layout: some View,
        @ViewBuilder content: () -> some View) -> some View
    {
        layout
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) {
                content()
            }
            .clipped()
    }

    private func resetLabel(_ text: String) -> some View {
        Text(text)
            .font(OpenBarTheme.Fonts.meta)
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            .lineLimit(2)
            .truncationMode(.tail)
    }

    /// A pace that runs out before the reset takes primary ink, a medium weight, and the warning
    /// triangle, so the most actionable line in the lane is not the faintest one.
    private func paceLabel(_ pace: UsageMenuCardView.Model.Metric.LanePresentation.Pace) -> some View {
        let isWarning = pace.tone == .runsOut
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            if let tone = pace.tone {
                MenuToneSymbol(systemName: tone.symbolName, color: tone.color(highlighted: self.isHighlighted))
            }
            Text(pace.text)
                .font(isWarning ? OpenBarTheme.Fonts.metaEmphasis : OpenBarTheme.Fonts.meta)
                .foregroundStyle(isWarning
                    ? MenuHighlightStyle.primary(self.isHighlighted)
                    : MenuHighlightStyle.secondary(self.isHighlighted))
                .lineLimit(2)
                .truncationMode(.tail)
        }
    }
}

extension UsageMenuCardView.Model.Metric {
    /// Text the lane's detail rows show, split the way the Calm native lane anatomy lays it out.
    struct LanePresentation: Equatable {
        struct Pace: Equatable {
            let text: String
            let tone: MenuPaceTone?
        }

        let resetText: String?
        let pace: Pace?
        /// Session-equivalent estimate ("Estimated: 3 session quotas left · …").
        let estimateText: String?
    }

    var lanePresentation: LanePresentation {
        let paceParts = [self.detailLeftText, self.detailRightText].compactMap(Self.nonEmpty)
        let estimateParts = [
            self.sessionEquivalentDetail?.leftText,
            self.sessionEquivalentDetail?.rightText,
        ].compactMap(Self.nonEmpty)
        let paceTone: MenuPaceTone? = self.paceWillLastToReset.map { $0 ? .lastsToReset : .runsOut }
        return LanePresentation(
            resetText: Self.nonEmpty(self.resetText),
            pace: paceParts.isEmpty ? nil : .init(text: paceParts.joined(separator: " · "), tone: paceTone),
            estimateText: estimateParts.isEmpty ? nil : estimateParts.joined(separator: " · "))
    }

    /// Status tone of the lane's value. Always derived from the remaining share, whatever the
    /// used/remaining display setting (spec §2.2).
    var quotaTone: OpenBarQuotaTone {
        guard self.statusText == nil, self.percent.isFinite else { return .normal }
        let remaining = self.percentStyle == .left ? self.percent : 100 - self.percent
        return OpenBarQuotaTone.resolve(remainingPercent: remaining, isStale: false)
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
