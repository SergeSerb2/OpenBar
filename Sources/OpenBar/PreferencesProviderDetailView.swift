import OpenBarCore
import SwiftUI

enum ProviderMetricInlinePresentation: Equatable {
    case progress
    case status(String)
}

@MainActor
struct ProviderDetailView<SupplementaryContent: View>: View {
    private struct ModelLimitsIdentity: Hashable {
        let id: String
        let scope: ProviderModelRateLimitScope?
    }

    let provider: UsageProvider
    @Bindable var store: UsageStore
    @Binding var isEnabled: Bool
    let subtitle: String
    let model: UsageMenuCardView.Model
    let accountUsageOverview: ProviderAccountUsageOverview?
    let usageItems: [ProviderUsageItemDescriptor]
    let openAIWebDiagnostic: String?
    let settingsPickers: [ProviderSettingsPickerDescriptor]
    let settingsToggles: [ProviderSettingsToggleDescriptor]
    let settingsFields: [ProviderSettingsFieldDescriptor]
    let settingsModelLimits: [ProviderSettingsModelLimitsDescriptor]
    let settingsDirectoryLists: [ProviderSettingsDirectoryListDescriptor]
    let settingsActions: [ProviderSettingsActionsDescriptor]
    let settingsTokenAccounts: ProviderSettingsTokenAccountsDescriptor?
    let settingsOrganizations: ProviderSettingsOrganizationsDescriptor?
    let errorDisplay: ProviderErrorDisplay?
    @Binding var isErrorExpanded: Bool
    let onCopyError: (String) -> Void
    let onRefresh: () -> Void
    let supplementarySettingsContent: SupplementaryContent
    let showsSupplementarySettingsContent: Bool

    init(
        provider: UsageProvider,
        store: UsageStore,
        isEnabled: Binding<Bool>,
        subtitle: String,
        model: UsageMenuCardView.Model,
        accountUsageOverview: ProviderAccountUsageOverview? = nil,
        usageItems: [ProviderUsageItemDescriptor] = [],
        openAIWebDiagnostic: String?,
        settingsPickers: [ProviderSettingsPickerDescriptor],
        settingsToggles: [ProviderSettingsToggleDescriptor],
        settingsFields: [ProviderSettingsFieldDescriptor],
        settingsDirectoryLists: [ProviderSettingsDirectoryListDescriptor] = [],
        settingsModelLimits: [ProviderSettingsModelLimitsDescriptor] = [],
        settingsActions: [ProviderSettingsActionsDescriptor] = [],
        settingsTokenAccounts: ProviderSettingsTokenAccountsDescriptor?,
        settingsOrganizations: ProviderSettingsOrganizationsDescriptor? = nil,
        errorDisplay: ProviderErrorDisplay?,
        isErrorExpanded: Binding<Bool>,
        onCopyError: @escaping (String) -> Void,
        onRefresh: @escaping () -> Void,
        showsSupplementarySettingsContent: Bool = false,
        @ViewBuilder supplementarySettingsContent: () -> SupplementaryContent)
    {
        self.provider = provider
        self.store = store
        self._isEnabled = isEnabled
        self.subtitle = subtitle
        self.model = model
        self.accountUsageOverview = accountUsageOverview
        self.usageItems = usageItems
        self.openAIWebDiagnostic = openAIWebDiagnostic
        self.settingsPickers = settingsPickers
        self.settingsToggles = settingsToggles
        self.settingsFields = settingsFields
        self.settingsDirectoryLists = settingsDirectoryLists
        self.settingsModelLimits = settingsModelLimits
        self.settingsActions = settingsActions
        self.settingsTokenAccounts = settingsTokenAccounts
        self.settingsOrganizations = settingsOrganizations
        self.errorDisplay = errorDisplay
        self._isErrorExpanded = isErrorExpanded
        self.onCopyError = onCopyError
        self.onRefresh = onRefresh
        self.showsSupplementarySettingsContent = showsSupplementarySettingsContent
        self.supplementarySettingsContent = supplementarySettingsContent()
    }

    static func metricTitle(provider: UsageProvider, metric: UsageMenuCardView.Model.Metric) -> String {
        L(UsageMenuCardView.popupMetricTitle(provider: provider, metric: metric))
    }

