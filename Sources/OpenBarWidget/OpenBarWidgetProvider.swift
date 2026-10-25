import AppIntents
import OpenBarCore
import SwiftUI
import WidgetKit

enum ProviderChoice: String, AppEnum {
    case codex
    case claude
    case gemini
    case alibaba
    case alibabatokenplan
    case qwencloud
    case antigravity
    case cursor
    case zai
    case copilot
    case devin
    case minimax
    case kilo
    case opencode
    case opencodego
    case mistral
    case kimi
    case deepseek
    case openrouter
    case pi

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Provider")

    /// AppIntents extracts this metadata statically; it must stay a literal, exhaustive
    /// dictionary. WidgetProviderChoiceTests pins these titles to the descriptor registry.
    /// Provider-specific by design: AppIntents requires a compile-time provider display inventory.
    static let caseDisplayRepresentations: [ProviderChoice: DisplayRepresentation] = [
        .codex: DisplayRepresentation(title: "Codex"),
        .claude: DisplayRepresentation(title: "Claude"),
        .gemini: DisplayRepresentation(title: "Gemini"),
        .alibaba: DisplayRepresentation(title: "Alibaba"),
        .alibabatokenplan: DisplayRepresentation(title: "Alibaba Token Plan"),
        .qwencloud: DisplayRepresentation(title: "Qwen Cloud"),
        .antigravity: DisplayRepresentation(title: "Antigravity"),
        .cursor: DisplayRepresentation(title: "Cursor"),
        .zai: DisplayRepresentation(title: "z.ai / GLM"),
        .copilot: DisplayRepresentation(title: "Copilot"),
        .devin: DisplayRepresentation(title: "Devin"),
        .minimax: DisplayRepresentation(title: "MiniMax"),
        .kilo: DisplayRepresentation(title: "Kilo"),
        .opencode: DisplayRepresentation(title: "OpenCode"),
        .opencodego: DisplayRepresentation(title: "OpenCode Go"),
        .mistral: DisplayRepresentation(title: "Mistral"),
        .kimi: DisplayRepresentation(title: "Kimi Code"),
        .deepseek: DisplayRepresentation(title: "DeepSeek"),
        .openrouter: DisplayRepresentation(title: "OpenRouter"),
        .pi: DisplayRepresentation(title: "Pi"),
    ]

    var provider: UsageProvider {
        UsageProvider(rawValue: self.rawValue)!
    }

    init?(provider: UsageProvider) {
        guard ProviderDescriptorRegistry.descriptor(for: provider).metadata.widgetSelectable else { return nil }
        self.init(rawValue: provider.rawValue)
    }
}

enum CompactMetric: String, AppEnum {
    case credits
    case todayCost
    case last30DaysCost

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Metric")

    static let caseDisplayRepresentations: [CompactMetric: DisplayRepresentation] = [
        .credits: DisplayRepresentation(title: "Credits left"),
        .todayCost: DisplayRepresentation(title: "Today cost"),
        .last30DaysCost: DisplayRepresentation(title: "Cost"),
    ]
}

struct ProviderSelectionIntent: AppIntent, WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Provider"
    static let description = IntentDescription("Select the provider to display in the widget.")

    @Parameter(title: "Provider", default: .codex)
    var provider: ProviderChoice

    init() {
        self.provider = .codex
    }
}

struct SwitchWidgetProviderIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch Provider"
    static let description = IntentDescription("Switch the provider shown in the widget.")

    @Parameter(title: "Provider")
    var provider: ProviderChoice

    init() {}

    init(provider: ProviderChoice) {
        self.provider = provider
    }

    func perform() async throws -> some IntentResult {
        WidgetSelectionStore.saveSelectedProvider(self.provider.provider)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct CompactMetricSelectionIntent: AppIntent, WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Provider + Metric"
    static let description = IntentDescription("Select the provider and metric to display.")

    @Parameter(title: "Provider", default: .codex)
    var provider: ProviderChoice

    @Parameter(title: "Metric", default: .credits)
    var metric: CompactMetric

    init() {
        self.provider = .codex
        self.metric = .credits
    }
}

struct OpenBarWidgetEntry: TimelineEntry {
    let date: Date
    let provider: UsageProvider
    let snapshot: WidgetSnapshot
}

struct OpenBarCompactEntry: TimelineEntry {
    let date: Date
    let provider: UsageProvider
    let metric: CompactMetric
    let snapshot: WidgetSnapshot
}

struct OpenBarSwitcherEntry: TimelineEntry {
    let date: Date
    let provider: UsageProvider
    let availableProviders: [UsageProvider]
    let snapshot: WidgetSnapshot
}

struct OpenBarTimelineProvider: AppIntentTimelineProvider {
    /// The Usage, History, and Accounts widgets share this provider but read different parts of the
    /// snapshot.
    var payload: WidgetEntryPayload.Kind = .usage

    func placeholder(in context: Context) -> OpenBarWidgetEntry {
        OpenBarWidgetEntry(
            date: Date(),
            provider: .codex,
            snapshot: WidgetPreviewData.snapshot())
    }

