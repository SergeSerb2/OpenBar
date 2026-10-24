import Foundation
import OpenBarCore

extension UsageStore {
    struct OpenAIDashboardRefreshContext {
        let targetEmail: String?
        let allowCurrentSnapshotFallback: Bool
        let expectedGuard: CodexAccountScopedRefreshGuard?
        let refreshTaskToken: UUID
        let allowCodexUsageBackfill: Bool
        let force: Bool
    }

    func applyOpenAIDashboardAndScheduleSubscriptionEnrichment(
        _ dashboard: OpenAIDashboardSnapshot,
        targetEmail: String?,
        context: OpenAIDashboardRefreshContext) async
    {
        if await self.applyOpenAIDashboard(
            dashboard,
            targetEmail: targetEmail,
            expectedGuard: context.expectedGuard,
            refreshTaskToken: context.refreshTaskToken,
            allowCodexUsageBackfill: context.allowCodexUsageBackfill)
        {
            self.scheduleOpenAISubscriptionMetadataEnrichment(
                dashboard: dashboard,
                targetEmail: targetEmail,
                expectedGuard: context.expectedGuard,
                force: context.force)
        }
    }

    /// Attaches metadata from a dashboard that has already passed the Codex authority check.
    @discardableResult
    func applyOpenAIDashboardSubscriptionMetadata(
        _ dashboard: OpenAIDashboardSnapshot) -> Bool
    {
        // Provider-specific by design: authorized OpenAI dashboard metadata attaches only to the active Codex snapshot.
        guard let currentUsage = self.snapshots[.codex] else { return false }

        let updatedUsage = currentUsage.withSubscriptionMetadata(
            expiresAt: dashboard.subscriptionExpiresAt,
            renewsAt: dashboard.subscriptionRenewsAt)
        self.snapshots[.codex] = updatedUsage
        let didChange = updatedUsage.subscriptionExpiresAt != currentUsage.subscriptionExpiresAt ||
            updatedUsage.subscriptionRenewsAt != currentUsage.subscriptionRenewsAt
        if didChange {
            self.persistWidgetSnapshot(reason: "dashboard-subscription-metadata")
        }
        return didChange
    }

