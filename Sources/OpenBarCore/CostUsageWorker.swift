import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

package enum CostUsageWorker {
    static let maximumRequestBytes = 8 * 1024 * 1024
    static let maximumResponseBytes = 64 * 1024 * 1024
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
            let value = try await CostUsageScanExecutor.run { checkCancellation in
                try checkCancellation()
                return try self.exchange(request, executable: executable, checkCancellation: checkCancellation)
            }
            try Task.checkCancellation()
            for job in value.pricingJobs {
                job.start()
            }
            guard let result = value.result else { throw WorkerError.protocolFailure }
            return try .value(PropertyListDecoder().decode(CostUsageWorkerValue<Value>.self, from: result).value)
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
        process.executableURL = executable
        process.arguments = ["__cost-worker"]
        process.environment = request.processEnvironment
        process.standardInput = input
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let stdout = ProcessPipeCapture(pipe: output, maxBytes: self.maximumResponseBytes + 1)
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
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        let deadline = Date().addingTimeInterval(15 * 60)
        while process.isRunning {
            try checkCancellation()
            guard Date() < deadline, stdout.currentSnapshot().count <= self.maximumResponseBytes else {
                throw WorkerError.protocolFailure
            }
            Thread.sleep(forTimeInterval: 0.01)
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