    static func versionText(provider: UsageProvider, store: UsageStore) -> String? {
        let context = ProviderPresentationContext(
            provider: provider,
            settings: store.settings,
            store: store,
            metadata: store.metadata(for: provider))
        let presentation = ProviderCatalog.implementation(for: provider)?.presentation(context: context)
            ?? ProviderPresentation(detailLine: ProviderPresentation.standardDetailLine)
        guard presentation.showsVersionInSettings else { return nil }
        return store.version(for: provider) ?? L("not detected")
    }

    static func metricInlinePresentation(
        _ metric: UsageMenuCardView.Model.Metric) -> ProviderMetricInlinePresentation
    {
        if let statusText = metric.statusText {
            return .status(statusText)
        }
        return .progress
    }

    static func planRow(provider: UsageProvider, planText: String?) -> (label: String, value: String)? {
        guard let rawPlan = planText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPlan.isEmpty
        else {
            return nil
        }
        let presentation = ProviderDescriptorRegistry.descriptor(for: provider).presentation.planRow
        if presentation.stripsBalancePrefix,
           let value = MenuBarDisplayText.prefixedValue(from: rawPlan, prefix: "Balance:")
        {
            return (label: L(presentation.balancePrefixedLabel), value: value)
        }
        return (label: L(presentation.label), value: rawPlan)
    }

    private var menuBarSettingsPickers: [ProviderSettingsPickerDescriptor] {
        self.settingsPickers.filter { $0.placement == .menuBar }
    }

    private var connectionSettingsPickers: [ProviderSettingsPickerDescriptor] {
        self.settingsPickers.filter { $0.placement == .connection }
    }

    var body: some View {
        Form {
            // The header sits on the window background above the groups, like a System Settings pane hero: it is
            // the header of a section without rows, so the grouped form draws no box around it.
            Section {} header: {
                ProviderDetailHeaderRow(
                    provider: self.provider,
                    store: self.store,
                    isEnabled: self.$isEnabled,
                    subtitle: self.subtitle,
                    onRefresh: self.onRefresh)
                    .foregroundStyle(.primary)
            }

            if let overview = self.accountUsageOverview {
                ProviderAccountUsageOverviewView(
                    provider: self.provider,
                    overview: overview,
                    isEnabled: self.isEnabled)
                if let tokenUsage = self.model.tokenUsage {
                    Section {
                        ProviderTokenUsageInlineView(provider: self.provider, tokenUsage: tokenUsage)
                    } header: {
                        Text(L(self.store.settings.codexLocalSessionCostLedgerEnabled ? "This Mac" : "Local usage"))
                    } footer: {
                        SettingsSectionFooter(L(self.store.settings.codexLocalSessionCostLedgerEnabled
                                ? "Local usage is shared across accounts on this Mac."
                                : "Local usage comes from the current Codex profile."))
                    }
                }
                if let diagnostic = self.openAIWebDiagnostic {
                    Section {
                        Text(diagnostic).font(OpenBarTheme.Fonts.meta).foregroundStyle(.secondary)
                    } header: {
                        Text(L("OpenAI web extras"))
                    }
                }
            } else {
                Section {
                    ProviderMetricsInlineView(
                        provider: self.provider,
                        model: self.model,
                        openAIWebDiagnostic: self.openAIWebDiagnostic,
                        isEnabled: self.isEnabled,
                        isRefreshing: self.store.refreshingProviders.contains(self.provider.instanceID))
                } header: {
                    // The grouped form demotes the header that follows the row-less hero section; keep it a
                    // normal section title.
                    Text(L("Usage"))
                        .settingsHeroFollowingHeader()
                }
            }

            // Source, version, status, and account details follow the usage preview.
            Section {
                ProviderDetailInfoRows(
                    provider: self.provider,
                    store: self.store,
                    isEnabled: self.isEnabled,
                    versionText: Self.versionText(provider: self.provider, store: self.store),
                    model: self.model,
                    showsAccountInfo: self.accountUsageOverview == nil)
            }

            if !self.usageItems.isEmpty {
                ProviderUsageItemVisibilitySettingsView(
                    provider: self.provider,
                    settings: self.store.settings,
                    items: self.usageItems)
            }

            if self.accountUsageOverview == nil, let errorDisplay {
                Section {
                    ProviderErrorView(
                        title: String(
                            format: L("last_fetch_failed_with_provider"),
                            self.store.metadata(for: self.provider).displayName),
                        display: errorDisplay,
                        isExpanded: self.$isErrorExpanded,
                        onCopy: { self.onCopyError(errorDisplay.full) })
                }
            }

            ProviderMenuBarPercentWindowSettingsView(
                provider: self.provider,
                settings: self.store.settings,
                snapshot: self.store.snapshot(for: self.provider.instanceID))

            if !self.menuBarSettingsPickers.isEmpty {
                Section {
                    ForEach(self.menuBarSettingsPickers) { picker in
                        ProviderSettingsPickerRowView(picker: picker)
                    }
                } header: {
                    Text(L("provider_section_menu_bar"))
                }
            }

            if !self.connectionSettingsPickers.isEmpty || !self.settingsActions.isEmpty {
                Section {
                    ForEach(self.connectionSettingsPickers) { picker in
                        ProviderSettingsPickerRowView(picker: picker)
                    }
                    ForEach(self.settingsActions) { descriptor in
                        ProviderSettingsActionsRowView(descriptor: descriptor)
                    }
                } header: {
                    Text(L("provider_section_connection"))
                }
            }

            if let tokenAccounts = self.settingsTokenAccounts,
               tokenAccounts.isVisible?() ?? true
            {
                ProviderSettingsTokenAccountsRowView(descriptor: tokenAccounts)
            }

            ForEach(self.settingsFields) { field in
                ProviderSettingsFieldRowView(field: field)
            }

            ForEach(self.settingsDirectoryLists) { descriptor in
                ProviderSettingsDirectoryListRowView(descriptor: descriptor)
            }

            ForEach(self.settingsModelLimits) { descriptor in
                ProviderSettingsModelLimitsRowView(descriptor: descriptor)
                    .id(ModelLimitsIdentity(id: descriptor.id, scope: descriptor.scope))
            }

            if let organizations = self.settingsOrganizations {
                ProviderSettingsOrganizationsRowView(descriptor: organizations)
            }

            if self.showsSupplementarySettingsContent {
                self.supplementarySettingsContent
            }

            ProviderAccentColorSettingsView(provider: self.provider, settings: self.store.settings)

            ProviderQuotaWarningSettingsView(provider: self.provider, settings: self.store.settings)

            if !self.settingsToggles.isEmpty {
                Section {
                    ForEach(self.settingsToggles) { toggle in
                        ProviderSettingsToggleRowView(toggle: toggle)
                    }
                } header: {
                    Text(L("Options"))
                }
            }
        }
        .settingsPaneForm()
    }
}

