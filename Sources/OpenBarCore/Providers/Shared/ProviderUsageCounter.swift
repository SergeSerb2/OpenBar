import Foundation

/// Invalid or overflowing upstream counters must not become plausible partial totals.
enum ProviderUsageCounter {
    enum Failure: LocalizedError {
        case invalidCount

        var errorDescription: String? {
            "Usage counters are out of range."
        }
    }

    static func sum(_ values: some Sequence<Int?>) -> Int? {
        var total = 0
        for value in values {
            guard let value, value >= 0 else { return nil }
            let result = total.addingReportingOverflow(value)
            guard !result.overflow else { return nil }
            total = result.partialValue
        }
        return total
    }

    static func add(_ lhs: Int, _ rhs: Int) throws -> Int {
        guard lhs >= 0, rhs >= 0, let total = CheckedSum.integers([lhs, rhs]) else {
            throw Failure.invalidCount
        }
        return total
    }
}
