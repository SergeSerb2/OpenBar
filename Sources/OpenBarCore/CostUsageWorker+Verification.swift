import Foundation

extension CostUsageWorker {
    package static func verify(
        provider: UsageProvider,
        historyDays: Int,
        calendar: Calendar,
        cancel: Bool = false) async throws -> String
    {
        // Provider-specific by design: only the Codex, Claude, and Pi local log scanners run in the helper.
        guard self.executable != nil, provider == .codex || provider == .claude || provider == .pi else {
            throw WorkerError.protocolFailure
        }
        let now = Date()
        let options = CostUsageScanner.Options(
            calendar: calendar,
            maxCodexSessionFileBytes: 0,
            maxCodexScanBytesPerRefresh: 0,
            maxCodexScanDurationPerRefresh: 0)
        var request = CostUsageWorkerRequest(operation: .tokens, scanner: .init(options))
        request.provider = provider
        request.now = now
        request.historyDays = historyDays
        request.allowPricingRefresh = false
        request.bypassScannerDebounce = true
        if cancel {
            let task = Task { try await self.run(request, as: CostUsageTokenResult.self) }
            try await Task.sleep(for: .milliseconds(100))
            task.cancel()
            do {
                _ = try await task.value
                throw WorkerError.protocolFailure
            } catch is CancellationError {
                return "worker cancellation == CancellationError (child reaped before return)"
            }
        }
        let direct = try await self.$isWorker.withValue(true) {
            try await self.referenceResult(provider: provider, now: now, historyDays: historyDays, options: options)
        }
        guard case let .value(remote) = try await self.run(request, as: CostUsageTokenResult.self) else {
            throw WorkerError.protocolFailure
        }
        guard direct == remote else {
            let expected = try PropertyListSerialization.propertyList(
                from: self.verificationData(direct), format: nil)
            let actual = try PropertyListSerialization.propertyList(
                from: self.verificationData(remote), format: nil)
            print("Mismatched fields: " + Self.mismatches(expected, actual, path: "result").prefix(20)
                .joined(separator: ", "))
            throw WorkerError.protocolFailure
        }
        var lines = [
            "\(provider.rawValue) full token result == true",
            "daily=\(remote.snapshot.daily.count) hourly=\(remote.snapshot.hourly.count) "
                + "quotaSlices=\(remote.snapshot.quotaSlices.count) "
                + "sessions=\(remote.snapshot.sessions.count) projects=\(remote.snapshot.projects.count)",
        ]
        // Provider-specific by design: cached snapshot, activity, and catch-up status exist only for Codex.
        if provider == .codex {
            request.operation = .cachedSnapshot
            let cached = await self.$isWorker.withValue(true) {
                await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
                    now: now, historyDays: historyDays, scannerOptions: options)
            }
            guard case let .value(remoteCached) = try await self.run(
                request, as: CostUsageFetcher.CachedCodexTokenSnapshotResult?.self), cached == remoteCached
            else { throw WorkerError.protocolFailure }
            lines.append("cached snapshot result == true")
            request.operation = .cachedActivity
            let activity = await self.$isWorker.withValue(true) {
                await CostUsageFetcher.loadCachedCodexTokenActivity(
                    now: now, maximumDays: historyDays, scannerOptions: options)
            }
            guard case let .value(remoteActivity) = try await self.run(
                request, as: CostUsageTokenActivityCache?.self), activity == remoteActivity
            else { throw WorkerError.protocolFailure }
            lines.append("cached activity == true")
            request.operation = .status
            let status = await self.$isWorker.withValue(true) {
                await CostUsageFetcher(scannerOptions: options).codexScanCatchUpStatus(now: now)
            }
            guard case let .value(remoteStatus) = try await self.run(
                request, as: CostUsageFetcher.CodexScanCatchUpStatus.self), status == remoteStatus
            else { throw WorkerError.protocolFailure }
            lines.append("catch-up status == true")
        }
        return lines.joined(separator: "\n")
    }

    private static func referenceResult(
        provider: UsageProvider,
        now: Date,
        historyDays: Int,
        options: CostUsageScanner.Options) async throws -> CostUsageTokenResult
    {
        var seenKeys: Set<String> = []
        for _ in 0..<64 {
            let result = try await CostUsageFetcher.loadTokenResult(
                provider: provider,
                now: now,
                historyDays: historyDays,
                allowPricingRefresh: false,
                bypassScannerDebounce: true,
                scannerOptions: options)
            // Provider-specific by design: only Codex scans are budgeted, so only Codex repeats until caught up.
            guard provider == .codex else { return result }
            let status = await CostUsageFetcher(scannerOptions: options).codexScanCatchUpStatus(now: now)
            if !status.pending { return result }
            guard seenKeys.insert(status.progressKey).inserted else { throw WorkerError.protocolFailure }
        }
        throw WorkerError.protocolFailure
    }

    private static func verificationData(_ result: CostUsageTokenResult) throws -> Data {
        try PropertyListEncoder().encode(CostUsageWorkerValue(value: result))
    }

    private static func mismatches(_ expected: Any, _ actual: Any, path: String) -> [String] {
        if let lhs = expected as? [String: Any], let rhs = actual as? [String: Any] {
            return Set(lhs.keys).union(rhs.keys).sorted().flatMap { key in
                guard let left = lhs[key], let right = rhs[key] else { return [path + "." + key] }
                return Self.mismatches(left, right, path: path + "." + key)
            }
        }
        if let lhs = expected as? [Any], let rhs = actual as? [Any] {
            guard lhs.count == rhs.count else { return [path + ".count"] }
            return lhs.indices.flatMap { Self.mismatches(lhs[$0], rhs[$0], path: path + "[\($0)]") }
        }
        return (expected as? NSObject)?.isEqual(actual) == true ? [] : [path]
    }
}
