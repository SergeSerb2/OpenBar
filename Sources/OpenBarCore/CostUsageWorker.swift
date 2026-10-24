import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

package enum CostUsageWorker {
    static let maximumRequestBytes = 8 * 1024 * 1024
    static let maximumResponseBytes = 64 * 1024 * 1024
    private static var timeout: Duration {
        #if DEBUG
        // Diagnostic CLI runs can exercise the real deadline path without a 15-minute wait.
        if let raw = ProcessInfo.processInfo.environment["OPENBAR_COST_WORKER_TIMEOUT_PROBE_SECONDS"],
           let seconds = TimeInterval(raw), seconds.isFinite, seconds > 0, seconds <= 15 * 60
        {
            return .seconds(seconds)
        }
        #endif
        return .seconds(15 * 60)
    }

    @TaskLocal static var isWorker = false
    @TaskLocal static var pricingJobs: CostUsageScanExecutor.LockedState<[CostUsageWorkerPricingJob]>?

    enum Outcome<Value: Sendable>: Sendable {
        case unavailable
        case value(Value)
    }

    enum WorkerError: Error {
        case protocolFailure
    }

    static var executable: URL? {
        guard !self.isWorker else { return nil }
        let environment = ProcessInfo.processInfo.environment
        let url: URL
        if environment["OPENBAR_COST_WORKER"] == "1" {
            url = environment["OPENBAR_COST_WORKER_PATH"].map { URL(fileURLWithPath: $0) }
                ?? URL(fileURLWithPath: CommandLine.arguments[0])
        } else {
            let bundle = Bundle.main.bundleURL
            guard bundle.pathExtension == "app",
                  Bundle.main.executableURL?.lastPathComponent == "OpenBar",
                  ProcessInfo.processInfo.processName == "OpenBar" else { return nil }
            url = bundle.appendingPathComponent("Contents/Helpers/OpenBarCLI")
        }
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static func canRoute(options: CostUsageScanner.Options?) -> Bool {
        self.executable != nil && options?.codexScanBudgetForTesting == nil
            && options?.codexScanWorkRecorderForTesting == nil && options?.codexScanDidYieldBeforeFileAttempt == nil
    }

    static func run<Value: Codable & Sendable>(
        _ request: CostUsageWorkerRequest,
        as _: Value.Type) async throws -> Outcome<Value>
    {
        guard let executable = self.executable else { return .unavailable }
        do {
            let wakeup = DispatchSemaphore(value: 0)
            let cancelled = CostUsageScanExecutor.LockedState(false)
            let value = try await withTaskCancellationHandler {
                try await CostUsageScanExecutor.run { checkCancellation in
                    try self.exchange(request, executable: executable, wakeup: wakeup, checkCancellation: {
                        try checkCancellation()
                        if cancelled.withLock({ $0 }) { throw CancellationError() }
                    })
                }
            } onCancel: {
                // Publish cancellation before waking: the executor's own cancellation handler can
                // run in either order, and a cancelled exchange must never go back to sleep.
                cancelled.withLock { $0 = true }
                wakeup.signal()
            }
            try Task.checkCancellation()
            guard let result = value.result else { throw WorkerError.protocolFailure }
            let decoded = try PropertyListDecoder().decode(CostUsageWorkerValue<Value>.self, from: result).value
            for job in value.pricingJobs {
                job.start()
            }
            return .value(decoded)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            OpenBarLog.logger(LogCategories.tokenCost).warning(
                "Cost worker failed; retrying once in process (\(request.operation.rawValue))")
            return .unavailable
        }
    }

    private static func exchange(
        _ request: CostUsageWorkerRequest,
        executable: URL,
        wakeup: DispatchSemaphore,
        checkCancellation: @escaping @Sendable () throws -> Void) throws -> CostUsageWorkerResponse
    {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(request)
        guard data.count <= self.maximumRequestBytes else { throw WorkerError.protocolFailure }
        // Unlink before writing: the inherited stdin file never leaves environment values on disk by name.
        let inputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.createFile(
            atPath: inputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        else { throw WorkerError.protocolFailure }
        let input: FileHandle
        do {
            input = try FileHandle(forUpdating: inputURL)
        } catch {
            try? FileManager.default.removeItem(at: inputURL)
            throw error
        }
        defer { try? input.close() }
        try FileManager.default.removeItem(at: inputURL)
        try input.write(contentsOf: data)
        try input.seek(toOffset: 0)

        let process = Process()
        process.terminationHandler = { _ in wakeup.signal() }
        process.executableURL = executable
        process.arguments = ["__cost-worker"]
        process.environment = request.processEnvironment
        process.standardInput = input
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let stdout = ProcessPipeCapture(pipe: output, maxBytes: self.maximumResponseBytes + 1) {
            wakeup.signal()
        }
        let stderr = ProcessPipeCapture(pipe: errors, maxBytes: 64 * 1024)
        defer {
            stdout.stop()
            stderr.stop()
            output.fileHandleForWriting.closeFile()
            errors.fileHandleForWriting.closeFile()
        }
        try checkCancellation()
        try process.run()
        stdout.start()
        stderr.start()
        defer {
            if process.isRunning { SubprocessRunner.terminateProcess(process, processGroup: nil) }
            process.waitUntilExit()
        }
        let deadline = ContinuousClock.now.advanced(by: self.timeout)
        let timeoutTask = Task.detached(priority: .utility) {
            do {
                // This is a hard deadline: default clock tolerance may coalesce the wake past it.
                try await Task.sleep(until: deadline, tolerance: .zero, clock: .continuous)
            } catch {
                return
            }
            wakeup.signal()
        }
        defer { timeoutTask.cancel() }
        while process.isRunning {
            try checkCancellation()
            guard ContinuousClock.now < deadline, stdout.currentSnapshot().count <= self.maximumResponseBytes else {
                throw WorkerError.protocolFailure
            }
            // Pipe output, process exit, and cancellation each signal this wait. The deadline
            // uses the same continuous clock, including system sleep, as the original timeout.
            wakeup.wait()
        }
        process.waitUntilExit()
        let response = stdout.finishSynchronously(timeout: 5)
        _ = stderr.finishSynchronously(timeout: 5)
        try checkCancellation()
        guard process.terminationStatus == 0, stdout.reachedEOF,
              response.count <= self.maximumResponseBytes else { throw WorkerError.protocolFailure }
        let value = try PropertyListDecoder().decode(CostUsageWorkerResponse.self, from: response)
        guard value.version == request.version, value.generation == request.generation else {
            throw WorkerError.protocolFailure
        }
        return value
    }
}
