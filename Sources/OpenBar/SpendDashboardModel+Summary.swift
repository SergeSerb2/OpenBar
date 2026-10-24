import OpenBarCore

extension SpendDashboardModel.ProviderInput {
    func summaryOnly() -> Self {
        var snapshot = CostUsageTokenSnapshot(
            sessionTokens: self.snapshot.sessionTokens,
            sessionCostUSD: self.snapshot.sessionCostUSD,
            sessionRequests: self.snapshot.sessionRequests,
            last30DaysTokens: self.snapshot.last30DaysTokens,
            last30DaysCostUSD: self.snapshot.last30DaysCostUSD,
            last30DaysRequests: self.snapshot.last30DaysRequests,
            currencyCode: self.snapshot.currencyCode,
            historyDays: self.snapshot.historyDays,
            historyCoverageIsEstablished: self.snapshot.historyCoverageIsEstablished,
            historyScanIsPartial: self.snapshot.historyScanIsPartial,
            historyLabel: self.snapshot.historyLabel,
            meteredCostUSD: self.snapshot.meteredCostUSD,
            costProvenance: self.snapshot.costProvenance,
            credentialScopeFingerprint: self.snapshot.credentialScopeFingerprint,
            daily: self.snapshot.daily,
            updatedAt: self.snapshot.updatedAt)
        snapshot.reportingPeriod = self.snapshot.reportingPeriod
        return Self(
            id: self.id,
            provider: self.provider,
            displayName: self.displayName,
            modelProviderName: self.modelProviderName,
            snapshot: snapshot,
            sourceKind: self.sourceKind)
    }
}
