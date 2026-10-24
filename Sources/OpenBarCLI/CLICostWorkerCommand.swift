import Commander
import Foundation
import OpenBarCore

extension OpenBarCLI {
    static func runInternalCostCommand(argv: [String]) async {
        guard let name = argv.first, name == "__cost-worker" || name == "__cost-worker-check" else { return }
        let program = Program(descriptors: [CommandDescriptor(
            name: name,
            abstract: "Internal cost worker",
            discussion: nil,
            signature: name == "__cost-worker" ? CommandSignature()
                : CommandSignature.describe(CostOptions()).flattened())])
        do {
            let invocation = try program.resolve(argv: argv)
            if name == "__cost-worker" {
                await Foundation.exit(CostUsageWorker.serve())
            }
            await Foundation.exit(Self.runCostWorkerCheck(invocation.parsedValues))
        } catch {
            Foundation.exit(1)
        }
    }

    static func runCostWorkerCheck(_ values: ParsedValues) async -> Int32 {
        guard let rawProvider = values.options["provider"]?.first,
              let provider = UsageProvider(rawValue: rawProvider) else { return 1 }
        let calendar = CostUsageBucketTimeZone.calendar(
            identifier: Self.stringFromAppDefaults("tokenCostUsageBucketTimeZone"))
        let period = Self.decodeCostReportingPeriod(from: values, saved: Self.costReportingPeriodFromDefaults())
        do {
            let report = try await CostUsageWorker.verify(
                provider: provider,
                historyDays: period.days(now: Date(), calendar: calendar),
                calendar: calendar,
                cancel: ProcessInfo.processInfo.environment["OPENBAR_COST_WORKER_CHECK_CANCEL"] == "1")
            print(report)
            return 0
        } catch {
            Self.writeStderr("Cost worker verification failed: \(error)\n")
            return 1
        }
    }
}