    func snapshot(for configuration: ProviderSelectionIntent, in context: Context) async -> OpenBarWidgetEntry {
        let provider = configuration.provider.provider
        return OpenBarWidgetEntry(
            date: Date(),
            provider: provider,
            snapshot: self.payload.pruned(
                WidgetSnapshotStore.load() ?? WidgetPreviewData.snapshot(),
                provider: provider,
                family: context.family))
    }

    func timeline(
        for configuration: ProviderSelectionIntent,
        in context: Context) async -> Timeline<OpenBarWidgetEntry>
    {
        let provider = configuration.provider.provider
        let snapshot = WidgetSnapshotStore.load() ?? WidgetPreviewData.emptySnapshot()
        let now = Date()
        // Schedule against the full snapshot, then keep only what this widget kind draws.
        let refresh = BurnDownRefreshSchedule.nextRefresh(snapshot: snapshot, provider: provider, now: now)
        let entry = OpenBarWidgetEntry(
            date: now,
            provider: provider,
            snapshot: self.payload.pruned(snapshot, provider: provider, family: context.family))
        return Timeline(entries: [entry], policy: .after(refresh))
    }
}

struct OpenBarSwitcherTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> OpenBarSwitcherEntry {
        let snapshot = WidgetPreviewData.snapshot()
        let providers = Self.supportedProviders(from: snapshot)
        return OpenBarSwitcherEntry(
            date: Date(),
            provider: providers.first ?? .codex,
            availableProviders: providers,
            snapshot: snapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (OpenBarSwitcherEntry) -> Void) {
        completion(self.makeEntry(family: context.family).entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OpenBarSwitcherEntry>) -> Void) {
        let (entry, refresh) = self.makeEntry(family: context.family)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func makeEntry(family: WidgetFamily) -> (entry: OpenBarSwitcherEntry, refresh: Date) {
        let snapshot = WidgetSnapshotStore.load() ?? WidgetPreviewData.emptySnapshot()
        let providers = Self.supportedProviders(from: snapshot)
        let stored = WidgetSelectionStore.loadSelectedProvider()
        let selected = providers.first { $0.instanceID == stored } ?? providers.first ?? .codex
        if selected.instanceID != stored {
            WidgetSelectionStore.saveSelectedProvider(selected)
        }
        let now = Date()
        let refresh = BurnDownRefreshSchedule.nextRefresh(snapshot: snapshot, provider: selected, now: now)
        let entry = OpenBarSwitcherEntry(
            date: now,
            provider: selected,
            availableProviders: providers,
            snapshot: WidgetEntryPayload.Kind.usage.pruned(snapshot, provider: selected, family: family))
        return (entry, refresh)
    }

    static func supportedProviders(from snapshot: WidgetSnapshot) -> [UsageProvider] {
        let enabled = snapshot.enabledProviders
        let instanceIDs = enabled.isEmpty ? snapshot.entries.map(\.provider) : enabled
        let supported = instanceIDs.compactMap { instanceID -> UsageProvider? in
            guard let provider = instanceID.firstPartyProvider, ProviderChoice(provider: provider) != nil else {
                return nil
            }
            return provider
        }
        return supported.isEmpty ? [.codex] : supported
    }
}

struct OpenBarCompactTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> OpenBarCompactEntry {
        OpenBarCompactEntry(
            date: Date(),
            provider: .codex,
            metric: .credits,
            snapshot: WidgetPreviewData.snapshot())
    }

    func snapshot(for configuration: CompactMetricSelectionIntent, in context: Context) async -> OpenBarCompactEntry {
        let provider = configuration.provider.provider
        let metric = configuration.metric
        return OpenBarCompactEntry(
            date: Date(),
            provider: provider,
            metric: metric,
            snapshot: WidgetEntryPayload.Kind.compact.pruned(
                WidgetSnapshotStore.load() ?? WidgetPreviewData.snapshot(),
                provider: provider,
                family: context.family))
    }

    func timeline(
        for configuration: CompactMetricSelectionIntent,
        in context: Context) async -> Timeline<OpenBarCompactEntry>
    {
        let provider = configuration.provider.provider
        let metric = configuration.metric
        let snapshot = WidgetSnapshotStore.load() ?? WidgetPreviewData.emptySnapshot()
        let entry = OpenBarCompactEntry(
            date: Date(),
            provider: provider,
            metric: metric,
            snapshot: WidgetEntryPayload.Kind.compact.pruned(snapshot, provider: provider, family: context.family))
        let refresh = Date().addingTimeInterval(30 * 60)
        return Timeline(entries: [entry], policy: .after(refresh))
    }
}

// MARK: - Entry payloads

