import AppKit
import OpenBarCore
import SwiftUI

/// SwiftUI card used inside the NSMenu to mirror Apple's rich menu panels.
struct UsageMenuCardView: View {
    struct Model {
        enum PercentStyle: String {
            case left
            case used

            var labelSuffix: String {
                switch self {
                case .left: L("usage_percent_suffix_left")
                case .used: L("usage_percent_suffix_used")
                }
            }

            var accessibilityLabel: String {
                switch self {
                case .left: L("Usage remaining")
                case .used: L("Usage used")
                }
            }
        }

        struct Metric: Identifiable {
            struct LinePresentation: Equatable {
                let titleText: String
                let resetText: String?
                let metaText: String?
            }

            let id: String
            var title: String
            var percent: Double
            let percentStyle: PercentStyle
            var statusText: String?
            var resetText: String?
            var detailText: String?
            var dailyTargetText: String?
            var detailLeftText: String?
            var detailRightText: String?
            var pacePercent: Double?
            /// True when detailLeftText/detailRightText came from a pace forecast.
            let detailIsPaceDerived: Bool
            /// The pace forecast's verdict, when the lane has one: true lasts until reset, false runs
            /// out first. Drives the pace line's status symbol; nil shows the text without a symbol.
            var paceWillLastToReset: Bool?
            let paceOnTop: Bool
            let warningMarkerPercents: [Double]
            let workdayMarkerPercents: [Double]
            let workdayTickAppearance: WorkdayTickAppearance
            let cardStyle: Bool
            var sessionEquivalentDetail: UsagePaceText.SessionEquivalentDetail?
            let isSyntheticCreditLane: Bool
            var helpText: String?

            init(
                id: String,
                title: String,
                percent: Double,
                percentStyle: PercentStyle,
                statusText: String? = nil,
                resetText: String?,
                detailText: String?,
                detailLeftText: String?,
                detailRightText: String?,
                pacePercent: Double?,
                detailIsPaceDerived: Bool = false,
                paceWillLastToReset: Bool? = nil,
                paceOnTop: Bool,
                warningMarkerPercents: [Double] = [],
                workdayMarkerPercents: [Double] = [],
                workdayTickAppearance: WorkdayTickAppearance = .subtle,
                cardStyle: Bool = false,
                sessionEquivalentDetail: UsagePaceText.SessionEquivalentDetail? = nil,
                isSyntheticCreditLane: Bool = false)
            {
                self.id = id
                self.title = title
                self.percent = percent
                self.percentStyle = percentStyle
                self.statusText = statusText
                self.resetText = resetText
                self.detailText = detailText
                self.detailLeftText = detailLeftText
                self.detailRightText = detailRightText
                self.pacePercent = pacePercent
                self.detailIsPaceDerived = detailIsPaceDerived
                self.paceWillLastToReset = paceWillLastToReset
                self.paceOnTop = paceOnTop
                self.warningMarkerPercents = warningMarkerPercents
                self.workdayMarkerPercents = workdayMarkerPercents
                self.workdayTickAppearance = workdayTickAppearance
                self.cardStyle = cardStyle
                self.sessionEquivalentDetail = sessionEquivalentDetail
                self.isSyntheticCreditLane = isSyntheticCreditLane
            }

            var percentLabel: String {
                UsageFormatter.percentText(self.percent, suffix: self.percentStyle.labelSuffix)
            }

            func linePresentation(title: String) -> LinePresentation {
                // Keep the title aligned with the configured used/remaining label semantics.
                let metaParts = [
                    self.detailLeftText,
                    self.detailRightText,
                    self.sessionEquivalentDetail?.leftText,
                    self.sessionEquivalentDetail?.rightText,
                ].compactMap { text -> String? in
                    guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                        return nil
                    }
                    return text
                }
                return LinePresentation(
                    titleText: "\(title) \(self.percentLabel)",
                    resetText: self.resetText,
                    metaText: metaParts.isEmpty ? nil : metaParts.joined(separator: " · "))
            }
        }

        enum SubtitleStyle {
            case info
            case loading
            case error
        }

        struct TokenUsageSection {
            let isRefreshing: Bool
            let sessionLine: String
            let monthLine: String
            let meteredLine: String?
            let comparisonLines: [String]
            let hintLine: String?
            let errorLine: String?
            let errorCopyText: String?

            /// Explicit initializer so `meteredLine`/`comparisonLines` default to empty: callers
            /// that predate them (and providers that never report them) keep their call sites.
            init(
                isRefreshing: Bool = false,
                sessionLine: String,
                monthLine: String,
                meteredLine: String? = nil,
                comparisonLines: [String] = [],
                hintLine: String?,
                errorLine: String?,
                errorCopyText: String?)
            {
                self.isRefreshing = isRefreshing
                self.sessionLine = sessionLine
                self.monthLine = monthLine
                self.meteredLine = meteredLine
                self.comparisonLines = comparisonLines
                self.hintLine = hintLine
                self.errorLine = errorLine
                self.errorCopyText = errorCopyText
            }
        }

        struct ProviderCostSection {
            let title: String
            let percentUsed: Double?
            let spendLine: String
            let percentLine: String?
            var balanceLine: String?
            var personalSpendLine: String?
            var dailyTargetText: String?
            var presentation: Presentation = .detail
            var showsInProviderDetails = true
            var percentStyle: PercentStyle = .used
        }

