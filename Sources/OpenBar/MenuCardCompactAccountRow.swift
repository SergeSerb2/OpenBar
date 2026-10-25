import OpenBarCore
import SwiftUI

/// Compact menu row for an inactive account: identity and a mini headroom bar,
/// followed by quota details with their provider-reported reset times.
/// Clicking the row expands it into the full usage card.
struct MenuCardCompactAccountRowView: View {
    struct Model: Equatable {
        let label: String
        let headroomPercent: Double?
        let severity: AccountMenuLayoutPlanner.Severity?
        let detailLines: [String]
        let hasError: Bool
        let showsBestBadge: Bool

        init(
            row: AccountMenuLayoutPlanner.CompactRow,
            resetTimeDisplayStyle: ResetTimeDisplayStyle,
            hidePersonalInfo: Bool = false,
            privacyOrdinal: PersonalInfoRedactor.AccountOrdinal? = nil,
            now: Date = .init())
        {
            self.label = PersonalInfoRedactor.redactAccountLabel(
                row.label,
                isEnabled: hidePersonalInfo,
                ordinal: privacyOrdinal)
            self.headroomPercent = row.headroomPercent
            self.severity = row.severity
            var details = row.windowDetails.map { detail in
                let title = localizedSessionQuotaLabel(detail.label, windowMinutes: detail.window.windowMinutes)
                let percent = UsageFormatter.percentText(
                    detail.window.remainingPercent,
                    suffix: L("usage_percent_suffix_left"))
                let reset: String? = switch detail.resetPresentation {
                case .standard:
                    UsageFormatter.resetLine(for: detail.window, style: resetTimeDisplayStyle, now: now)
                case .hidden:
                    nil
                case .providerDescription:
                    detail.window.resetDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let line = ["\(title) \(percent)", reset].compactMap(\.self).filter { !$0.isEmpty }
                    .joined(separator: " · ")
                return PersonalInfoRedactor.redactEmails(in: line, isEnabled: hidePersonalInfo) ?? line
            }
            if let capturedAt = row.lastKnownUsageCapturedAt {
                details.append(LastKnownUsagePresentation.message(capturedAt: capturedAt, now: now))
            }
            self.detailLines = details
            self.hasError = row.hasError
            self.showsBestBadge = row.isBestCandidate
        }

        var accessibilityText: String {
            var parts = [self.label]
            if let label = self.headroomLabel {
                parts.append(String(format: L("%@ remaining"), label))
            }
            parts.append(contentsOf: self.detailLines)
            if self.hasError {
                parts.append(L("Account unavailable"))
            }
            return parts.joined(separator: ", ")
        }

        var headroomLabel: String? {
            self.headroomPercent.map { "\(Int($0.rounded()))%" }
        }

        var heightFingerprint: String {
            [
                "compactAccount",
                self.label,
                self.headroomLabel ?? "-",
                self.detailLines.joined(separator: "|"),
                self.hasError ? "error" : "ok",
                self.showsBestBadge ? "best" : "plain",
            ].joined(separator: "|")
        }
    }

    static let miniBarWidth: CGFloat = 56
    static let miniBarHeight: CGFloat = 4

    let model: Model
    let progressColor: Color
    let width: CGFloat
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: OpenBarSpacing.hairline) {
            HStack(alignment: .center, spacing: OpenBarSpacing.regular) {
                Text(self.model.label)
                    .font(OpenBarTheme.Fonts.laneTitle)
                    .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if self.model.showsBestBadge {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(MenuHighlightStyle.accent(self.isHighlighted))
                        .accessibilityLabel(L("Most usable account"))
                }
                Spacer(minLength: OpenBarSpacing.section)
                if self.model.hasError, self.model.headroomPercent == nil {
                    MenuToneSymbol(
                        systemName: OpenBarQuotaTone.warning.symbolName ?? "exclamationmark.triangle.fill",
                        color: self.isHighlighted ? MenuHighlightStyle.selectionText : OpenBarTheme.Colors.warning)
                } else if let headroom = self.model.headroomPercent, let label = self.model.headroomLabel {
                    CompactHeadroomMeter(
                        percent: min(100, max(0, headroom)),
                        tint: self.progressColor)
                        .frame(width: Self.miniBarWidth, height: Self.miniBarHeight)
                        .accessibilityHidden(true)
                    self.headroomValue(label)
                }
            }
            ForEach(Array(self.model.detailLines.enumerated()), id: \.offset) { _, detail in
                Text(detail)
                    .font(OpenBarTheme.Fonts.meta)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, UsageMenuCardLayout.horizontalPadding)
        .padding(.vertical, 5)
        .frame(width: self.width, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(self.model.accessibilityText)
    }

    /// Headroom figure with the shared quota tone (warning ≤ 25 %, critical ≤ 10 % remaining).
    private func headroomValue(_ label: String) -> some View {
        let tone = self.model.headroomTone
        let toneColor = tone.menuColor(highlighted: self.isHighlighted)
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            if let toneColor, let symbolName = tone.symbolName {
                MenuToneSymbol(systemName: symbolName, color: toneColor)
            }
            Text(label)
                .font(OpenBarTheme.Fonts.laneValue)
                .foregroundStyle(toneColor ?? MenuHighlightStyle.primary(self.isHighlighted))
                .lineLimit(1)
        }
        .frame(minWidth: 40, alignment: .trailing)
    }
}

extension MenuCardCompactAccountRowView.Model {
    /// Color tone of the headroom figure. Folding and ordering keep `AccountMenuLayoutPlanner`'s own
    /// severity; only the presentation uses the shared menu thresholds.
    var headroomTone: OpenBarQuotaTone {
        OpenBarQuotaTone.resolve(remainingPercent: self.headroomPercent, isStale: false)
    }
}

/// The compact row's 56 × 4 mini meter: the lane meter's split motif at a smaller size.
private struct CompactHeadroomMeter: View {
    let percent: Double
    let tint: Color

    var body: some View {
        UsageProgressBar(
            percent: self.percent,
            tint: self.tint,
            accessibilityLabel: "",
            height: MenuCardCompactAccountRowView.miniBarHeight)
    }
}

/// Summary row standing in for the healthy accounts hidden by the compact
/// multi-account layout; clicking it reveals the individual rows.
struct MenuCardCollapsedAccountsRowView: View {
    let count: Int
    let width: CGFloat
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var title: String {
        String(format: L("%d more accounts ready"), self.count)
    }

    var body: some View {
        HStack(spacing: OpenBarSpacing.regular) {
            MenuToneSymbol(
                systemName: "checkmark.circle.fill",
                color: self.isHighlighted ? MenuHighlightStyle.selectionText : OpenBarTheme.Colors.ok)
            Text(self.title)
                .font(OpenBarTheme.Fonts.meta)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            Spacer(minLength: OpenBarSpacing.section)
            Image(systemName: "chevron.down")
                .font(.system(size: OpenBarMenuStyle.chevronSize, weight: .semibold))
                .foregroundStyle(MenuHighlightStyle.tertiary(self.isHighlighted))
        }
        .padding(.horizontal, UsageMenuCardLayout.horizontalPadding)
        .padding(.vertical, 5)
        .frame(width: self.width, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(self.title)
        .accessibilityHint(L("Shows the hidden accounts"))
    }
}
