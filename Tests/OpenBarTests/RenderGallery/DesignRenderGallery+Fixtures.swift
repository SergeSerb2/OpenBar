import Foundation
import OpenBarCore
@testable import OpenBar

/// Synthetic data for the render gallery. Values are fictitious and stable, so renders diff cleanly.
@MainActor
enum GalleryFixtures {
    /// Fixed clock: 2026-10-24 10:00 local, so countdowns render the same on every run.
    static let now = Date(timeIntervalSince1970: 1_792_861_200)

    struct Provider {
        let provider: UsageProvider
        let email: String
        let plan: String
        let primaryUsed: Double
        let primaryResetIn: TimeInterval
        let secondaryUsed: Double?
        let secondaryResetIn: TimeInterval
        let todayCost: Double?
        let todayTokens: Int?
        let monthCost: Double?
        let monthTokens: Int?
        let isStale: Bool
        var lastError: String?
        var extraUsage: ProviderCostSnapshot?
    }

    /// Three providers that cover the normal, warning, and critical tones. Codex's session runs
    /// ahead of its pace, so its card shows the "runs out" pace line.
    static let providers: [Provider] = [
        Provider(
            provider: .claude,
            email: "alex@example.com",
            plan: "Max",
            primaryUsed: 38,
            primaryResetIn: 2 * 3600 + 14 * 60,
            secondaryUsed: 59,
            secondaryResetIn: 3 * 86400 + 4 * 3600,
            todayCost: 4.12,
            todayTokens: 1_240_000,
            monthCost: 88.40,
            monthTokens: 31_200_000,
            isStale: false),
        Provider(
            provider: .codex,
            email: "alex@example.com",
            plan: "Pro",
            primaryUsed: 82,
            primaryResetIn: 2 * 3600 + 10 * 60,
            secondaryUsed: 47,
            secondaryResetIn: 5 * 86400 + 2 * 3600,
            todayCost: 2.06,
            todayTokens: 640_000,
            monthCost: 41.75,
            monthTokens: 14_800_000,
            isStale: false),
        Provider(
            provider: .cursor,
            email: "sam@example.com",
            plan: "Pro",
            primaryUsed: 94,
            primaryResetIn: 9 * 86400,
            secondaryUsed: nil,
            secondaryResetIn: 0,
            todayCost: nil,
            todayTokens: nil,
            monthCost: nil,
            monthTokens: nil,
            isStale: false),
        Provider(
            provider: .gemini,
            email: "sam@example.com",
            plan: "Pro",
            primaryUsed: 40,
            primaryResetIn: 6 * 3600,
            secondaryUsed: 52,
            secondaryResetIn: 4 * 86400,
            todayCost: nil,
            todayTokens: nil,
            monthCost: nil,
            monthTokens: nil,
            isStale: true),
    ]

    /// A long provider name and plan, for localization and truncation checks.
    static let longName = Provider(
        provider: .alibabatokenplan,
        email: "alexandra.longname@example-enterprise.com",
        plan: "Coding Plan Pro",
        primaryUsed: 64,
        primaryResetIn: 4 * 3600 + 40 * 60,
        secondaryUsed: 81,
        secondaryResetIn: 6 * 86400 + 3 * 3600,
        todayCost: nil,
        todayTokens: nil,
        monthCost: nil,
        monthTokens: nil,
        isStale: false)

    /// A long Claude menu: an error subline, extra usage, and cost, to check the menu's height.
    static let longClaude = Provider(
        provider: .claude,
        email: "alex@example.com",
        plan: "Max",
        primaryUsed: 76,
        primaryResetIn: 3 * 3600 + 5 * 60,
        secondaryUsed: 88,
        secondaryResetIn: 2 * 86400 + 6 * 3600,
        todayCost: 6.48,
        todayTokens: 2_310_000,
        monthCost: 131.20,
        monthTokens: 47_900_000,
        isStale: false,
        lastError: "Claude Code credentials changed. Click Refresh to read the new sign-in; "
            + "the last successful usage stays visible until then.",
        extraUsage: ProviderCostSnapshot(
            used: 18.40,
            limit: 50,
            currencyCode: "USD",
            period: "Monthly",
            updatedAt: Date(timeIntervalSince1970: 1_792_861_200)))