        let provider: UsageProvider
        let providerName: String
        var email: String
        var accountIdentityFingerprint: String?
        let subtitleText: String
        let subtitleStyle: SubtitleStyle
        var lastKnownUsageText: String?
        var usesLiveSubtitle: Bool = false
        let planText: String?
        var planEmphasis: PlanEmphasis = .none
        var metrics: [Metric]
        var usageNotes: [String]
        var subscriptionNotes: [String] = []
        var providerDetails: [ProviderDetailSection] = []
        /// Provider-owned titles remain stable when the displayed sections are localized or redacted.
        var providerDetailRawTitles: [String?] = []
        var throughput: ProviderThroughputSection?
        let openAIAPIUsage: OpenAIAPIUsageSnapshot?
        let inlineUsageDashboard: InlineUsageDashboardModel?
        var creditsText: String?
        var creditsRemaining: Double?
        var creditsShowProgress = true
        var creditsProgressPercent: Double?, creditsScaleText: String?
        var creditsHintText: String?
        var creditsHintCopyText: String?
        var limitResetCredits: LimitResetCreditsPresentation?
        var cloudCredits: ProviderCostSection?
        var providerCost: ProviderCostSection?
        let tokenUsage: TokenUsageSection?
        let placeholder: String?
        let progressColor: Color
    }

    let model: Model
    var layoutModel: Model?
    let width: CGFloat
    var planAction: (() -> Void)?
    @Environment(\.menuCardRefreshMonitor) private var refreshMonitor

    static func popupMetricTitle(provider: UsageProvider, metric: Model.Metric) -> String {
        if provider == .openrouter, metric.id == "primary" {
            return L("API key limit")
        }
        return metric.title
    }

    /// One hosting view, several soft cards (spec §9.2, §11): the provider card first, then credits,
    /// extra usage, and cost, each its own card separated by the 6-pt card gap.
    var body: some View {
        let liveModel = self.liveModel
        let layoutModel = self.layoutModel ?? self.model
        VStack(alignment: .leading, spacing: OpenBarMenuStyle.cardGap) {
            VStack(alignment: .leading, spacing: 0) {
                UsageMenuCardHeaderView(model: layoutModel, planAction: self.planAction)
                if Self.hasDetails(for: liveModel) {
                    self.providerCardDetails(liveModel: liveModel, layoutModel: layoutModel)
                        .padding(.top, Self.dividerBottomPadding(for: liveModel))
                }
            }
            .menuCardChrome()

            if liveModel.usesStackedDetailLayout {
                if let credits = liveModel.creditsText {
                    VStack(alignment: .leading, spacing: OpenBarMenuStyle.laneSpacing) {
                        CreditsBarContent(
                            creditsText: credits,
                            showsProgress: liveModel.creditsShowProgress,
                            progressPercent: liveModel.creditsProgressPercent,
                            scaleText: liveModel.creditsScaleText,
                            hintText: liveModel.creditsHintText,
                            hintCopyText: liveModel.creditsHintCopyText,
                            progressColor: liveModel.progressColor)
                        if liveModel.creditsOnlyInlineUsageDashboard, let dashboard = liveModel.inlineUsageDashboard {
                            InlineUsageDashboardContent(model: dashboard)
                        }
                    }
                    .menuCardChrome()
                }
                if let providerCost = liveModel.providerCost {
                    ProviderCostContent(section: providerCost, progressColor: liveModel.progressColor)
                        .menuCardChrome()
                }
                if let tokenUsage = liveModel.tokenUsage {
                    TokenUsageSectionContent(
                        provider: liveModel.provider,
                        tokenUsage: tokenUsage,
                        showsCodexHint: liveModel.inlineUsageDashboard == nil)
                        .menuCardChrome()
                }
            }
        }
        .frame(width: self.width, alignment: .leading)
    }

    @ViewBuilder
    private func providerCardDetails(liveModel: Model, layoutModel: Model) -> some View {
        if !liveModel.usesStackedDetailLayout {
            VStack(alignment: .leading, spacing: OpenBarMenuStyle.laneSpacing) {
                if liveModel.showsChartSwitch, let throughput = liveModel.throughput,
                   let dashboard = liveModel.inlineUsageDashboard
                {
                    ProviderMenuChartContent(
                        provider: liveModel.provider.instanceID,
                        throughput: throughput,
                        dashboard: dashboard,
                        color: liveModel.progressColor)
                        .id(liveModel.provider.instanceID)
                } else if let throughput = liveModel.throughput {
                    ProviderThroughputContent(section: throughput, color: liveModel.progressColor)
                }
                if let dashboard = liveModel.inlineUsageDashboard {
                    InlineUsageDashboardContent(model: dashboard, showsChart: !liveModel.showsChartSwitch)
                } else if !liveModel.usageNotes.isEmpty {
                    UsageNotesContent(notes: liveModel.usageNotes)
                } else if let placeholder = liveModel.placeholder {
                    // Non-stacked placeholders are standalone detail rows; stacked usage placeholders are gated below.
                    MenuCardPlaceholderText(text: placeholder)
                }
                if !liveModel.providerDetails.isEmpty {
                    ProviderDetailSectionsContent(
                        sections: liveModel.providerDetails,
                        chartColor: liveModel.progressColor)
                }
            }
        } else if liveModel.hasUsageContent, !liveModel.creditsOnlyInlineUsageDashboard {
            UsageMenuCardUsageContentView(
                model: liveModel,
                layoutModel: layoutModel,
                showBottomDivider: false)
        }
    }

    private var liveModel: Model {
        guard self.model.usesLiveSubtitle else { return self.model }
        return self.refreshMonitor?.model(for: self.model.provider, fallback: self.model) ?? self.model
    }

    /// The provider card shows content below its header (lanes, notes, dashboards, placeholder).
    private static func hasDetails(for model: Model) -> Bool {
        model.hasUsageContent && (!model.usesStackedDetailLayout || !model.creditsOnlyInlineUsageDashboard)
    }

    /// Space between the card header and the first lane (or other detail content).
    static func dividerBottomPadding(for model: Model) -> CGFloat {
        if model.usesStackedDetailLayout, model.hasUsageContent {
            return UsageMenuCardLayout.postHeaderDividerContentSpacing
        }
        return UsageMenuCardLayout.sectionBottomPadding
    }
}

/// Provider logo for card headers: the shipped template artwork at 16 pt in the text color.
struct MenuCardProviderLogo: View {
    let provider: UsageProvider

    var body: some View {
        if let image = ProviderBrandIcon.image(for: self.provider) {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .frame(width: OpenBarMenuStyle.logoSize, height: OpenBarMenuStyle.logoSize)
                .accessibilityHidden(true)
        }
    }
}