@MainActor
struct ProviderUsageItemVisibilitySettingsView: View {
    let provider: UsageProvider
    @Bindable var settings: SettingsStore
    let items: [ProviderUsageItemDescriptor]

    var body: some View {
        Section {
            ForEach(self.items) { item in
                Toggle(
                    isOn: Binding(
                        get: { self.settings.isUsageItemVisible(item.id, for: self.provider) },
                        set: { isVisible in
                            self.settings.setUsageItemVisible(
                                isVisible,
                                itemID: item.id,
                                for: self.provider)
                        })) {
                    VStack(alignment: .leading) {
                        Text(item.title)
                        if item.requiresOptionalUsage, !self.settings.showOptionalCreditsAndExtraUsage {
                            Text(L("Hidden by the global optional credits, spending & billing setting."))
                                .font(OpenBarTheme.Fonts.meta)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
            }

            Button(L("Restore Defaults")) {
                self.settings.restoreDefaultUsageItemVisibility(for: self.provider)
            }
            .disabled(!self.settings.hasCustomUsageItemVisibility(for: self.provider))
        } header: {
            Text(L("Visible usage items"))
        } footer: {
            SettingsSectionFooter(L(
                "Choose which usage rows appear in this provider's menu, Settings preview, and Overview."))
        }
    }
}

@MainActor
struct ProviderDetailHeaderRow: View {
    let provider: UsageProvider
    @Bindable var store: UsageStore
    @Binding var isEnabled: Bool
    let subtitle: String
    let onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: OpenBarSpacing.section) {
            ProviderDetailBrandIcon(provider: self.provider)

            VStack(alignment: .leading, spacing: OpenBarSpacing.hairline) {
                Text(self.store.metadata(for: self.provider).displayName)
                    .font(OpenBarTheme.Fonts.title)
                    .lineLimit(1)

                Text(self.detailSubtitle)
                    .font(OpenBarTheme.Fonts.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer(minLength: OpenBarSpacing.section)

            Button {
                self.onRefresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(L("Refresh"))
            .accessibilityLabel(L("Refresh"))

            Toggle(L("Enabled"), isOn: self.$isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    private var detailSubtitle: String {
        let lines = self.subtitle.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 2 else { return self.subtitle }
        let first = lines[0]
        let rest = lines.dropFirst().joined(separator: "\n")
        let tail = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        if tail.isEmpty {
            return String(first)
        }
        return "\(first) • \(tail)"
    }
}

@MainActor
private struct ProviderDetailBrandIcon: View {
    let provider: UsageProvider

    /// 24-pt template logo on a 40-pt card-fill tile (docs/design §9.4).
    var body: some View {
        Group {
            if let brand = ProviderBrandIcon.image(for: self.provider) {
                Image(nsImage: brand)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "circle.dotted")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(
            width: OpenBarSettingsMetrics.providerHeaderLogoSize,
            height: OpenBarSettingsMetrics.providerHeaderLogoSize)
        .foregroundStyle(.primary)
        .frame(
            width: OpenBarSettingsMetrics.providerHeaderTileSize,
            height: OpenBarSettingsMetrics.providerHeaderTileSize)
        .background(SettingsFillBackground(shape: RoundedRectangle(
            cornerRadius: OpenBarRadius.rail,
            style: .continuous)))
        .accessibilityHidden(true)
    }
}

@MainActor
struct ProviderDetailInfoRows: View {
    let provider: UsageProvider
    @Bindable var store: UsageStore
    let isEnabled: Bool
    let versionText: String?
    let model: UsageMenuCardView.Model
    var showsAccountInfo: Bool = true
    @Environment(\.settingsPreviewNow) private var previewNow

    var body: some View {
        if self.showsAccountInfo {
            ProviderDetailInfoRow(label: L("Source"), value: self.store.sourceLabel(for: self.provider))
        }
        if let versionText {
            ProviderDetailInfoRow(label: L("Version"), value: versionText)
        }
        if self.showsAccountInfo {
            ProviderDetailInfoRow(label: L("Updated"), value: self.updatedText)
        }

        if let status = self.store.status(for: self.provider) {
            ProviderDetailInfoRow(label: L("Status"), value: status.description ?? status.indicator.label)
        }

        if self.showsAccountInfo, !self.model.email.isEmpty {
            ProviderDetailInfoRow(label: L("Account"), value: self.model.email)
        }

        // Provider-specific by design: Kiro reports an auth method as a separate identity field, not a plan.
        if self.provider == .kiro,
           let authMethod = self.store.snapshot(for: self.provider.instanceID)?.loginMethod(for: .kiro),
           !authMethod.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            ProviderDetailInfoRow(label: L("Auth"), value: authMethod)
        }

        if self.showsAccountInfo, let planRow = ProviderDetailView<EmptyView>.planRow(
            provider: self.provider,
            planText: self.model.planText)
        {
            ProviderDetailInfoRow(label: planRow.label, value: planRow.value)
        }
    }

    private var updatedText: String {
        if let updated = self.store.snapshot(for: self.provider.instanceID)?.updatedAt {
            return UsageFormatter.updatedString(from: updated, now: self.previewNow ?? Date())
        }
        if self.store.refreshingProviders.contains(self.provider.instanceID) {
            return L("Refreshing")
        }
        if self.store.unavailableMessage(for: self.provider) != nil {
            return L("Unavailable")
        }
        return L("Not fetched yet")
    }
}

private struct ProviderDetailInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent(self.label) {
            Text(self.value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
}

@MainActor
struct ProviderMetricsInlineView: View {
    let provider: UsageProvider
    let model: UsageMenuCardView.Model
    let openAIWebDiagnostic: String?
    let isEnabled: Bool
    let isRefreshing: Bool

    struct InfoRow: Identifiable, Equatable {
        enum ID: Hashable {
            case credits
            case openAIWeb
        }

        let id: ID
        let label: String
        let value: String
    }

    struct ContentState: Equatable {
        let hasMetrics: Bool
        let hasUsageNotes: Bool
        let hasProviderCost: Bool
        let hasInfoRows: Bool
        let hasTokenUsage: Bool
        let hasResetCredits: Bool
        let hasCloudCredits: Bool
        let hasProviderDetails: Bool

        init(model: UsageMenuCardView.Model, infoRows: [InfoRow]) {
            self.hasMetrics = !model.metrics.isEmpty
            self.hasUsageNotes = !model.usageNotes.isEmpty
            self.hasProviderCost = model.providerCost?.showsInProviderDetails == true
            self.hasInfoRows = !infoRows.isEmpty
            self.hasTokenUsage = model.tokenUsage != nil
            self.hasResetCredits = model.limitResetCredits != nil
            self.hasCloudCredits = model.cloudCredits != nil
            self.hasProviderDetails = !model.providerDetails.isEmpty
        }

        var showsPlaceholder: Bool {
            !self.hasMetrics &&
                !self.hasUsageNotes &&
                !self.hasProviderCost &&
                !self.hasInfoRows &&
                !self.hasTokenUsage &&
                !self.hasResetCredits &&
                !self.hasCloudCredits &&
                !self.hasProviderDetails
        }
    }

    static func infoRows(
        for model: UsageMenuCardView.Model,
        openAIWebDiagnostic: String?) -> [InfoRow]
    {
        var rows: [InfoRow] = []
        if let credits = model.creditsText {
            rows.append(InfoRow(id: .credits, label: L("Credits"), value: credits))
        }
        if let diagnostic = openAIWebDiagnostic {
            rows.append(InfoRow(id: .openAIWeb, label: L("OpenAI web extras"), value: diagnostic))
        }
        return rows
    }

    var body: some View {
        let infoRows = Self.infoRows(for: self.model, openAIWebDiagnostic: self.openAIWebDiagnostic)
        let contentState = ContentState(model: self.model, infoRows: infoRows)

        if contentState.showsPlaceholder {
            Text(self.placeholderText)
                .font(OpenBarTheme.Fonts.meta)
                .foregroundStyle(.secondary)
        } else {
            if contentState.hasMetrics {
                // Lanes use the menu card anatomy, two per row when the form is wide enough.
                ProviderUsageLaneLayout(columnSpacing: OpenBarSpacing.page, rowSpacing: OpenBarSpacing.section) {
                    ForEach(self.model.metrics, id: \.id) { metric in
                        ProviderMetricInlineRow(
                            metric: metric,
                            title: ProviderDetailView<EmptyView>.metricTitle(provider: self.provider, metric: metric),
                            progressColor: self.model.progressColor)
                    }
                }
                .padding(.vertical, OpenBarSpacing.hairline)
            }

            if contentState.hasUsageNotes {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(self.model.usageNotes.enumerated()), id: \.offset) { _, note in
                        Text(note)
                            .font(OpenBarTheme.Fonts.meta)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            ForEach(infoRows) { row in
                ProviderDetailInfoRow(label: row.label, value: row.value)
            }

            if let resetCredits = self.model.limitResetCredits {
                ProviderLimitResetCreditsInlineRow(presentation: resetCredits)
            }

            if let cloudCredits = self.model.cloudCredits {
                ProviderMetricInlineTextRow(title: cloudCredits.title, value: cloudCredits.spendLine)
            }

            if let providerCost = self.model.providerCost, providerCost.showsInProviderDetails {
                ProviderMetricInlineCostRow(
                    section: providerCost,
                    progressColor: self.model.progressColor)
            }

            if let tokenUsage = self.model.tokenUsage {
                ProviderTokenUsageInlineView(provider: self.model.provider, tokenUsage: tokenUsage)
            }

            if contentState.hasProviderDetails {
                ProviderDetailSectionsContent(
                    sections: self.model.providerDetails,
                    chartColor: self.model.progressColor)
            }
        }
    }

    private var placeholderText: String {
        Self.placeholderText(
            isEnabled: self.isEnabled,
            isRefreshing: self.isRefreshing,
            modelPlaceholder: self.model.placeholder)
    }

    static func placeholderText(
        isEnabled: Bool,
        isRefreshing: Bool,
        modelPlaceholder: String?) -> String
    {
        if !isEnabled {
            return L("Disabled — no recent data")
        }
        if isRefreshing {
            return L("Refreshing")
        }
        return modelPlaceholder.map(L) ?? L("No usage yet")
    }
}

struct ProviderTokenUsageInlineView: View {
    let provider: UsageProvider
    let tokenUsage: UsageMenuCardView.Model.TokenUsageSection

    var body: some View {
        ProviderMetricInlineTextRow(
            title: UsageMenuCardView.Model.tokenUsageHeader(provider: self.provider),
            value: self.tokenUsage.sessionLine)
        ProviderMetricInlineTextRow(title: "", value: self.tokenUsage.monthLine)
        if ProviderDescriptorRegistry.descriptor(for: self.provider).tokenCost.showsHintInProviderDetails,
           let hint = self.tokenUsage.hintLine, !hint.isEmpty
        {
            ProviderMetricInlineTextRow(title: "", value: hint)
        }
    }
}

/// One usage lane in the menu card anatomy (docs/design §9.2): title and value, the meter, then reset and pace.
/// A low lane shows its tone symbol and color on the value; the meter keeps the provider color.
private struct ProviderMetricInlineRow: View {
    let metric: UsageMenuCardView.Model.Metric
    let title: String
    let progressColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: OpenBarMenuMetrics.laneInnerSpacing) {
            switch ProviderDetailView<EmptyView>.metricInlinePresentation(self.metric) {
            case let .status(statusText):
                HStack(alignment: .firstTextBaseline, spacing: OpenBarSpacing.regular) {
                    Text(self.title)
                        .font(OpenBarTheme.Fonts.laneTitle)
                        .lineLimit(1)
                    Spacer(minLength: OpenBarSpacing.regular)
                    Text(statusText)
                        .font(OpenBarTheme.Fonts.meta)
                        .foregroundStyle(.secondary)
                }
            case .progress:
                HStack(alignment: .firstTextBaseline, spacing: OpenBarSpacing.regular) {
                    Text(self.title)
                        .font(OpenBarTheme.Fonts.laneTitle)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: OpenBarSpacing.regular)
                    self.valueLabel
                }

                UsageProgressBar(
                    percent: self.metric.percent,
                    tint: self.progressColor,
                    accessibilityLabel: self.metric.percentStyle.accessibilityLabel,
                    pacePercent: self.metric.pacePercent,
                    paceOnTop: self.metric.paceOnTop,
                    warningMarkerPercents: self.metric.warningMarkerPercents,
                    workdayMarkerPercents: self.metric.workdayMarkerPercents,
                    workdayTickAppearance: self.metric.workdayTickAppearance)
                    .frame(maxWidth: .infinity)

                let presentation = self.metric.linePresentation(title: self.title)
                if presentation.resetText != nil || presentation.metaText != nil {
                    // Reset left and pace right when both fit; otherwise they stack and wrap instead of truncating.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: OpenBarSpacing.regular) {
                            self.detailTexts(presentation, stacked: false)
                        }
                        VStack(alignment: .leading, spacing: OpenBarSpacing.hairline) {
                            self.detailTexts(presentation, stacked: true)
                        }
                    }
                    .font(OpenBarTheme.Fonts.meta)
                    .foregroundStyle(.secondary)
                }

                if let detail = self.metric.detailText, !detail.isEmpty {
                    Text(detail)
                        .font(OpenBarTheme.Fonts.meta)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func detailTexts(
        _ presentation: UsageMenuCardView.Model.Metric.LinePresentation,
        stacked: Bool) -> some View
    {
        if let resetText = presentation.resetText {
            Text(resetText)
                .lineLimit(stacked ? nil : 1)
                .fixedSize(horizontal: !stacked, vertical: true)
        }
        if !stacked {
            Spacer(minLength: OpenBarSpacing.regular)
        }
        if let metaText = presentation.metaText {
            Text(metaText)
                .lineLimit(stacked ? nil : 1)
                .fixedSize(horizontal: !stacked, vertical: true)
        }
    }

    private var tone: OpenBarQuotaTone {
        guard !self.metric.isSyntheticCreditLane else { return .normal }
        let remaining = self.metric.percentStyle == .left ? self.metric.percent : 100 - self.metric.percent
        return OpenBarQuotaTone.resolve(remainingPercent: remaining, isStale: false)
    }

    @ViewBuilder
    private var valueLabel: some View {
        let tone = self.tone
        HStack(alignment: .firstTextBaseline, spacing: OpenBarSpacing.tight) {
            if tone == .warning || tone == .critical, let symbol = tone.symbolName {
                Image(systemName: symbol)
                    .font(OpenBarTheme.Fonts.meta)
                    .accessibilityHidden(true)
            }
            Text(self.metric.percentLabel)
                .font(OpenBarTheme.Fonts.laneValue)
                .lineLimit(1)
        }
        .foregroundStyle(OpenBarTheme.Colors.tone(tone) ?? Color.primary)
    }
}

/// Places usage lanes two per row when each lane can be at least `minimumLaneWidth` wide, otherwise one per row.
/// A layout rather than `ViewThatFits`, so each lane and its meter is built once.
private struct ProviderUsageLaneLayout: Layout {
    var columnSpacing: CGFloat
    var rowSpacing: CGFloat
    var minimumLaneWidth: CGFloat = 220

    private func columns(for width: CGFloat, count: Int) -> Int {
        count >= 2 && width >= self.minimumLaneWidth * 2 + self.columnSpacing ? 2 : 1
    }

    private func laneWidth(for width: CGFloat, columns: Int) -> CGFloat {
        columns == 2 ? (width - self.columnSpacing) / 2 : width
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? self.minimumLaneWidth * 2 + self.columnSpacing
        let columns = self.columns(for: width, count: subviews.count)
        let laneWidth = self.laneWidth(for: width, columns: columns)
        var height: CGFloat = 0
        for rowStart in stride(from: 0, to: subviews.count, by: columns) {
            let row = subviews[rowStart..<min(rowStart + columns, subviews.count)]
            let rowHeight = row.map { $0.sizeThatFits(ProposedViewSize(width: laneWidth, height: nil)).height }
                .max() ?? 0
            height += rowHeight + (rowStart == 0 ? 0 : self.rowSpacing)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = self.columns(for: bounds.width, count: subviews.count)
        let laneWidth = self.laneWidth(for: bounds.width, columns: columns)
        var y = bounds.minY
        for rowStart in stride(from: 0, to: subviews.count, by: columns) {
            let row = Array(subviews[rowStart..<min(rowStart + columns, subviews.count)])
            let laneProposal = ProposedViewSize(width: laneWidth, height: nil)
            let rowHeight = row.map { $0.sizeThatFits(laneProposal).height }.max() ?? 0
            for (column, subview) in row.enumerated() {
                let x = bounds.minX + CGFloat(column) * (laneWidth + self.columnSpacing)
                subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: laneProposal)
            }
            y += rowHeight + self.rowSpacing
        }
    }
}

private struct ProviderLimitResetCreditsInlineRow: View {
    let presentation: LimitResetCreditsPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: OpenBarMenuMetrics.laneInnerSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L("Limit Reset Credits"))
                    .font(OpenBarTheme.Fonts.laneTitle)
                Spacer(minLength: 8)
                Text(self.presentation.text)
                    .font(OpenBarTheme.Fonts.meta)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "clock")
                    .font(OpenBarTheme.Fonts.caption)
                Text(self.presentation.expirySummaryText)
                    .font(OpenBarTheme.Fonts.meta)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(self.presentation.accessibilityLabel)
    }
}

private struct ProviderMetricInlineTextRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if !self.title.isEmpty {
                Text(self.title)
                    .font(OpenBarTheme.Fonts.laneTitle)
            }
            Spacer(minLength: 8)
            Text(self.value)
                .font(OpenBarTheme.Fonts.meta)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct ProviderMetricInlineCostRow: View {
    let section: UsageMenuCardView.Model.ProviderCostSection
    let progressColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: OpenBarMenuMetrics.laneInnerSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(self.section.title)
                    .font(OpenBarTheme.Fonts.laneTitle)
                Spacer(minLength: 8)
                if let percentLine = self.section.percentLine {
                    Text(percentLine)
                        .font(OpenBarTheme.Fonts.meta)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if let percentUsed = self.section.percentUsed {
                UsageProgressBar(
                    percent: percentUsed,
                    tint: self.progressColor,
                    accessibilityLabel: L("Usage used"))
                    .frame(maxWidth: .infinity)
            }

            Text(self.section.spendLine)
                .font(OpenBarTheme.Fonts.meta)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}
