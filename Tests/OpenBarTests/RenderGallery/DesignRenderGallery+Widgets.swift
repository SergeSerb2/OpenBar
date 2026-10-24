import AppKit
import OpenBarCore
import SwiftUI
import WidgetKit
@testable import OpenBarWidget

/// Widget tiles at the macOS sizes, in full color and in the accented rendering mode.
/// Owner during the redesign: the Widgets & web agent (see docs/design/README.md, work split).
@MainActor
enum GalleryWidgetsSection {
    static let sizes: [(String, WidgetTileSize, CGSize)] = [
        ("Small", .small, CGSize(width: 155, height: 155)),
        ("Medium", .medium, CGSize(width: 329, height: 155)),
        ("Large", .large, CGSize(width: 329, height: 345)),
    ]

    static func render(_ gallery: GalleryWriter) throws {
        let entry = Self.entry()
        for (label, size, points) in self.sizes {
            try gallery.add(
                section: "widgets",
                title: "Usage tile · \(label)",
                name: "usage-\(label.lowercased())",
                note: "UsageTile + TileHeader for a synthetic Claude entry, "
                    + "\(Int(points.width)) × \(Int(points.height)) pt.")
            { appearance in
                try GalleryCapture.hosted(
                    self.tile(entry: entry, size: size, points: points, appearance: appearance, mode: nil),
                    appearance: appearance,
                    backdrop: appearance.desktopBackdrop,
                    padding: 16)
            }
        }
        try gallery.add(
            section: "widgets",
            title: "Usage tile · Medium · accented mode",
            name: "usage-medium-accented",
            note: "widgetRenderingModeOverride = .accented: the tile must read through shape and text alone.")
        { appearance in
            try GalleryCapture.hosted(
                self.tile(
                    entry: entry,
                    size: .medium,
                    points: CGSize(width: 329, height: 155),
                    appearance: appearance,
                    mode: .accented),
                appearance: appearance,
                backdrop: appearance.desktopBackdrop,
                padding: 16)
        }
    }

    private static func tile(
        entry: WidgetSnapshot.ProviderEntry,
        size: WidgetTileSize,
        points: CGSize,
        appearance: GalleryAppearance,
        mode: WidgetRenderingMode?) -> some View
    {
        UsageTile(entry: entry, size: size) {
            TileHeader(provider: entry.provider, updatedAt: entry.updatedAt, size: size)
        }
        .environment(\.widgetRenderingModeOverride, mode)
        .padding(size == .small ? 12 : 14)
        .frame(width: points.width, height: points.height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(appearance.isDark ? Color(white: 0.17) : Color(white: 0.98)))
    }

    private static func entry() -> WidgetSnapshot.ProviderEntry {
        let now = Date(timeIntervalSince1970: 1_792_861_200)
        return WidgetSnapshot.ProviderEntry(
            provider: .claude,
            updatedAt: now.addingTimeInterval(-60),
            primary: RateWindow(
                usedPercent: 38,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(2 * 3600 + 14 * 60),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 59,
                windowMinutes: 10080,
                resetsAt: now.addingTimeInterval(3 * 86400 + 4 * 3600),
                resetDescription: nil),
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])
    }
}