/// Card header (spec §9.2): logo · name · plan · submenu chevron, then the account and
/// "Updated …" line, an error block, or the last-known notice.
struct UsageMenuCardHeaderView: View {
    let model: UsageMenuCardView.Model
    var planAction: (() -> Void)?
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.menuCardRefreshMonitor) private var refreshMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: UsageMenuCardLayout.headerLineSpacing) {
            self.titleRow
            let liveSubtitle = self.liveSubtitle
            let displayed = liveSubtitle.displayed(reservesStaleRow: self.model.lastKnownUsageText != nil)
            // Keep the geometry AppKit measured for this hosted row. A new error stays one line
            // until the next rebuild; a recovered error keeps its reserved height until then.
            if self.model.subtitleStyle == .error {
                if !self.model.email.isEmpty {
                    self.metaText(self.model.email)
                        .truncationMode(.middle)
                }
                self.errorBlock(liveSubtitle: liveSubtitle, displayedText: displayed.subtitle)
            } else {
                self.subline(subtitle: displayed.subtitle, style: liveSubtitle.style)
            }
            // The reserved row keeps its measured height; a recovery hides it until the next rebuild.
            if let reservedStaleText = self.model.lastKnownUsageText {
                HStack(alignment: .firstTextBaseline, spacing: OpenBarSpacing.tight) {
                    MenuToneSymbol(
                        systemName: OpenBarQuotaTone.stale.symbolName ?? "clock",
                        color: MenuHighlightStyle.secondary(self.isHighlighted))
                    // Up to two lines, measured from the reserved text so a live update keeps the height.
                    Text(reservedStaleText)
                        .font(OpenBarTheme.Fonts.meta)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .topLeading) {
                            Text(displayed.staleRow ?? reservedStaleText)
                                .font(OpenBarTheme.Fonts.meta)
                                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                                .lineLimit(2)
                                .truncationMode(.tail)
                        }
                }
                .opacity(displayed.staleRow == nil ? 0 : 1)
            }
        }
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: OpenBarMenuStyle.logoTitleSpacing) {
            MenuCardProviderLogo(provider: self.model.provider)
            Text(self.model.providerName)
                .font(OpenBarTheme.Fonts.cardTitle)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: OpenBarSpacing.regular)
            if let plan = self.model.planText {
                Group {
                    if let planAction {
                        Button(action: planAction) {
                            Text(plan)
                        }
                        .buttonStyle(.plain)
                        .menuCardInteractiveControl()
                        .accessibilityLabel(plan)
                    } else {
                        Text(plan)
                    }
                }
                .font(OpenBarTheme.Fonts.meta)
                .fontWeight(self.model.planEmphasis.isEmphasized ? .semibold : nil)
                .foregroundStyle(self.model.planEmphasis.color(highlighted: self.isHighlighted))
                .lineLimit(1)
                .layoutPriority(2)
            }
            MenuCardSubmenuChevron()
        }
    }

    /// Account (middle-truncated) · "Updated …". The status text keeps its width; the account yields.
    @ViewBuilder
    private func subline(subtitle: String, style: UsageMenuCardView.Model.SubtitleStyle) -> some View {
        let email = self.model.email
        if email.isEmpty || subtitle.isEmpty {
            let text = email.isEmpty ? subtitle : email
            if !text.isEmpty {
                Text(MenuInlineCodeText.attributed(text))
                    .font(OpenBarTheme.Fonts.meta)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(email)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(" · ")
                    .fixedSize()
                Text(MenuInlineCodeText.attributed(subtitle))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Spacer(minLength: 0)
            }
            .font(OpenBarTheme.Fonts.meta)
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
        }
    }

    /// Error: critical octagon and up to three lines of text, copy button on the right.
    private func errorBlock(liveSubtitle: MenuCardLiveSubtitle, displayedText: String) -> some View {
        let isError = liveSubtitle.style == .error
        let showsCopyButton = isError && !liveSubtitle.text.isEmpty
        return HStack(alignment: .top, spacing: OpenBarSpacing.compact) {
            MenuToneSymbol(
                systemName: OpenBarQuotaTone.critical.symbolName ?? "exclamationmark.octagon.fill",
                color: MenuHighlightStyle.error(self.isHighlighted))
                .padding(.top, 1)
                .opacity(isError ? 1 : 0)
            Text(MenuInlineCodeText.attributed(self.model.subtitleText))
                .font(OpenBarTheme.Fonts.meta)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .topLeading) {
                    Text(MenuInlineCodeText.attributed(displayedText))
                        .font(OpenBarTheme.Fonts.meta)
                        .foregroundStyle(isError
                            ? MenuHighlightStyle.primary(self.isHighlighted)
                            : MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .clipped()
                .layoutPriority(1)
            CopyIconButton(
                copyText: liveSubtitle.text,
                isHighlighted: self.isHighlighted,
                isInteractive: showsCopyButton)
                // Center the padded icon on the first text line, independent of wrapping.
                    .offset(y: -4)
                    .opacity(showsCopyButton ? 1 : 0)
                    .allowsHitTesting(showsCopyButton)
                    .accessibilityHidden(!showsCopyButton)
        }
        .padding(.top, OpenBarSpacing.hairline)
    }

    private func metaText(_ text: String) -> some View {
        Text(text)
            .font(OpenBarTheme.Fonts.meta)
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            .lineLimit(1)
    }

    private var liveSubtitle: MenuCardLiveSubtitle {
        let fallback = MenuCardLiveSubtitle(
            text: self.model.subtitleText,
            style: self.model.subtitleStyle,
            lastKnownUsageText: self.model.lastKnownUsageText)
        guard self.model.usesLiveSubtitle else { return fallback }
        return self.refreshMonitor?.subtitle(for: self.model.provider, fallback: fallback) ?? fallback
    }
}

private struct CopyIconButtonStyle: ButtonStyle {
    let isHighlighted: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: OpenBarRadius.chip, style: .continuous)
                    .fill(MenuHighlightStyle.secondary(self.isHighlighted).opacity(configuration.isPressed ? 0.18 : 0))
            }
    }
}

private struct CopyIconButton: View {
    let copyText: String
    let isHighlighted: Bool
    let isInteractive: Bool

    @State private var didCopy = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            self.handleCopy()
        } label: {
            Image(systemName: self.didCopy ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(CopyIconButtonStyle(isHighlighted: self.isHighlighted))
        .menuCardInteractiveControl(isEnabled: self.isInteractive)
        .accessibilityLabel(self.didCopy ? L("Copied") : L("Copy error"))
    }

    private func handleCopy() {
        let text = self.copyText
        self.resetTask?.cancel()
        MenuPasteboardCopy.perform(text, completion: {
            self.didCopy = true
            // One-shot confirmation reset after a user click; not a repeating timer.
            self.resetTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.9))
                self.didCopy = false
            }
        })
    }
}

private struct UsageNotesContent: View {
    let notes: [String]
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: OpenBarSpacing.tight) {
            ForEach(Array(self.notes.enumerated()), id: \.offset) { _, note in
                Text(note)
                    .font(OpenBarTheme.Fonts.meta)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Empty or placeholder state: one secondary `meta` line ("No usage yet").
private struct MenuCardPlaceholderText: View {
    let text: String
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        Text(self.text)
            .font(OpenBarTheme.Fonts.meta)
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
    }
}

/// Header-only card (sectioned menus and Overview rows without usage).
struct UsageMenuCardHeaderSectionView: View {
    let model: UsageMenuCardView.Model
    let showDivider: Bool
    let width: CGFloat

    var body: some View {
        UsageMenuCardHeaderView(model: self.model, planAction: nil)
            .menuCardChrome()
            .frame(width: self.width, alignment: .leading)
    }
}

/// Header and quota lanes in one card, with live values drawn over frozen layout geometry.
struct UsageMenuCardHeaderAndUsageCard: View {
    let model: UsageMenuCardView.Model
    let layoutModel: UsageMenuCardView.Model
    var showsSectionDividers = true
    var compactMetrics = false
    var footer: String?
    @Environment(\.menuCardRefreshMonitor) private var refreshMonitor
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            UsageMenuCardHeaderView(model: self.layoutModel, planAction: nil)
            if self.layoutModel.hasUsageContent {
                UsageMenuCardUsageContentView(
                    model: self.liveModel,
                    layoutModel: self.layoutModel,
                    showBottomDivider: false,
                    showsSectionDividers: self.showsSectionDividers,
                    compactMetrics: self.compactMetrics)
                    .padding(.top, UsageMenuCardLayout.postHeaderDividerContentSpacing)
            }
            if let footer {
                Text(footer)
                    .font(OpenBarTheme.Fonts.meta)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
                    .padding(.top, OpenBarSpacing.regular)
            }
        }
        .menuCardChrome()
    }

    private var liveModel: UsageMenuCardView.Model {
        guard self.model.usesLiveSubtitle else { return self.model }
        return self.refreshMonitor?.model(for: self.model.provider, fallback: self.model) ?? self.model
    }
}

