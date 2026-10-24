import AppKit
import OpenBarCore
import SwiftUI
@testable import OpenBar

/// The Settings window content (sidebar + detail) with test stores, one capture per pane.
/// Owner during the redesign: the Settings agent (see docs/design/README.md, work split).
///
/// The view is hosted in an opaque container rather than a titled window: an offscreen titled window
/// is occluded, so SwiftUI skips its sidebar list and its materials capture as black. The titlebar and
/// toolbar are therefore not in these images, and selection plates that use emphasized materials draw
/// as solid fills.
@MainActor
enum GallerySettingsSection {
    static let panes: [(String, SettingsPane)] = [
        ("General", .general),
        ("Menu Bar", .menuBar),
        ("Provider · Claude", .provider(UsageProvider.claude.instanceID)),
        ("About", .about),
    ]

    static func render(_ gallery: GalleryWriter) throws {
        let settings = testSettingsStore(
            suiteName: "DesignRenderGallery-settings",
            userDefaults: InMemoryUserDefaults())
        enableTestProviders([.claude, .codex, .cursor, .gemini], settings: settings)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        for (title, pane) in self.panes {
            let slug = title.lowercased()
                .replacingOccurrences(of: " · ", with: "-")
                .replacingOccurrences(of: " ", with: "-")
            try gallery.add(
                section: "settings",
                title: "Settings · \(title)",
                name: "pane-\(slug)",
                note: "PreferencesView at the default 880 × 620 window size, without the titlebar.")
            { appearance in
                let selection = PreferencesSelection(userDefaults: InMemoryUserDefaults())
                selection.pane = pane
                return try GalleryCapture.hosted(
                    PreferencesView(
                        settings: settings,
                        store: store,
                        updater: DisabledUpdaterController(),
                        selection: selection),
                    appearance: appearance,
                    size: CGSize(width: SettingsPane.windowWidth, height: SettingsPane.windowHeight),
                    backdrop: .windowBackgroundColor,
                    settle: 1.0)
            }
        }
    }
}
