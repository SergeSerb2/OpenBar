import AppKit
import OpenBarCore
import SwiftUI

/// Cost as its own card (spec §9.2): title, then "Today / Last 30 days" label-value lines, then any
/// hint or error text.
struct CostMenuCardRowView: View {
    let title: String
    let detailLines: [String]
    let valueLines: Set<String>
    let width: CGFloat
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: OpenBarSpacing.tight) {
            HStack(alignment: .firstTextBaseline, spacing: OpenBarSpacing.regular) {
                Text(self.title)
                    .font(OpenBarTheme.Fonts.laneTitle)
                    .lineLimit(1)
                Spacer(minLength: OpenBarSpacing.regular)
                MenuCardSubmenuChevron()
            }
            .padding(.bottom, OpenBarSpacing.hairline)
            ForEach(self.detailLines.indices, id: \.self) { index in
                let line = self.detailLines[index]
                if self.valueLines.contains(line) {
                    MenuCardValueLine(line: line)
                } else {
                    Text(line)
                        .font(OpenBarTheme.Fonts.meta)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .menuCardChrome()
        .frame(width: self.width, alignment: .leading)
    }
}

extension StatusItemController {
    static var costMenuTitle: String {
        L("Cost")
    }

    static func costMenuTitleForProvider(_ provider: UsageProvider) -> String {
        UsageMenuCardView.Model.tokenUsageHeader(provider: provider)
    }

    func makeCostMenuCardItem(
        model: UsageMenuCardView.Model,
        submenu: NSMenu?,
        width: CGFloat) -> NSMenuItem
    {
        let title = Self.costMenuTitleForProvider(model.provider)
        let tooltipLines = Self.costMenuTooltipLines(provider: model.provider, tokenUsage: model.tokenUsage)
        let visibleDetailLines = Self.costMenuVisibleDetailLines(
            provider: model.provider,
            tokenUsage: model.tokenUsage,
            hasSubmenu: submenu != nil)
        guard visibleDetailLines.isEmpty == false, self.menuCardRenderingEnabledForController else {
            return Self.makeNativeCostMenuCardItem(
                title: title,
                visibleDetailLines: visibleDetailLines,
                tooltipLines: tooltipLines,
                submenu: submenu)
        }

        let item = self.makeMenuCardItem(
            CostMenuCardRowView(
                title: title,
                detailLines: visibleDetailLines,
                valueLines: Self.costMenuValueLines(tokenUsage: model.tokenUsage),
                width: width),
            id: "menuCardCost",
            width: width,
            heightCacheScope: model.provider.rawValue,
            heightCacheFingerprint: "costMenuRow:\(visibleDetailLines.count)",
            submenu: submenu,
            submenuIndicatorAlignment: .trailing,
            submenuIndicatorTopPadding: 0)
        item.title = title
        item.toolTip = tooltipLines.joined(separator: "\n")
        return item
    }

    private static func makeNativeCostMenuCardItem(
        title: String,
        visibleDetailLines: [String],
        tooltipLines: [String],
        submenu: NSMenu?) -> NSMenuItem
    {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.representedObject = "menuCardCost"
        item.submenu = submenu
        // Submenu cost rows already show these details; keep tooltips only for inline rows
        // where they reveal truncated text and avoid flashes during in-place menu refreshes.
        if submenu == nil {
            item.toolTip = tooltipLines.joined(separator: "\n")
        }
        if #available(macOS 14.4, *) {
            item.subtitle = visibleDetailLines.joined(separator: "\n")
        } else if !visibleDetailLines.isEmpty {
            item.attributedTitle = Self.costMenuFallbackAttributedTitle(
                title: title,
                visibleDetailLines: visibleDetailLines)
        }
        return item
    }

    /// Lines that read as "Label: value" (Today, the history window, metered spend, comparisons).
    static func costMenuValueLines(tokenUsage: UsageMenuCardView.Model.TokenUsageSection?) -> Set<String> {
        let lines = [tokenUsage?.sessionLine, tokenUsage?.monthLine, tokenUsage?.meteredLine].compactMap(\.self)
            + (tokenUsage?.comparisonLines ?? [])
        return Set(lines.filter { !$0.isEmpty })
    }

    static func costMenuTooltipLines(
        provider _: UsageProvider,
        tokenUsage: UsageMenuCardView.Model.TokenUsageSection?) -> [String]
    {
        let lines = [
            tokenUsage?.sessionLine,
            tokenUsage?.monthLine,
            tokenUsage?.meteredLine,
        ]
            .compactMap(\.self)
            + (tokenUsage?.comparisonLines ?? [])
            + [tokenUsage?.hintLine, tokenUsage?.errorLine].compactMap(\.self)
        return lines.filter { !$0.isEmpty }
    }

    static func costMenuVisibleDetailLines(
        provider: UsageProvider,
        tokenUsage: UsageMenuCardView.Model.TokenUsageSection?,
        hasSubmenu: Bool) -> [String]
    {
        guard !hasSubmenu else { return [] }
        let primaryLines = ([
            tokenUsage?.sessionLine,
            tokenUsage?.monthLine,
            tokenUsage?.meteredLine,
        ]
            .compactMap(\.self)
            + (tokenUsage?.comparisonLines ?? [])
            + [provider == .codex ? tokenUsage?.hintLine : nil].compactMap(\.self)
            + [tokenUsage?.errorLine].compactMap(\.self))
            .filter { !$0.isEmpty }
        guard primaryLines.isEmpty else { return primaryLines }
        return [tokenUsage?.hintLine]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
    }

    static func costMenuFallbackAttributedTitle(
        title: String,
        visibleDetailLines: [String]) -> NSAttributedString
    {
        let detailText = visibleDetailLines.joined(separator: " | ")
        let title = detailText.isEmpty ? title : "\(title)  \(detailText)"
        let attributedTitle = NSMutableAttributedString(
            string: title,
            attributes: [.font: NSFont.menuFont(ofSize: NSFont.systemFontSize)])
        guard !detailText.isEmpty else { return attributedTitle }

        let detailRange = (title as NSString).range(of: detailText)
        attributedTitle.addAttributes(
            [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ],
            range: detailRange)
        return attributedTitle
    }
}