struct UsageMenuCardUsageContentView: View {
    let model: UsageMenuCardView.Model
    let layoutModel: UsageMenuCardView.Model
    let showBottomDivider: Bool
    var showsSectionDividers = true
    var compactMetrics = false
    @Environment(\.menuItemHighlighted) private var isHighlighted

    /// Doubao ships Coding Plan and Agent Plan subscriptions, each with personal
    /// and team editions whose windows share period labels. Split the two plan
    /// families here; team rows keep distinct ids and disclose their edition.
    private var doubaoSplitMetrics: (
        coding: [UsageMenuCardView.Model.Metric],
        agent: [UsageMenuCardView.Model.Metric])?
    {
        guard self.model.provider == .doubao else { return nil }
        let agent = self.model.metrics.filter { $0.id.hasPrefix("doubao-agent-") }
        guard !agent.isEmpty else { return nil }
        let coding = self.model.metrics.filter { !$0.id.hasPrefix("doubao-agent-") }
        return (coding, agent)
    }

    private func groupHeader(_ title: String) -> some View {
        Text(L(title))
            .font(OpenBarTheme.Fonts.laneTitle)
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
    }

    private func metricRows(_ metrics: [UsageMenuCardView.Model.Metric]) -> some View {
        ForEach(metrics, id: \.id) { metric in
            MetricRow(
                metric: metric,
                layoutMetric: self.layoutModel.metrics.first { $0.id == metric.id } ?? metric,
                title: UsageMenuCardView.popupMetricTitle(provider: self.model.provider, metric: metric),
                progressColor: self.model.progressColor,
                compact: self.compactMetrics,
                accessibilityProviderName: self.model.providerName)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OpenBarMenuStyle.laneSpacing) {
            if let split = self.doubaoSplitMetrics {
                if !split.coding.isEmpty {
                    self.groupHeader("Coding Plan")
                    self.metricRows(split.coding)
                }
                if !split.coding.isEmpty, self.showsSectionDividers {
                    Divider()
                }
                self.groupHeader("Agent Plan")
                self.metricRows(split.agent)
            } else {
                self.metricRows(self.model.metrics)
            }
            if !self.model.quotaSubscriptionNotes.isEmpty,
               self.model.showsOverviewSupplementalContent(compact: self.compactMetrics)
            {
                UsageNotesContent(notes: self.model.quotaSubscriptionNotes)
            }
            if let resetCredits = self.model.limitResetCredits {
                if !self.model.metrics.isEmpty, self.showsSectionDividers {
                    Divider()
                }
                LimitResetCreditsContent(presentation: resetCredits)
            }
            if self.model.showsOverviewSupplementalContent(compact: self.compactMetrics) {
                self.supplementalContent
            }
            if let cloudCredits = self.model.cloudCredits,
               self.model.showsOverviewSupplementalContent(compact: self.compactMetrics)
            {
                if self.model.hasUsageContentAboveCloudCredits, self.showsSectionDividers {
                    Divider()
                }
                ProviderCostContent(
                    section: cloudCredits,
                    progressColor: self.model.progressColor,
                    showsSubmenuChevron: false)
            }
            if self.showBottomDivider {
                Divider()
            }
        }
    }

    @ViewBuilder
    private var supplementalContent: some View {
        if self.model.showsChartSwitch, let throughput = self.model.throughput,
           let dashboard = self.model.inlineUsageDashboard
        {
            ProviderMenuChartContent(
                provider: self.model.provider.instanceID,
                throughput: throughput,
                dashboard: dashboard,
                color: self.model.progressColor)
                .id(self.model.provider.instanceID)
        } else if let throughput = self.model.throughput {
            ProviderThroughputContent(section: throughput, color: self.model.progressColor)
        }
        if let dashboard = self.model.inlineUsageDashboard {
            InlineUsageDashboardContent(model: dashboard, showsChart: !self.model.showsChartSwitch)
            if self.model.quotaSubscriptionNotes.isEmpty, !self.model.subscriptionNotes.isEmpty {
                UsageNotesContent(notes: self.model.subscriptionNotes)
            }
        } else if !self.model.supplementalUsageNotes.isEmpty {
            UsageNotesContent(notes: self.model.supplementalUsageNotes)
        } else if let placeholder = self.model.placeholder, self.model.metrics.isEmpty,
                  self.model.limitResetCredits == nil, self.model.cloudCredits == nil
        {
            MenuCardPlaceholderText(text: placeholder)
        }
        if !self.model.providerDetails.isEmpty {
            ProviderDetailSectionsContent(
                sections: self.model.providerDetails,
                chartColor: self.model.progressColor)
        }
    }
}

/// Quota lanes as a standalone card.
struct UsageMenuCardUsageSectionView: View {
    let model: UsageMenuCardView.Model
    let layoutModel: UsageMenuCardView.Model
    let showBottomDivider: Bool
    let bottomPadding: CGFloat
    let width: CGFloat
    var showsSectionDividers = true
    var compactMetrics = false
    @Environment(\.menuCardRefreshMonitor) private var refreshMonitor

    var body: some View {
        UsageMenuCardUsageContentView(
            model: self.liveModel,
            layoutModel: self.layoutModel,
            showBottomDivider: self.showBottomDivider,
            showsSectionDividers: self.showsSectionDividers,
            compactMetrics: self.compactMetrics)
            .menuCardChrome()
            .frame(width: self.width, alignment: .leading)
    }

    private var liveModel: UsageMenuCardView.Model {
        guard self.model.usesLiveSubtitle else { return self.model }
        return self.refreshMonitor?.model(for: self.model.provider, fallback: self.model) ?? self.model
    }
}

/// Credits as its own card (sectioned menus).
struct UsageMenuCardCreditsSectionView: View {
    let model: UsageMenuCardView.Model
    let showBottomDivider: Bool
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let width: CGFloat
    @Environment(\.menuCardRefreshMonitor) private var refreshMonitor

    var body: some View {
        let liveModel = self.liveModel
        if let credits = liveModel.creditsText {
            CreditsBarContent(
                creditsText: credits,
                showsProgress: liveModel.creditsShowProgress,
                progressPercent: liveModel.creditsProgressPercent,
                scaleText: liveModel.creditsScaleText,
                hintText: liveModel.creditsHintText,
                hintCopyText: liveModel.creditsHintCopyText,
                progressColor: liveModel.progressColor)
                .menuCardChrome()
                .frame(width: self.width, alignment: .leading)
        }
    }

    private var liveModel: UsageMenuCardView.Model {
        guard self.model.usesLiveSubtitle else { return self.model }
        return self.refreshMonitor?.model(for: self.model.provider, fallback: self.model) ?? self.model
    }
}

