import OpenBarCore
import SwiftUI

// Cost card content shared by the inline card body and the standalone cost row (spec §9.2 "Cost").

/// A label on the left and its value on the right ("Today      $4.12 · 1.2M tokens"). Lines that do
/// not have the localized "Label: value" shape show whole on the left.
struct MenuCardValueLine: View {
    let line: String
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        if let split = Self.split(self.line) {
            HStack(alignment: .firstTextBaseline, spacing: OpenBarSpacing.regular) {
                Text(split.label)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: OpenBarSpacing.regular)
                Text(split.value)
                    .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .font(OpenBarTheme.Fonts.meta)
        } else {
            Text(self.line)
                .font(OpenBarTheme.Fonts.meta)
                .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                .lineLimit(1)
        }
    }

    /// Splits at the first label colon (ASCII or full-width), as every localized cost format writes it.
    static func split(_ line: String) -> (label: String, value: String)? {
        guard let colon = line.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return nil }
        let label = line[..<colon].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, !value.isEmpty, label.count <= 40 else { return nil }
        return (label, value)
    }
}

/// Shared token-cost card (title, Today / window / metered / comparison lines, hint, error), used
/// by the inline card body; the standalone cost row renders the same lines.
struct TokenUsageSectionContent: View {
    let provider: UsageProvider
    let tokenUsage: UsageMenuCardView.Model.TokenUsageSection
    let showsCodexHint: Bool
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: OpenBarSpacing.tight) {
            HStack(alignment: .firstTextBaseline, spacing: OpenBarSpacing.compact) {
                Text(UsageMenuCardView.Model.tokenUsageHeader(provider: self.provider))
                    .font(OpenBarTheme.Fonts.laneTitle)
                    .lineLimit(1)
                Spacer(minLength: OpenBarSpacing.regular)
                if self.tokenUsage.isRefreshing {
                    // Static status instead of a spinner: nothing animates inside the menu (spec §7).
                    Text("\(L("Refreshing"))…")
                        .font(OpenBarTheme.Fonts.meta)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                }
                MenuCardSubmenuChevron()
            }
            .padding(.bottom, OpenBarSpacing.hairline)
            MenuCardValueLine(line: self.tokenUsage.sessionLine)
            MenuCardValueLine(line: self.tokenUsage.monthLine)
            if let metered = self.tokenUsage.meteredLine, !metered.isEmpty {
                MenuCardValueLine(line: metered)
            }
            ForEach(self.tokenUsage.comparisonLines, id: \.self) { line in
                MenuCardValueLine(line: line)
            }
            if self.provider != .codex || self.showsCodexHint,
               let hint = self.tokenUsage.hintLine,
               !hint.isEmpty
            {
                Text(hint)
                    .font(OpenBarTheme.Fonts.meta)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = self.tokenUsage.errorLine, !error.isEmpty {
                Text(error)
                    .font(OpenBarTheme.Fonts.meta)
                    .foregroundStyle(MenuHighlightStyle.error(self.isHighlighted))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .overlay {
                        ClickToCopyOverlay(copyText: self.tokenUsage.errorCopyText ?? error)
                    }
            }
        }
    }
}
