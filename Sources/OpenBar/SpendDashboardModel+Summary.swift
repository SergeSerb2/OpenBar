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
            hourly: self.snapshot.hourly,
            updatedAt: self.snapshot.updatedAt)
        snapshot.reportingPeriod = self.snapshot.reportingPeriod
        // Activity values carry their own coverage bounds, and accounting decides Pi inclusion; both stay.
        // The native projection is read only from store publications, so the summary drops it.
        return Self(
            id: self.id,
            provider: self.provider,
            displayName: self.displayName,
            modelProviderName: self.modelProviderName,
            snapshot: snapshot,
            tokenActivityCache: self.tokenActivityCache,
            sourceKind: self.sourceKind,
            accounting: self.accounting?.withoutNativeProjection)
    }
}
