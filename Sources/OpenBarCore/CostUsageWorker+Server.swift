import Foundation

extension CostUsageWorker {
    package static func serve() async -> Int32 {
        do {
            var input = Data()
            while let chunk = try FileHandle.standardInput.read(upToCount: 64 * 1024), !chunk.isEmpty {
                guard input.count + chunk.count <= self.maximumRequestBytes else { throw WorkerError.protocolFailure }
                input.append(chunk)
            }
            let request = try PropertyListDecoder().decode(CostUsageWorkerRequest.self, from: input)
            guard request.version == 1 else { throw WorkerError.protocolFailure }
            let jobs = CostUsageScanExecutor.LockedState<[CostUsageWorkerPricingJob]>([])
            let result = await self.$isWorker.withValue(true) {
                await self.$pricingJobs.withValue(jobs) {
                    try? await self.execute(request)
                }
            }
            let response = CostUsageWorkerResponse(
                version: request.version,
                generation: request.generation,
                result: result,
                pricingJobs: jobs.withLock { $0 })
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(response)
            guard data.count <= self.maximumResponseBytes else { throw WorkerError.protocolFailure }
            try FileHandle.standardOutput.write(contentsOf: data)
            return 0
        } catch {
            return 1
        }
    }

    private static func encoded(_ value: some Codable) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(CostUsageWorkerValue(value: value))
    }

    private static func execute(_ request: CostUsageWorkerRequest) async throws -> Data {
        let options = request.scanner.options
        let fetcher = CostUsageFetcher(scannerOptions: options)
        switch request.operation {
        case .tokens:
            return try await self.encoded(CostUsageFetcher.loadTokenResult(
                provider: request.provider,
                environment: request.environment,
                antigravityAdditionalProfileHomes: request.antigravityAdditionalProfileHomes,
                now: request.now,
                forceRefresh: request.forceRefresh,
                allowVertexClaudeFallback: request.allowVertexClaudeFallback,
                codexHomePath: request.codexHomePath,
                historyDays: request.historyDays,
                allowPricingRefresh: request.allowPricingRefresh,
                refreshPricingInBackground: request.refreshPricingInBackground,
                includePiSessions: request.includePiSessions,
                bypassScannerDebounce: request.bypassScannerDebounce,
                piWorkingDirectories: request.piWorkingDirectories,
                piSessionProcessContexts: request.piSessionProcessContexts,
                scannerOptions: options,
                retryUnknownPricing: request.retryUnknownPricing,
                reportContext: request.reportContext,
                includeNativeProjection: request.includeNativeProjection))
        case .cachedSnapshot:
            return try await self.encoded(CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
                now: request.now,
                codexHomePath: request.codexHomePath,
                historyDays: request.historyDays,
                allowScopedCodexHome: request.allowScopedCodexHome,
                includePiSessions: request.includePiSessions,
                includeProjectAndSessionBreakdowns: request.includeProjectAndSessionBreakdowns,
                requireCompleteHistory: request.requireCompleteHistory,
                scannerOptions: options,
                environment: request.environment,
                includeNativeProjection: request.includeNativeProjection))
        case .cachedActivity:
            return try await self.encoded(CostUsageFetcher.loadCachedCodexTokenActivity(
                now: request.now,
                codexHomePath: request.codexHomePath,
                maximumDays: request.historyDays,
                scannerOptions: options))
        case .status:
            return try await self.encoded(fetcher.codexScanCatchUpStatus(
                codexHomePath: request.codexHomePath,
                historyDays: request.statusHistoryDays,
                now: request.now))
        case .advance:
            return try await self.encoded(self.advance(request, fetcher: fetcher))
        case .cachedProjects:
            return try await self.encoded(fetcher.loadCachedCodexLocalProjectUsageSnapshot(
                now: request.now,
                codexHomePath: request.codexHomePath,
                historyDays: request.historyDays,
                hidePersonalInfo: request.hidePersonalInfo))
        case .projects:
            return try await self.encoded(fetcher.loadCodexLocalProjectUsageSnapshot(
                now: request.now,
                forceRefresh: request.forceRefresh,
                codexHomePath: request.codexHomePath,
                historyDays: request.historyDays,
                hidePersonalInfo: request.hidePersonalInfo))
        }
    }

    private static func advance(
        _ request: CostUsageWorkerRequest,
        fetcher: CostUsageFetcher) async throws
        -> CostUsageScanExecutor.TimedResult<CostUsageFetcher.CodexScanCatchUpStatus>
    {
        let budget = request.scanDurationPerRefresh ?? 2
        var duration: TimeInterval = 0
        var passes = 0
        var seenKeys = request.knownProgressKeys
        var progressKeys: [String] = []
        while true {
            let result = try await fetcher.advanceCodexScanCatchUp(
                now: request.now,
                codexHomePath: request.codexHomePath,
                historyDays: request.historyDays,
                scanDurationPerRefresh: max(0.001, budget - duration))
            duration += result.activeDuration
            passes += 1
            let status = result.value
            progressKeys.append(status.progressKey)
            let madeProgress = seenKeys.insert(status.progressKey).inserted
            // These are consecutive pages within one duty-cycle burst. The app owns the sleep and resource policy.
            if !status.pending || status.yieldedBeforeFileAttempt || !madeProgress
                || duration >= budget || passes >= max(1, min(8, request.maximumPasses))
            {
                var result = CostUsageScanExecutor.TimedResult(value: status, activeDuration: duration)
                result.completedPasses = passes
                result.progressKeys = progressKeys
                return result
            }
        }
    }
}