    func scheduleOpenAISubscriptionMetadataEnrichment(
        dashboard: OpenAIDashboardSnapshot,
        targetEmail: String?,
        expectedGuard: CodexAccountScopedRefreshGuard?,
        force: Bool = false)
    {
        guard self.startupBehavior.automaticallyStartsBackgroundWork ||
            self._test_openAISubscriptionMetadataLoaderOverride != nil else { return }
        self.openAISubscriptionMetadataEnrichmentTask?.cancel()
        let token = UUID()
        self.openAISubscriptionMetadataEnrichmentToken = token
        let expectedGuard = expectedGuard ?? self.currentCodexOpenAIWebRefreshGuard()
        let cacheScope = self.codexCookieCacheScopeForOpenAIWeb()
        let allowBillingPageFallback = self.takeOpenAISubscriptionBillingFallbackAllowance(force: force)
        let log: (String) -> Void = { [weak self] line in self?.logOpenAIWeb(line) }
        self.openAISubscriptionMetadataEnrichmentTask = Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.openAISubscriptionMetadataEnrichmentToken == token {
                    self.openAISubscriptionMetadataEnrichmentTask = nil
                    self.openAISubscriptionMetadataEnrichmentToken = nil
                }
            }
            let result: OpenAISubscriptionFetchResult = if let override = self
                ._test_openAISubscriptionMetadataLoaderOverride
            {
                await override(targetEmail)
            } else {
                await OpenAIDashboardFetcher().fetchSubscriptionMetadata(
                    accountEmail: targetEmail,
                    cacheScope: cacheScope,
                    allowBillingPageFallback: allowBillingPageFallback,
                    logger: log)
            }
            await self.applyOpenAISubscriptionMetadataEnrichment(
                result,
                dashboard: dashboard,
                targetEmail: targetEmail,
                expectedGuard: expectedGuard,
                token: token)
        }
    }

    /// The billing fallback hydrates chatgpt.com in a hidden WebView (usage page, then billing page), so it gets the
    /// same budget as the dashboard page scrape: once per page-scrape interval, unless the user forces a refresh.
    /// The allowance is used when granted, so an account whose subscription API keeps failing cannot retry it on
    /// every refresh.
    private func takeOpenAISubscriptionBillingFallbackAllowance(force: Bool) -> Bool {
        let now = Date()
        let allowed = Self.shouldAllowOpenAISubscriptionBillingFallback(
            force: force,
            userInitiated: ProviderInteractionContext.current == .userInitiated,
            lastFallbackAt: self.lastOpenAISubscriptionBillingFallbackAt,
            now: now,
            refreshInterval: max(
                self.openAIWebRefreshIntervalSeconds(),
                Self.openAIDashboardPageScrapeMinimumInterval))
        if allowed {
            self.lastOpenAISubscriptionBillingFallbackAt = now
        }
        return allowed
    }

    nonisolated static func shouldAllowOpenAISubscriptionBillingFallback(
        force: Bool,
        userInitiated: Bool,
        lastFallbackAt: Date?,
        now: Date,
        refreshInterval: TimeInterval) -> Bool
    {
        if force, userInitiated {
            return true
        }
        guard let lastFallbackAt else { return true }
        return now.timeIntervalSince(lastFallbackAt) >= refreshInterval
    }

    private func applyOpenAISubscriptionMetadataEnrichment(
        _ result: OpenAISubscriptionFetchResult,
        dashboard: OpenAIDashboardSnapshot,
        targetEmail: String?,
        expectedGuard: CodexAccountScopedRefreshGuard,
        token: UUID) async
    {
        // Provider-specific by design: optional OpenAI billing work requires active Codex web access.
        guard !Task.isCancelled,
              self.isEnabled(.codex),
              self.settings.openAIWebAccessEnabled,
              self.settings.codexCookieSource.isEnabled,
              self.openAISubscriptionMetadataEnrichmentToken == token,
              result.succeeded
        else { return }
        // The captured dates belong to this accepted dashboard, not a later same-email refresh.
        guard self.openAIDashboardAttachmentAuthorized, self.openAIDashboard == dashboard else {
            self.logOpenAIWeb("subscription metadata enrichment skipped: dashboard changed")
            return
        }
        let enrichedDashboard = dashboard.withSubscriptionMetadata(result.metadata)
        let authority = self.evaluateCodexDashboardAuthority(
            dashboard: enrichedDashboard,
            sourceKind: .liveWeb,
            routingTargetEmail: targetEmail)
        guard authority.decision.disposition == .attach,
              authority.decision.allowedEffects.contains(.subscriptionMetadataAttachment)
        else {
            self.logOpenAIWeb("subscription metadata enrichment skipped: authority=\(authority.decision.disposition)")
            return
        }
        if !self.shouldApplyOpenAIDashboardRefreshGuard(
            expectedGuard: expectedGuard,
            routingTargetEmail: targetEmail)
        {
            self.logOpenAIWeb("subscription metadata enrichment skipped: refresh guard changed")
            return
        }
        self.openAIDashboard = enrichedDashboard
        self.lastOpenAIDashboardSnapshot = enrichedDashboard
        let didPersist = self.applyOpenAIDashboardSubscriptionMetadata(enrichedDashboard)
        self
            .logOpenAIWeb(
                "subscription metadata enrichment \(didPersist ? "persisted" : "unchanged"): authority=attach")
        if let attachedEmail = self.codexDashboardAttachmentEmail(from: authority.input), !attachedEmail.isEmpty {
            OpenAIDashboardCacheStore.save(OpenAIDashboardCache(
                accountEmail: attachedEmail,
                snapshot: enrichedDashboard))
        }
    }
}