/// Per-kind budgets for what a timeline entry carries.
///
/// WidgetKit keeps timeline entries in the widget host's memory, and the shared snapshot holds every
/// enabled provider with a month of daily history. Each widget kind keeps only what its views read:
/// the configured provider (or its accounts), at most the days its family draws, and no detail
/// sections. Pruning happens after the refresh schedule is computed, and the persisted shared
/// snapshot is never modified.
enum WidgetEntryPayload {
    enum Kind {
        /// Usage, switcher, and account usage tiles: one provider; history only on large (7 days).
        case usage
        /// History widget: one provider, two weeks of history.
        case history
        /// Accounts widget: the provider's saved accounts, no history.
        case accounts
        /// Compact metric and burn-down widgets: one provider, no history.
        case compact

        func pruned(_ snapshot: WidgetSnapshot, provider: UsageProvider, family: WidgetFamily) -> WidgetSnapshot {
            switch self {
            case .usage:
                WidgetEntryPayload.pruned(
                    snapshot,
                    provider: provider,
                    dailyPoints: family == .systemLarge ? WidgetTileSize.largeHistoryDays : 0)
            case .history:
                WidgetEntryPayload.pruned(snapshot, provider: provider, dailyPoints: WidgetEntryPayload.historyDays)
            case .accounts:
                WidgetEntryPayload.pruned(
                    snapshot,
                    provider: provider,
                    dailyPoints: 0,
                    keepsEntries: false,
                    keepsAccounts: true)
            case .compact:
                WidgetEntryPayload.pruned(snapshot, provider: provider, dailyPoints: 0)
            }
        }
    }

    /// Days of history the History widget draws.
    static let historyDays = 14

    static func pruned(
        _ snapshot: WidgetSnapshot,
        provider: UsageProvider,
        dailyPoints: Int,
        keepsEntries: Bool = true,
        keepsAccounts: Bool = false,
        accountID: String? = nil) -> WidgetSnapshot
    {
        let instanceID = provider.instanceID
        let entries = keepsEntries
            ? snapshot.entries.filter { $0.provider == instanceID }.map { self.pruned($0, dailyPoints: dailyPoints) }
            : []
        let accounts = keepsAccounts
            ? snapshot.accounts
            .filter { $0.provider == instanceID && (accountID == nil || $0.id == accountID) }
            .map { account in
                WidgetSnapshot.AccountEntry(
                    id: account.id,
                    provider: account.provider,
                    label: account.label,
                    usage: account.usage.map { self.pruned($0, dailyPoints: 0) })
            }
            : []
        return WidgetSnapshot(
            entries: entries,
            accounts: accounts,
            accountOverflowCounts: keepsAccounts
                ? snapshot.accountOverflowCounts.filter { $0.key == instanceID.rawValue }
                : [:],
            enabledProviders: snapshot.enabledProviders,
            usageBarsShowUsed: snapshot.usageBarsShowUsed,
            generatedAt: snapshot.generatedAt)
    }

    static func pruned(_ entry: WidgetSnapshot.ProviderEntry, dailyPoints: Int) -> WidgetSnapshot.ProviderEntry {
        WidgetSnapshot.ProviderEntry(
            instanceID: entry.provider,
            updatedAt: entry.updatedAt,
            primary: entry.primary,
            secondary: entry.secondary,
            tertiary: entry.tertiary,
            usageRows: entry.usageRows,
            creditsRemaining: entry.creditsRemaining,
            codeReviewRemainingPercent: entry.codeReviewRemainingPercent,
            tokenUsage: entry.tokenUsage,
            dailyUsage: Array(entry.dailyUsage.suffix(max(0, dailyPoints))),
            providerCost: entry.providerCost,
            quotaOwnerKey: entry.quotaOwnerKey,
            balanceText: entry.balanceText,
            details: nil)
    }
}

enum WidgetPreviewData {
    static func emptySnapshot() -> WidgetSnapshot {
        WidgetSnapshot(entries: [], enabledProviders: [], generatedAt: Date())
    }

    static func snapshot() -> WidgetSnapshot {
        let now = Date()
        let primary = RateWindow(
            usedPercent: 35,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(4 * 3600),
            resetDescription: "Resets in 4h")
        let secondary = RateWindow(
            usedPercent: 60,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(3 * 86400),
            resetDescription: "Resets in 3d")
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .codex,
            updatedAt: now,
            primary: primary,
            secondary: secondary,
            tertiary: nil,
            creditsRemaining: 1243.4,
            codeReviewRemainingPercent: 78,
            tokenUsage: WidgetSnapshot.TokenUsageSummary(
                sessionCostUSD: 12.4,
                sessionTokens: 420_000,
                last30DaysCostUSD: 923.8,
                last30DaysTokens: 12_400_000),
            dailyUsage: [
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-01", totalTokens: 120_000, costUSD: 15.2),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-02", totalTokens: 80000, costUSD: 10.1),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-03", totalTokens: 140_000, costUSD: 17.9),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-04", totalTokens: 90000, costUSD: 11.4),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-05", totalTokens: 160_000, costUSD: 19.8),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-06", totalTokens: 70000, costUSD: 8.9),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-07", totalTokens: 110_000, costUSD: 13.7),
            ])
        return WidgetSnapshot(entries: [entry], generatedAt: now)
    }
}