private struct CreditsBarContent: View {
    let creditsText: String
    let showsProgress: Bool
    var progressPercent: Double?, scaleText: String?
    let hintText: String?
    let hintCopyText: String?
    let progressColor: Color
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: OpenBarMenuStyle.laneInnerSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: OpenBarSpacing.regular) {
                Text(L("Credits"))
                    .font(OpenBarTheme.Fonts.laneTitle)
                Spacer(minLength: OpenBarSpacing.regular)
                MenuCardSubmenuChevron()
            }
            if self.showsProgress, let progressPercent {
                UsageProgressBar(
                    percent: min(100, max(0, progressPercent)),
                    tint: self.progressColor,
                    accessibilityLabel: L("Credits remaining"))
                HStack(alignment: .firstTextBaseline) {
                    Text(self.creditsText)
                        .font(OpenBarTheme.Fonts.meta)
                        .lineLimit(1)
                    Spacer()
                    if let scaleText {
                        Text(scaleText)
                            .font(OpenBarTheme.Fonts.meta)
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    }
                }
            } else {
                Text(self.creditsText)
                    .font(OpenBarTheme.Fonts.meta)
            }
            if let hintText, !hintText.isEmpty {
                Text(hintText)
                    .font(OpenBarTheme.Fonts.meta)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .overlay {
                        ClickToCopyOverlay(copyText: self.hintCopyText ?? hintText)
                    }
            }
        }
    }
}

/// Extra usage as its own card (sectioned menus).
struct UsageMenuCardExtraUsageSectionView: View {
    let model: UsageMenuCardView.Model
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let width: CGFloat
    @Environment(\.menuCardRefreshMonitor) private var refreshMonitor

    var body: some View {
        let liveModel = self.liveModel
        if let providerCost = liveModel.providerCost {
            ProviderCostContent(
                section: providerCost,
                progressColor: liveModel.progressColor)
                .menuCardChrome()
                .frame(width: self.width, alignment: .leading)
        }
    }

    private var liveModel: UsageMenuCardView.Model {
        guard self.model.usesLiveSubtitle else { return self.model }
        return self.refreshMonitor?.model(for: self.model.provider, fallback: self.model) ?? self.model
    }
}

// MARK: - Model factory

extension UsageMenuCardView.Model {
    static func make(_ input: Input, calendar: Calendar = .current) -> UsageMenuCardView.Model {
        let planText = Self.plan(
            for: input.provider,
            snapshot: input.snapshot,
            account: input.account,
            override: input.planOverride,
            metadata: input.metadata)
        let paceVisible = input.paceVisible && ProviderDescriptorRegistry.descriptor(for: input.provider).pace
            .allowsPace(dataConfidence: input.snapshot?.dataConfidence ?? .unknown)
        let rawMetrics = Self.metrics(input: input)
        let metrics = Self.redactedMetrics(
            Self.paceGatedMetrics(
                paceVisible ? Self.monthlyTargetMetrics(rawMetrics, input: input, calendar: calendar) : rawMetrics,
                paceVisible: paceVisible),
            provider: input.provider,
            hidePersonalInfo: input.hidePersonalInfo)
        let openAIAPIUsage = input.snapshot?.openAIAPIUsage
        let inlineUsageDashboard = Self.inlineUsageDashboard(input: input)
        let usageNotes = Self.usageNotes(input: input)
        let presentation = ProviderDescriptorRegistry.descriptor(for: input.provider).presentation
        let menuCard = presentation.menuCard
        let rawCreditsText: String? = if !menuCard.showsCreditsSection ||
            !input.showOptionalCreditsAndExtraUsage
        {
            nil
        } else {
            Self.creditsLine(
                metadata: input.metadata,
                snapshot: input.snapshot,
                credits: input.credits,
                error: input.creditsError,
                preferredCurrencyCode: input.preferredCurrencyCode)
        }
        let creditsText = PersonalInfoRedactor.redactEmails(in: rawCreditsText, isEnabled: input.hidePersonalInfo)
        let creditsProgressPercent = Self.creditsProgressPercent(credits: input.credits)
        let creditsScaleText = Self.creditsScaleText(credits: input.credits)
        let codexCreditLimitDetail = Self.codexCreditLimitDetail(credits: input.credits, now: input.now)
        let isClaudeAdminAPI = input.snapshot?.loginMethod(for: input.provider) == "Admin API"
        let extraUsageCost = Self.resolvedProviderCost(input: input)
        let extraUsageSnapshot = extraUsageCost.map { cost in
            (input.snapshot ?? UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: cost.updatedAt)).with(providerCost: cost)
        } ?? input.snapshot
        let showsProviderCost = menuCard.showsProviderCost(context: ProviderCostVisibilityContext(
            snapshot: extraUsageSnapshot,
            showOptionalUsage: input.showOptionalCreditsAndExtraUsage))
        let costPresentation = extraUsageSnapshot.map { presentation.cost(snapshot: $0) }
        let providerCostStyle = costPresentation?.menuCardStyle ?? .generic
        let providerCostFollowsSummaryStyle = Self.providerCostFollowsSummaryStyle(
            cost: extraUsageCost,
            style: providerCostStyle,
            isClaudeAdminAPI: isClaudeAdminAPI) && !menuCard.providerCostIsRequiredUsage
        var providerCost: ProviderCostSection? = if !showsProviderCost ||
            metrics.contains(where: { $0.id == "claude-extra-usage" }) ||
            (providerCostFollowsSummaryStyle && !input.costSummaryInlineEnabled)
        {
            nil
        } else {
            Self.providerCostSection(
                cost: extraUsageCost,
                style: providerCostStyle,
                percentStyle: input.usageBarsShowUsed ? .used : .left,
                isClaudeAdminAPI: isClaudeAdminAPI,
                preferredCurrencyCode: input.preferredCurrencyCode)
        }
        if paceVisible, providerCost?.percentUsed != nil {
            providerCost?.dailyTargetText = Self.monthlyCostTarget(
                cost: extraUsageCost, input: input, calendar: calendar)
        }
        let tokenUsageSnapshot = Self.tokenUsageSnapshot(input: input)
        let tokenUsage = Self.tokenUsageSection(
            provider: input.provider,
            enabled: input.tokenCostMenuSectionEnabled,
            isRefreshing: input.tokenCostIsRefreshing,
            comparisonPeriodsEnabled: input.costComparisonPeriodsEnabled,
            snapshot: tokenUsageSnapshot,
            error: input.tokenError,
            preferredCurrencyCode: input.preferredCurrencyCode,
            calendar: input.costUsageBucketCalendar)
        let subtitle = input.subtitleOverride.map { (text: $0, style: SubtitleStyle.info) }
            ?? Self.subtitle(
                snapshot: input.snapshot,
                isRefreshing: input.isRefreshing,
                lastError: Self.lastError(input: input),
                hasLastKnownUsage: input.lastKnownUsageCapturedAt != nil,
                now: input.now)
        let redacted = Self.redactedText(input: input, subtitle: subtitle)
        let placeholder = Self.placeholder(input: input)
        let providerDetails = Self.visibleProviderDetails(
            input: input,
            replacedRows: providerCost == nil ? [:] : costPresentation?.replacedDetailRows ?? [:])

