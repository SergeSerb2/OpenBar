import AppKit
import OpenBarCore
import SwiftUI
@testable import OpenBar

/// The Settings window content (sidebar + detail) with test stores, one capture per pane and state.
/// Owner during the redesign: the Settings agent (see docs/design/README.md, work split).
///
/// The view is hosted in an opaque container rather than a titled window: an offscreen titled window
/// is occluded, so SwiftUI skips its sidebar list and its materials capture as black. The traffic lights are
/// therefore not in these images (the detail's back/forward strip is, because the shell draws it), the sidebar
/// material shows as the window background, and the selected row's emphasized plate draws as a solid fill.
///
/// Repeatable: provider panes read the fixed gallery clock through `settingsPreviewNow`, formatters use a fixed
/// time zone, and every snapshot is relative to `GalleryFixtures.now`.
@MainActor
enum GallerySettingsSection {
    struct Capture {
        let title: String
        let pane: SettingsPane
        var language = "en"
        var search = ""
        var note = "PreferencesView at the default 880 × 620 window size, without the titlebar."
    }

    static let timeZone = TimeZone(identifier: "America/Vancouver") ?? .gmt

    static let captures: [Capture] = [
        Capture(title: "General", pane: .general),
        Capture(
            title: "iCloud Sync",
            pane: .iCloudSync,
            note: "The test runner has no CloudKit entitlement, so this is the 1.0 \"not available\" state."),
        Capture(title: "Notifications", pane: .notifications),
        Capture(title: "Menu Bar", pane: .menuBar),
        Capture(title: "Menu", pane: .menu),
        Capture(title: "Advanced", pane: .advanced),
        Capture(
            title: "Provider · Claude",
            pane: .provider(UsageProvider.claude.instanceID),
            note: "Normal lanes (62 % and 41 % left), operational status mark (dot)."),
        Capture(
            title: "Provider · Codex",
            pane: .provider(UsageProvider.codex.instanceID),
            note: "Warning lane (18 % left), minor-issue status mark (triangle)."),
        Capture(
            title: "Provider · Cursor",
            pane: .provider(UsageProvider.cursor.instanceID),
            note: "Critical lane (6 % left, fresh data), major-outage status mark (octagon)."),
        Capture(
            title: "Provider · Gemini",
            pane: .provider(UsageProvider.gemini.instanceID),
            note: "Stale data: last updated 3 hours before the gallery clock; unknown status (ring)."),
        Capture(
            title: "Provider · Copilot",
            pane: .provider(UsageProvider.copilot.instanceID),
            note: "Error state with a long message, and no usage yet."),
        Capture(
            title: "Sidebar search · no match",
            pane: .general,
            search: "zzzz",
            note: "Empty provider search: \"No matching providers\" with the clear-filters action."),
        Capture(
            title: "Provider · Claude · Deutsch",
            pane: .provider(UsageProvider.claude.instanceID),
            language: "de"),
        Capture(title: "Menu Bar · Русский", pane: .menuBar, language: "ru"),
        Capture(title: "About", pane: .about),
    ]

    static func render(_ gallery: GalleryWriter) throws {
        let settings = testSettingsStore(
            suiteName: "DesignRenderGallery-settings",
            userDefaults: InMemoryUserDefaults())
        enableTestProviders([.claude, .codex, .cursor, .gemini, .copilot], settings: settings)
        settings.statusChecksEnabled = true
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        self.seed(store)

        // Fixed formatting inputs for repeatable renders; restored when the section ends.
        let previousTimeZone = NSTimeZone.default
        NSTimeZone.default = self.timeZone
        defer { NSTimeZone.default = previousTimeZone }
        // The test runner has no OpenBar icon; show the shipped one in the sidebar row and About.
        let previousIcon = NSApplication.shared.applicationIconImage
        NSApplication.shared.applicationIconImage = self.appIcon() ?? previousIcon
        defer { NSApplication.shared.applicationIconImage = previousIcon }

        for capture in self.captures {
            try gallery.add(
                section: "settings",
                title: "Settings · \(capture.title)",
                name: "pane-\(self.slug(capture.title))",
                note: capture.note)
            { appearance in
                try OpenBarLocalizationOverride.$appLanguage.withValue(capture.language) {
                    let selection = PreferencesSelection(userDefaults: InMemoryUserDefaults())
                    selection.pane = capture.pane
                    selection.sidebarSearchText = capture.search
                    return try GalleryCapture.hosted(
                        PreferencesView(
                            settings: settings,
                            store: store,
                            updater: DisabledUpdaterController(),
                            selection: selection)
                            .environment(\.settingsPreviewNow, GalleryFixtures.now)
                            .environment(\.timeZone, self.timeZone)
                            .environment(\.locale, Locale(identifier: capture.language)),
                        appearance: appearance,
                        size: CGSize(width: SettingsPane.windowWidth, height: SettingsPane.windowHeight),
                        backdrop: .windowBackgroundColor,
                        settle: 1.0)
                }
            }
        }

        try gallery.add(
            section: "settings",
            title: "Settings · Usage & Spend dashboard content",
            name: "spend-dashboard",
            note: "SpendDashboardCurrencySection from a synthetic 14-day model at the detail column width. "
                + "The full pane is not captured because it scans local cost logs when it appears.")
        { appearance in
            guard let group = self.spendGroup() else { throw GalleryError.bitmap }
            return try GalleryCapture.hosted(
                SpendDashboardCurrencySection(group: group, requestedDays: 14)
                    .padding(24)
                    .frame(width: SettingsPane.windowWidth - SettingsPane.sidebarWidth)
                    .environment(\.timeZone, self.timeZone),
                appearance: appearance,
                backdrop: .windowBackgroundColor,
                settle: 0.6)
        }
    }

