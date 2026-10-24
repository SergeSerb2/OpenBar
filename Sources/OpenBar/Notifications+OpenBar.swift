import Foundation
import OpenBarCore

extension Notification.Name {
    static let openbarDebugBlinkNow = Notification.Name("openbarDebugBlinkNow")
    #if DEBUG
    static let openbarDebugSimulateMemoryPressure =
        Notification.Name("com.serbinenko.openbar.debug.simulateMemoryPressure")
    #endif
    static let openbarSessionLimitReset = Notification.Name("openbarSessionLimitReset")
    static let openbarWeeklyLimitReset = Notification.Name("openbarWeeklyLimitReset")
    static let openbarProviderConfigDidChange = Notification.Name("openbarProviderConfigDidChange")
    static let openbarLocalConfigFileDidChange = Notification.Name("openbarLocalConfigFileDidChange")
    static let openbarUsageSnapshotsDidChange = Notification.Name("openbarUsageSnapshotsDidChange")
    static let openbarQuotaWarningDidPost = Notification.Name("openbarQuotaWarningDidPost")
}

final class UsageSnapshotsDidChangeEvent: NSObject, @unchecked Sendable {
    let snapshots: [AccountSnapshotSyncPayload]

    init(snapshots: [AccountSnapshotSyncPayload]) {
        self.snapshots = snapshots
    }
}

@MainActor
final class SessionLimitResetEvent: NSObject {
    let provider: UsageProvider
    let accountIdentifier: String
    let accountLabel: String?
    let usedPercent: Double

    init(provider: UsageProvider, accountIdentifier: String, accountLabel: String?, usedPercent: Double) {
        self.provider = provider
        self.accountIdentifier = accountIdentifier
        self.accountLabel = accountLabel
        self.usedPercent = usedPercent
    }
}

@MainActor
final class WeeklyLimitResetEvent: NSObject {
    let provider: UsageProvider
    let accountIdentifier: String
    let accountLabel: String?
    let usedPercent: Double

    init(provider: UsageProvider, accountIdentifier: String, accountLabel: String?, usedPercent: Double) {
        self.provider = provider
        self.accountIdentifier = accountIdentifier
        self.accountLabel = accountLabel
        self.usedPercent = usedPercent
    }
}

@MainActor
final class QuotaWarningPostedEvent: NSObject {
    let provider: UsageProvider
    let window: QuotaWarningWindow
    let threshold: Int
    let postedAt: Date

    init(provider: UsageProvider, window: QuotaWarningWindow, threshold: Int, postedAt: Date) {
        self.provider = provider
        self.window = window
        self.threshold = threshold
        self.postedAt = postedAt
    }
}