        return UsageMenuCardView.Model(
            provider: input.provider,
            providerName: input.metadata.displayName,
            email: redacted.email,
            accountIdentityFingerprint: Self.trackedAccountIdentityFingerprint(input: input),
            subtitleText: redacted.subtitleText,
            subtitleStyle: subtitle.style,
            lastKnownUsageText: input.lastKnownUsageCapturedAt.map {
                LastKnownUsagePresentation.message(capturedAt: $0, now: input.now)
            },
            usesLiveSubtitle: input.usesLiveSubtitle,
            planText: planText,
            planEmphasis: input.planEmphasis,
            metrics: metrics,
            usageNotes: usageNotes,
            subscriptionNotes: Self.subscriptionMetadataNotes(snapshot: input.snapshot, provider: input.provider),
            providerDetails: providerDetails.sections,
            providerDetailRawTitles: providerDetails.rawTitles,
            throughput: input.snapshot?.throughput.map {
                ProviderThroughputSection(snapshot: $0, presentation: input.throughputPresentation)
            },
            openAIAPIUsage: openAIAPIUsage,
            inlineUsageDashboard: inlineUsageDashboard,
            creditsText: creditsText,
            creditsRemaining: input.credits?.displayRemaining,
            creditsShowProgress: input.credits?.hasWorkspaceBalance != true,
            creditsProgressPercent: creditsProgressPercent,
            creditsScaleText: creditsScaleText,
            creditsHintText: codexCreditLimitDetail ?? redacted.creditsHintText,
            creditsHintCopyText: codexCreditLimitDetail ?? redacted.creditsHintCopyText,
            limitResetCredits: Self.limitResetCredits(input: input),
            cloudCredits: Self.cloudCreditsSection(input: input),
            providerCost: providerCost,
            tokenUsage: tokenUsage,
            placeholder: placeholder,
            progressColor: Self.progressColor(for: input.provider))
    }

    private static func resolvedProviderCost(input: Input) -> ProviderCostSnapshot? {
        // Provider-specific by design: Codex extra credits come from member credit snapshots, not USD spend.
        if input.provider == .codex {
            if let projected = input.codexProjection?.extraUsageCost {
                return projected
            }
            if let fromCredits = CodexExtraUsageCost.providerCost(from: input.credits) {
                return fromCredits
            }
        }
        return input.snapshot?.providerCost
    }

    private static func email(from input: Input) -> String {
        // Provider-specific by design: a claude-swap or tcr accountOverride is the display label
        // (alias or email · org). Other stacked sources keep fetched identity first.
        if input.accountIsAuthoritative,
           input.provider == .claude,
           input.sourceLabel.flatMap(ClaudeSwapAccountSource.init(identitySource:)) != nil,
           let email = input.account.email, !email.isEmpty
        {
            return email
        }
        if let email = input.snapshot?.accountEmail(for: input.provider), !email.isEmpty {
            return email
        }
        // Provider-specific by design: Cursor app auth can expose only a subject ID, so its card needs this fallback.
        if input.provider == .cursor {
            let raw = input.snapshot?.identity(for: .cursor)?.accountID
            let accountID = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !accountID.isEmpty {
                return accountID.split(separator: "|").last.map(String.init) ?? accountID
            }
        }
        if input.metadata.usesAccountFallback || input.accountIsAuthoritative,
           let email = input.account.email, !email.isEmpty
        {
            return email
        }
        return ""
    }

    private static func plan(
        for provider: UsageProvider,
        snapshot: UsageSnapshot?,
        account: AccountInfo,
        override: PlanOverride,
        metadata: ProviderMetadata) -> String?
    {
        if case let .label(label) = override {
            return label.flatMap { $0.isEmpty ? nil : $0 }
        }
        if provider == .kiro,
           let plan = kiroPlan(snapshot: snapshot)
        {
            return plan
        }
        if provider == .kilo {
            guard let pass = self.kiloLoginPass(snapshot: snapshot) else {
                return nil
            }
            return self.planDisplay(pass, for: provider)
        }
        if let plan = snapshot?.loginMethod(for: provider), !plan.isEmpty {
            return self.planDisplay(plan, for: provider)
        }
        if metadata.usesAccountFallback,
           let plan = account.plan, !plan.isEmpty
        {
            return Self.planDisplay(plan, for: provider)
        }
        return nil
    }

    private static func planDisplay(_ text: String, for provider: UsageProvider) -> String {
        if provider == .minimax {
            return self.miniMaxPlanDisplay(text)
        }
        let cleaned = if provider == .codex {
            CodexPlanFormatting.displayName(text) ?? UsageFormatter.cleanPlanName(text)
        } else {
            UsageFormatter.cleanPlanName(text)
        }
        return cleaned.isEmpty ? text : cleaned
    }

    private static func miniMaxPlanDisplay(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()
        if normalized.contains("tokenplanplus") || normalized.contains("token plan plus") {
            return "Plus"
        }
        if normalized.contains("tokenplanmax") || normalized.contains("token plan max") {
            return "Max"
        }
        if normalized.contains("tokenplanultra") || normalized.contains("token plan ultra") {
            return "Ultra"
        }
        return trimmed
    }

    private static func kiloLoginPass(snapshot: UsageSnapshot?) -> String? {
        self.kiloLoginParts(snapshot: snapshot).pass
    }

    static func kiloLoginDetails(snapshot: UsageSnapshot?) -> [String] {
        self.kiloLoginParts(snapshot: snapshot).details
    }

    private static func kiloLoginParts(snapshot: UsageSnapshot?) -> (pass: String?, details: [String]) {
        guard let loginMethod = snapshot?.loginMethod(for: .kilo) else {
            return (nil, [])
        }
        let parts = loginMethod
            .components(separatedBy: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else {
            return (nil, [])
        }
        let first = parts[0]
        if self.isKiloActivitySegment(first) {
            return (nil, parts)
        }
        return (first, Array(parts.dropFirst()))
    }

    private static func isKiloActivitySegment(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("auto top-up:")
    }

    private static func subtitle(
        snapshot: UsageSnapshot?,
        isRefreshing: Bool,
        lastError: String?,
        hasLastKnownUsage: Bool,
        now: Date) -> (text: String, style: SubtitleStyle)
    {
        if let lastError, !lastError.isEmpty {
            let message = lastError.trimmingCharacters(in: .whitespacesAndNewlines)
            return (message, .error)
        }

        if isRefreshing {
            return ("\(L("Refreshing"))…", .loading)
        }

        if hasLastKnownUsage {
            return ("", .info)
        }

        if let updated = snapshot?.updatedAt {
            return (UsageFormatter.updatedString(from: updated, now: now), .info)
        }

        return (L("Not fetched yet"), .info)
    }

    private struct RedactedText {
        let email: String
        let subtitleText: String
        let creditsHintText: String?
        let creditsHintCopyText: String?
    }

    private static func redactedText(
        input: Input,
        subtitle: (text: String, style: SubtitleStyle)) -> RedactedText
    {
        let email = PersonalInfoRedactor.redactAccountLabel(
            Self.email(from: input),
            isEnabled: input.hidePersonalInfo,
            ordinal: input.accountPrivacyOrdinal)
        let subtitleText = PersonalInfoRedactor.redactEmails(in: subtitle.text, isEnabled: input.hidePersonalInfo)
            ?? subtitle.text
        let creditsHintText = PersonalInfoRedactor.redactEmails(
            in: Self.dashboardHint(error: input.dashboardError),
            isEnabled: input.hidePersonalInfo)
        let creditsHintCopyText = Self.creditsHintCopyText(
            dashboardError: input.dashboardError,
            hidePersonalInfo: input.hidePersonalInfo)
        return RedactedText(
            email: email,
            subtitleText: subtitleText,
            creditsHintText: creditsHintText,
            creditsHintCopyText: creditsHintCopyText)
    }

    private static func creditsHintCopyText(dashboardError: String?, hidePersonalInfo: Bool) -> String? {
        guard let dashboardError, !dashboardError.isEmpty else { return nil }
        return hidePersonalInfo ? "" : dashboardError
    }

    private static func metrics(input: Input) -> [Metric] {
        guard let snapshot = input.snapshot else { return [] }
        if input.provider == .antigravity {
            return Self.antigravityMetrics(input: input, snapshot: snapshot)
        }
        var metrics: [Metric] = []
        let percentStyle: PercentStyle = input.usageBarsShowUsed ? .used : .left
        let labels = Self.rateWindowLabels(input: input, snapshot: snapshot)
        if input.provider == .mistral, let credits = snapshot.mistralUsage?.credits {
            metrics.append(Metric(
                id: "mistral-balance",
                title: L("Balance"),
                percent: 0,
                percentStyle: percentStyle,
                statusText: credits.formattedAvailableAmount,
                resetText: nil,
                detailText: nil,
                detailLeftText: nil,
                detailRightText: nil,
                pacePercent: nil,
                paceOnTop: true))
        }
        if input.provider == .codex, let codexProjection = input.codexProjection {
            metrics.append(contentsOf: Self.codexRateMetrics(
                input: input,
                projection: codexProjection,
                percentStyle: percentStyle))
        } else if let primary = snapshot.primary?.measured {
            metrics.append(Self.primaryMetric(
                input: input,
                primary: primary,
                bindingProjection: Self.bindingQuotaProjection(
                    input: input,
                    primary: primary,
                    snapshot: snapshot),
                percentStyle: percentStyle,
                title: labels.primary))
        }
        if input.provider != .codex, let weekly = snapshot.secondary {
            metrics.append(Self.secondaryMetric(
                input: input,
                weekly: weekly,
                percentStyle: percentStyle,
                title: labels.secondary))
        }
        if labels.showsTertiary, let opus = snapshot.tertiary {
            var tertiaryDetailText: String?
            if input.provider == .alibaba || input.provider == .alibabatokenplan,
               let detail = opus.resetDescription,
               !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                tertiaryDetailText = detail
            }
            // Perplexity purchased credits don't reset; show balance without "Resets" prefix.
            let opusResetText: String? = input.provider == .perplexity || input.provider == .sub2api
                ? opus.resetDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
                : Self.resetText(for: opus, style: input.resetTimeDisplayStyle, now: input.now)
            let tertiaryPaceDetail = Self.resetWindowPaceDetail(window: opus, input: input)
            metrics.append(Metric(
                id: "tertiary",
                title: labels.tertiary,
                percent: Self.clamped(input.usageBarsShowUsed ? opus.usedPercent : opus.remainingPercent),
                percentStyle: percentStyle,
                resetText: opusResetText,
                detailText: tertiaryDetailText,
                detailLeftText: tertiaryPaceDetail?.leftLabel,
                detailRightText: tertiaryPaceDetail?.rightLabel,
                pacePercent: tertiaryPaceDetail?.pacePercent,
                detailIsPaceDerived: tertiaryPaceDetail?.isPaceDerived ?? false,
                paceWillLastToReset: tertiaryPaceDetail?.willLastToReset,
                paceOnTop: tertiaryPaceDetail?.paceOnTop ?? true,
                warningMarkerPercents: Self.warningMarkerPercents(
                    thresholds: input.quotaWarningThresholds[.weekly],
                    showUsed: input.usageBarsShowUsed)))
        }
        metrics.append(contentsOf: Self.extraRateWindowMetrics(
            snapshot: snapshot,
            input: input,
            percentStyle: percentStyle))
        if input.provider == .kilo || input.provider == .kimi,
           metrics.contains(where: { $0.id == "primary" }),
           metrics.contains(where: { $0.id == "secondary" })
        {
            metrics.sort { lhs, rhs in
                let primarySecondaryOrder: [String: Int] = [
                    "secondary": 0,
                    "primary": 1,
                ]
                return (primarySecondaryOrder[lhs.id] ?? Int.max) < (primarySecondaryOrder[rhs.id] ?? Int.max)
            }
        }

        if let codexProjection = input.codexProjection,
           codexProjection.supplementalMetrics.contains(.codeReview),
           let remaining = codexProjection.remainingPercent(for: .codeReview)
        {
            let percent = input.usageBarsShowUsed ? (100 - remaining) : remaining
            let resetText = codexProjection.limitWindow(for: .codeReview).flatMap {
                Self.resetText(for: $0, style: input.resetTimeDisplayStyle, now: input.now)
            }
            metrics.append(Metric(
                id: "code-review",
                title: L("Code review"),
                percent: Self.clamped(percent),
                percentStyle: percentStyle,
                resetText: resetText,
                detailText: nil,
                detailLeftText: nil,
                detailRightText: nil,
                pacePercent: nil,
                paceOnTop: true))
        }
        return Self.blockingQuotaMetrics(metrics, input: input, snapshot: snapshot)
    }

    private static func primaryMetric(
        input: Input,
        primary: RateWindow,
        bindingProjection: RateWindowBindingQuotaProjection? = nil,
        percentStyle: PercentStyle,
        title: String? = nil) -> Metric
    {
        var presentation = PrimaryMetricPresentation(
            resetText: Self.resetText(for: primary, style: input.resetTimeDisplayStyle, now: input.now),
            detailText: nil)
        Self.applyPrimaryQuotaPresentation(
            &presentation,
            input: input,
            primary: primary)
        Self.applyPrimaryBalancePresentation(&presentation, input: input, primary: primary)
        Self.applyPrimaryResetPresentation(&presentation, input: input, primary: primary)
        if bindingProjection == nil {
            Self.applyPrimaryPacePresentation(&presentation, input: input, primary: primary)
        }
        Self.applyPrimaryFinalOverrides(&presentation, input: input, primary: primary)
        // Provider-specific by design: z.ai's textual 5-hour reset phrase is provider-owned copy localized here.
        if input.provider == .zai, let resetText = Self.localizedZaiPeriodicResetText(primary) {
            presentation.resetText = resetText
        }
        if let bindingProjection {
            let resetWindow = RateWindow(
                usedPercent: bindingProjection.usedPercent,
                windowMinutes: primary.windowMinutes,
                resetsAt: bindingProjection.resetsAt,
                resetDescription: bindingProjection.resetDescription)
            presentation.resetText = Self.resetText(
                for: resetWindow,
                style: input.resetTimeDisplayStyle,
                now: input.now)
        }
        let displayedUsedPercent = bindingProjection?.usedPercent ?? primary.usedPercent
        return Metric(
            id: "primary",
            title: title ?? L(input.metadata.sessionLabel),
            percent: Self.clamped(input.usageBarsShowUsed ? displayedUsedPercent : 100 - displayedUsedPercent),
            percentStyle: percentStyle,
            statusText: presentation.statusText,
            resetText: presentation.resetText,
            detailText: presentation.detailText,
            detailLeftText: presentation.detailLeft,
            detailRightText: presentation.detailRight,
            pacePercent: presentation.pacePercent,
            detailIsPaceDerived: presentation.detailIsPaceDerived,
            paceWillLastToReset: presentation.paceWillLastToReset,
            paceOnTop: presentation.paceOnTop,
            warningMarkerPercents: Self.warningMarkerPercents(
                thresholds: input.quotaWarningThresholds[
                    input.provider == .cursor && input.snapshot
                        .flatMap(CursorProviderDescriptor.sharedWeeklyPool) != nil
                        ? .weekly : .session,
                ],
                showUsed: input.usageBarsShowUsed),
            sessionEquivalentDetail: Self.sessionEquivalentDetail(
                input: input,
                weeklyWindow: primary,
                weeklyWindowID: nil))
    }

    private static func secondaryMetric(
        input: Input,
        weekly: RateWindow,
        percentStyle: PercentStyle,
        title: String? = nil) -> Metric
    {
        // Kimi's secondary slot is its 5-hour rate limit rather than a weekly window.
        var paceDetail = if input.provider == .kimi {
            Self.sessionPaceDetail(
                provider: input.provider,
                window: weekly,
                now: input.now,
                showUsed: input.usageBarsShowUsed)
        } else {
            Self.weeklyPaceDetail(
                provider: input.provider,
                window: weekly,
                now: input.now,
                pace: input.weeklyPace,
                showUsed: input.usageBarsShowUsed)
        }
        let presentation = ProviderDescriptorRegistry.descriptor(for: input.provider).presentation
        var weeklyResetText = Self.resetText(for: weekly, style: input.resetTimeDisplayStyle, now: input.now)
        var weeklyDetailText: String?
        if input.provider == .warp,
           let detail = weekly.resetDescription,
           !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            weeklyResetText = nil
            weeklyDetailText = detail
        }
        if presentation.menuCard.showsSecondaryBalanceDescription,
           let detail = weekly.resetDescription,
           !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            weeklyDetailText = detail
            if weekly.resetsAt == nil {
                weeklyResetText = nil
            }
        }
        if input.provider == .sub2api {
            weeklyResetText = weekly.resetDescription
        }
        if input.provider == .kiro,
           let remainingText = input.snapshot?.detailRow(label: "Bonus credits left")?.value,
           let totalText = input.snapshot?.detailRow(label: "Bonus credits left")?.secondaryValue?
               .split(separator: "·", maxSplits: 1)
               .first?
               .trimmingCharacters(in: .whitespacesAndNewlines)
               .replacingOccurrences(of: "of ", with: "")
        {
            paceDetail = PaceDetail(
                leftLabel: String(format: L("%@ of %@ bonus credits left"), remainingText, totalText),
                rightLabel: nil,
                pacePercent: nil,
                paceOnTop: true)
        }
        if input.provider == .alibaba || input.provider == .alibabatokenplan,
           let detail = weekly.resetDescription,
           !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            weeklyDetailText = detail
        }
        if [.copilot, .zenmux].contains(input.provider),
           let detail = weekly.resetDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !detail.isEmpty
        {
            paceDetail = PaceDetail(leftLabel: detail, rightLabel: nil, pacePercent: nil, paceOnTop: true)
        }
        if input.provider == .zenmux, weekly.resetsAt == nil {
            weeklyResetText = nil
        }
        if let cursorPaceDetail = Self.resetWindowPaceDetail(
            window: weekly,
            input: input,
            pace: input.weeklyPace)
        {
            paceDetail = cursorPaceDetail
        }
        // Perplexity bonus credits don't reset; show balance without "Resets" prefix.
        if input.provider == .perplexity,
           let detail = weekly.resetDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !detail.isEmpty
        {
            weeklyResetText = detail
        }
        if input.provider == .synthetic,
           let regen = Self.syntheticRegenDetail(
               weekly: weekly,
               cost: input.snapshot?.providerCost,
               now: input.now,
               showUsed: input.usageBarsShowUsed)
        {
            weeklyResetText = regen.resetText
            paceDetail = regen.pace
        }
        return Metric(
            id: "secondary",
            title: title ?? L(input.metadata.weeklyLabel),
            percent: Self.clamped(input.usageBarsShowUsed ? weekly.usedPercent : weekly.remainingPercent),
            percentStyle: percentStyle,
            statusText: nil,
            resetText: weeklyResetText,
            detailText: weeklyDetailText,
            detailLeftText: paceDetail?.leftLabel,
            detailRightText: paceDetail?.rightLabel,
            pacePercent: paceDetail?.pacePercent,
            detailIsPaceDerived: paceDetail?.isPaceDerived ?? false,
            paceWillLastToReset: paceDetail?.willLastToReset,
            paceOnTop: paceDetail?.paceOnTop ?? true,
            warningMarkerPercents: Self.warningMarkerPercents(
                thresholds: input.quotaWarningThresholds[.weekly],
                showUsed: input.usageBarsShowUsed),
            workdayMarkerPercents: input.workdayTickAppearance == .hidden
                ? []
                : workDayMarkerPercents(
                    workDays: input.workDaysPerWeek,
                    windowMinutes: weekly.windowMinutes),
            workdayTickAppearance: input.workdayTickAppearance,
            sessionEquivalentDetail: Self.sessionEquivalentDetail(
                input: input,
                weeklyWindow: weekly,
                weeklyWindowID: nil))
    }
}

extension UsageMenuCardView.Model {
    fileprivate static func trackedAccountIdentityFingerprint(input: Input) -> String? {
        let accountID = input.snapshot?.identity(for: input.provider.instanceID)?.accountID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let email = Self.email(from: input)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedAccountID = accountID?.isEmpty == false ? accountID : nil
        guard !email.isEmpty || normalizedAccountID != nil else { return nil }
        return UsageStore.sha256Hex(
            "OpenBar.tracked-account:\(input.provider.rawValue):\(normalizedAccountID ?? ""):\(email)")
    }
}