    private static func slug(_ title: String) -> String {
        let ascii = title
            .replacingOccurrences(of: "Русский", with: "ru")
            .replacingOccurrences(of: "Deutsch", with: "de")
        return ascii.lowercased()
            .replacingOccurrences(of: " · ", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }

    /// Settings-specific usage states, each relative to the gallery clock: normal, warning, critical (fresh),
    /// stale, and error. One service status of each kind drives the sidebar marks.
    private static func seed(_ store: UsageStore) {
        let now = GalleryFixtures.now
        let states: [(UsageProvider, Double, Double?, TimeInterval)] = [
            (.claude, 38, 59, 60),
            (.codex, 82, 47, 60),
            (.cursor, 94, nil, 60),
            (.gemini, 50, 30, 3 * 3600),
        ]
        for (provider, primaryUsed, secondaryUsed, age) in states {
            store._setSnapshotForTesting(
                UsageSnapshot(
                    primary: RateWindow(
                        usedPercent: primaryUsed,
                        windowMinutes: provider == .cursor ? 43200 : 300,
                        resetsAt: now.addingTimeInterval(provider == .cursor ? 9 * 86400 : 2 * 3600 + 14 * 60),
                        resetDescription: nil),
                    secondary: secondaryUsed.map {
                        RateWindow(
                            usedPercent: $0,
                            windowMinutes: 10080,
                            resetsAt: now.addingTimeInterval(3 * 86400 + 4 * 3600),
                            resetDescription: nil)
                    },
                    updatedAt: now.addingTimeInterval(-age)),
                provider: provider)
        }
        store._setErrorForTesting(
            "GitHub returned 401 Unauthorized for the Copilot usage request. Sign in again from Settings → "
                + "Providers → Copilot, or check that the token still has the copilot scope. Request ID 7F3A-19C2.",
            provider: .copilot)
        let statuses: [(UsageProvider, ProviderStatusIndicator)] = [
            (.claude, .none), (.codex, .minor), (.cursor, .major), (.gemini, .unknown), (.copilot, .none),
        ]
        for (provider, indicator) in statuses {
            store.statuses[provider.instanceID] = ProviderStatus(
                indicator: indicator,
                description: nil,
                updatedAt: now)
        }
    }

    private static func appIcon() -> NSImage? {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // RenderGallery
            .deletingLastPathComponent() // OpenBarTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent()
        return NSImage(contentsOf: repository.appendingPathComponent("Sources/OpenBar/Resources/Icon-classic.icns"))
    }

    /// Fictitious Codex, Claude, and Cursor spend over 14 days, in the fixed gallery time zone.
    private static func spendGroup() -> SpendDashboardModel.CurrencyGroup? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = self.timeZone
        let now = GalleryFixtures.now
        let today = calendar.startOfDay(for: now)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let accounts: [(String, UsageProvider, String, Double)] = [
            ("codex-a", .codex, "Codex", 1.0),
            ("claude-a", .claude, "Claude", 1.6),
            ("cursor-a", .cursor, "Cursor", 0.4),
        ]
        let inputs = accounts.enumerated().map { index, account in
            var daily: [CostUsageDailyReport.Entry] = []
            for offset in -13...0 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                let cost = Double((abs(offset) * 7 + index * 5) % 13 + 2) * 0.9 * account.3
                daily.append(CostUsageDailyReport.Entry(
                    date: formatter.string(from: day),
                    inputTokens: nil,
                    outputTokens: nil,
                    totalTokens: Int(cost * 120_000),
                    costUSD: cost,
                    modelsUsed: nil,
                    modelBreakdowns: nil))
            }
            let snapshot = CostUsageTokenSnapshot(
                sessionTokens: nil,
                sessionCostUSD: nil,
                last30DaysTokens: daily.compactMap(\.totalTokens).reduce(0, +),
                last30DaysCostUSD: daily.compactMap(\.costUSD).reduce(0, +),
                historyDays: 14,
                costProvenance: .listPriceEstimate,
                daily: daily,
                updatedAt: now)
            return SpendDashboardModel.ProviderInput(
                id: account.0,
                provider: account.1,
                displayName: account.2,
                snapshot: snapshot)
        }
        return SpendDashboardModel.build(inputs: inputs, requestedDays: 14, now: now, calendar: calendar).groups.first
    }
}