    static func snapshot(_ fixture: Provider) -> UsageSnapshot {
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: fixture.primaryUsed,
                windowMinutes: fixture.provider == .cursor ? 43200 : 300,
                resetsAt: self.now.addingTimeInterval(fixture.primaryResetIn),
                resetDescription: nil),
            secondary: fixture.secondaryUsed.map {
                RateWindow(
                    usedPercent: $0,
                    windowMinutes: 10080,
                    resetsAt: self.now.addingTimeInterval(fixture.secondaryResetIn),
                    resetDescription: nil)
            },
            updatedAt: fixture.isStale ? self.now.addingTimeInterval(-3 * 3600) : self.now.addingTimeInterval(-60))
        guard let extraUsage = fixture.extraUsage else { return snapshot }
        return snapshot.with(providerCost: extraUsage)
    }

    static func tokenSnapshot(_ fixture: Provider) -> CostUsageTokenSnapshot? {
        guard let todayTokens = fixture.todayTokens else { return nil }
        return CostUsageTokenSnapshot(
            sessionTokens: todayTokens,
            sessionCostUSD: fixture.todayCost,
            last30DaysTokens: fixture.monthTokens,
            last30DaysCostUSD: fixture.monthCost,
            costProvenance: .listPriceEstimate,
            daily: [],
            updatedAt: self.now)
    }

    /// A provider that has not fetched yet: the empty card state.
    static func emptyModel(_ provider: UsageProvider) -> UsageMenuCardView.Model? {
        guard let metadata = ProviderDefaults.metadata[provider] else { return nil }
        return UsageMenuCardView.Model.make(.init(
            provider: provider,
            metadata: metadata,
            snapshot: nil,
            credits: nil,
            creditsError: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            quotaWarningThresholds: [:],
            now: self.now))
    }

    static func menuCardModel(_ fixture: Provider) -> UsageMenuCardView.Model? {
        guard let metadata = ProviderDefaults.metadata[fixture.provider] else { return nil }
        let snapshot = self.snapshot(fixture)
        return UsageMenuCardView.Model.make(.init(
            provider: fixture.provider,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboardError: nil,
            tokenSnapshot: self.tokenSnapshot(fixture),
            tokenError: nil,
            account: AccountInfo(email: fixture.email, plan: fixture.plan),
            lastKnownUsageCapturedAt: fixture.isStale ? snapshot.updatedAt : nil,
            isRefreshing: false,
            lastError: fixture.lastError,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: fixture.todayTokens != nil,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            quotaWarningThresholds: [:],
            now: self.now))
    }

    /// Remaining percentage of the secondary (weekly) lane, as the switcher strip shows it.
    static func weeklyRemaining(_ provider: UsageProvider) -> Double? {
        guard let fixture = self.providers.first(where: { $0.provider == provider }) else { return 72 }
        return fixture.secondaryUsed.map { 100 - $0 } ?? (100 - fixture.primaryUsed)
    }

    // MARK: Compact account rows

    /// Six claude-swap style accounts: one active, the rest spread across healthy, warning,
    /// critical, and unavailable, as the compact multi-account layout shows them.
    static func compactAccounts() -> [ProviderAccountUsageSnapshot] {
        struct Row {
            let label: String
            var active = false
            let session: Double?
            let weekly: Double?
            var error: String?
        }
        let rows = [
            Row(label: "alex@example.com", active: true, session: 38, weekly: 59),
            Row(label: "alex@work.example", session: 93, weekly: 61),
            Row(label: "sam@example.com", session: 81, weekly: 70),
            Row(label: "pat@example.com", session: 12, weekly: 20),
            Row(label: "lee@example.com", session: 8, weekly: 15),
            Row(label: "kim@example.com", session: nil, weekly: nil, error: "Token expired"),
        ]
        return rows.enumerated().map { index, row in
            let primary = row.session.map {
                RateWindow(
                    usedPercent: $0,
                    windowMinutes: 300,
                    resetsAt: self.now.addingTimeInterval(Double(index + 1) * 1800),
                    resetDescription: nil)
            }
            let secondary = row.weekly.map {
                RateWindow(
                    usedPercent: $0,
                    windowMinutes: 10080,
                    resetsAt: self.now.addingTimeInterval(Double(index + 2) * 86400),
                    resetDescription: nil)
            }
            let snapshot: UsageSnapshot? = row.error == nil
                ? UsageSnapshot(primary: primary, secondary: secondary, updatedAt: self.now, identity: nil)
                : nil
            return ProviderAccountUsageSnapshot(
                id: ProviderAccountIdentity(source: "claude-swap", opaqueID: String(index + 1)),
                provider: .claude,
                displayLabel: row.label,
                isActive: row.active,
                canActivate: row.error == nil,
                snapshot: snapshot,
                error: row.error,
                sourceLabel: "claude-swap")
        }
    }
}
