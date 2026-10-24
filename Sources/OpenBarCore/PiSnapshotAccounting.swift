import Foundation

/// Describes which local sources are represented by a token-cost snapshot.
///
/// Claude and Codex can read Pi/OMP session logs as an inclusive convenience. The
/// spend dashboard uses this metadata to project the native portion when Pi is
/// shown as its own source, so the same session is never counted twice.
package enum PiSnapshotAccounting: Sendable, Equatable, Codable {
    case nativeOnly
    case includesPi(scope: String, native: CostUsageTokenSnapshot)
    /// Inclusive, like `includesPi`, for readers that never project the native portion. Only the
    /// spend dashboard projects it, so other publications skip holding a second snapshot.
    case includesPiWithoutNative(scope: String)
    case piOnly(scope: String)

    package var scope: String? {
        switch self {
        case .nativeOnly:
            nil
        case let .includesPi(scope, _), let .includesPiWithoutNative(scope), let .piOnly(scope):
            scope
        }
    }

    package var withoutQuotaSlices: Self {
        guard case let .includesPi(scope, native) = self else { return self }
        return .includesPi(scope: scope, native: native.withoutQuotaSlices())
    }

    package var withoutNativeProjection: Self {
        guard case let .includesPi(scope, _) = self else { return self }
        return .includesPiWithoutNative(scope: scope)
    }
}

package struct CostUsageTokenResult: Sendable, Equatable, Codable {
    package let snapshot: CostUsageTokenSnapshot
    package let accounting: PiSnapshotAccounting?

    package init(snapshot: CostUsageTokenSnapshot, accounting: PiSnapshotAccounting? = nil) {
        self.snapshot = snapshot
        self.accounting = accounting
    }
}
