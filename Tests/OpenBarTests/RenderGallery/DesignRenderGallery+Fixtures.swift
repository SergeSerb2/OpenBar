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
    }

    /// Three providers that cover the normal, warning, and critical tones.
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
            primaryResetIn: 47 * 60,
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
            isStale: true),
    ]

    static func snapshot(_ fixture: Provider) -> UsageSnapshot {
        UsageSnapshot(
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

    static func menuCardModel(_ fixture: Provider, width _: CGFloat = 310) -> UsageMenuCardView.Model? {
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
            lastError: nil,
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
}
