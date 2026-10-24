import Foundation

struct CostUsageWorkerRequest: Codable, Sendable {
    enum Operation: String, Codable, Sendable {
        case tokens, cachedSnapshot, cachedActivity, status, advance, cachedProjects, projects
    }

    struct ScannerOptions: Codable, Sendable {
        var codexSessionsRoot: URL?
        var claudeProjectsRoots: [URL]?
        var cacheRoot: URL?
        var codexTraceDatabaseURL: URL?
        var calendar: Calendar
        var refreshMinIntervalSeconds: TimeInterval
        var claudeLogProviderFilter: String
        var forceRescan: Bool
        var maxCodexSessionFileBytes: Int64
        var maxCodexScanBytesPerRefresh: Int64
        var maxCodexScanDurationPerRefresh: TimeInterval?
        var preferNewestCodexSessionsFirst: Bool

        init(_ options: CostUsageScanner.Options) {
            self.codexSessionsRoot = options.codexSessionsRoot
            self.claudeProjectsRoots = options.claudeProjectsRoots
            self.cacheRoot = options.cacheRoot
            self.codexTraceDatabaseURL = options.codexTraceDatabaseURL
            self.calendar = options.calendar
            self.refreshMinIntervalSeconds = options.refreshMinIntervalSeconds
            self.claudeLogProviderFilter = switch options.claudeLogProviderFilter {
            case .all: "all"
            case .vertexAIOnly: "vertexAIOnly"
            case .excludeVertexAI: "excludeVertexAI"
            }
            self.forceRescan = options.forceRescan
            self.maxCodexSessionFileBytes = options.maxCodexSessionFileBytes
            self.maxCodexScanBytesPerRefresh = options.maxCodexScanBytesPerRefresh
            self.maxCodexScanDurationPerRefresh = options.maxCodexScanDurationPerRefresh
            self.preferNewestCodexSessionsFirst = options.preferNewestCodexSessionsFirst
        }

        var options: CostUsageScanner.Options {
            var options = CostUsageScanner.Options(
                codexSessionsRoot: self.codexSessionsRoot,
                claudeProjectsRoots: self.claudeProjectsRoots,
                cacheRoot: self.cacheRoot,
                codexTraceDatabaseURL: self.codexTraceDatabaseURL,
                calendar: self.calendar,
                claudeLogProviderFilter: self.claudeLogProviderFilter == "vertexAIOnly" ? .vertexAIOnly
                    : self.claudeLogProviderFilter == "excludeVertexAI" ? .excludeVertexAI : .all,
                forceRescan: self.forceRescan,
                maxCodexSessionFileBytes: self.maxCodexSessionFileBytes,
                maxCodexScanBytesPerRefresh: self.maxCodexScanBytesPerRefresh,
                maxCodexScanDurationPerRefresh: self.maxCodexScanDurationPerRefresh,
                preferNewestCodexSessionsFirst: self.preferNewestCodexSessionsFirst)
            options.refreshMinIntervalSeconds = self.refreshMinIntervalSeconds
            return options
        }
    }

    var version = 1
    var generation = UUID()
    var operation: Operation
    var scanner: ScannerOptions
    var processEnvironment = ProcessInfo.processInfo.environment
    var environment = ProcessInfo.processInfo.environment
    // Provider-specific by design: only token requests read this; the other operations are Codex catch-up steps.
    var provider: UsageProvider = .codex
    var antigravityAdditionalProfileHomes: [String] = []
    var now = Date()
    var forceRefresh = false
    var allowVertexClaudeFallback = false
    var codexHomePath: String?
    var historyDays = 30
    var allowPricingRefresh = true
    var refreshPricingInBackground = true
    var includePiSessions = true
    var bypassScannerDebounce = false
    var piWorkingDirectories: [URL] = []
    var piSessionProcessContexts: [PiSessionProcessContext] = []
    var retryUnknownPricing = true
    var reportContext: CostUsageReportContext?
    var allowScopedCodexHome = false
    var includeProjectAndSessionBreakdowns = true
    var requireCompleteHistory = false
    var statusHistoryDays: Int?
    var maximumPasses = 8
    var knownProgressKeys: Set<String> = []
    var scanDurationPerRefresh: TimeInterval?
    var hidePersonalInfo = true
}

struct CostUsageWorkerResponse: Codable, Sendable {
    let version: Int
    let generation: UUID
    let result: Data?
    let pricingJobs: [CostUsageWorkerPricingJob]
}

struct CostUsageWorkerValue<Value: Codable>: Codable {
    let value: Value
}

struct CostUsageWorkerPricingJob: Codable, Sendable {
    struct Target: Codable, Sendable {
        let providerID: String
        let modelID: String
    }

    let now: Date
    let cacheRoot: URL?
    var targets: [Target]?

    func start() {
        Task.detached(priority: .utility) {
            let client = ModelsDevClient()
            guard let targets = self.targets else {
                await ModelsDevPricingPipeline.refreshIfNeeded(now: self.now, cacheRoot: self.cacheRoot, client: client)
                return
            }
            let groups = Dictionary(grouping: targets, by: \.providerID)
            for providerID in groups.keys.sorted() {
                let outcome = await ModelsDevPricingPipeline.refreshForUnknownModelsIfNeeded(
                    providerID: providerID,
                    modelIDs: Set(groups[providerID, default: []].map(\.modelID)),
                    now: self.now,
                    cacheRoot: self.cacheRoot,
                    client: client)
                if outcome == .pricingAvailable { return }
            }
        }
    }
}
