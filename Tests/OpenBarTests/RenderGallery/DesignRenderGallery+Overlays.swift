import AppKit
import OpenBarCore
import SwiftUI
@testable import OpenBar

/// Transient overlays and the share card, rendered with fictitious data. Called from the menubar section
/// so it shares that section's filter. Owner during the redesign: the Glyph agent. The confetti overlay
/// is a Core Animation particle effect and has no static frame worth capturing.
@MainActor
enum GalleryOverlaysSection {
    static func render(_ gallery: GalleryWriter) throws {
        try gallery.add(
            section: "overlays",
            title: "Quota warning overlay",
            name: "quota-warning-overlay",
            note: "Content of the click-through panel; shown over a stand-in desktop.")
        { appearance in
            try GalleryCapture.hosted(
                QuotaWarningAlertOverlayView(
                    title: "Claude session quota is low",
                    message: "18% left. Resets in 2h 14m.")
                    .frame(width: 520, height: 180),
                appearance: appearance,
                backdrop: appearance.desktopBackdrop,
                settle: 0.5)
        }

        try gallery.add(
            section: "overlays",
            title: "Quota warning overlay · long localized text",
            name: "quota-warning-overlay-long",
            note: "German-length copy wraps inside the 420-point card instead of truncating.")
        { appearance in
            try GalleryCapture.hosted(
                QuotaWarningAlertOverlayView(
                    title: "Das Sitzungskontingent für Claude ist fast aufgebraucht",
                    message: "Noch 8 % übrig. Das Kontingent wird in 2 Std. 14 Min. zurückgesetzt; "
                        + "bis dahin können Anfragen abgelehnt werden.")
                    .frame(width: 520, height: 200),
                appearance: appearance,
                backdrop: appearance.desktopBackdrop,
                settle: 0.5)
        }

        try gallery.add(
            section: "overlays",
            title: "Share stats card · 1200 × 630 export",
            name: "share-card",
            note: "Always dark; the light capture shows the same card.",
            appearances: [.dark])
        { appearance in
            try GalleryCapture.hosted(
                ShareStatsCardView(payload: self.sharePayload),
                appearance: appearance,
                size: ShareStatsCardView.size)
        }
    }

    static let sharePayload = ShareStatsPayload(
        days: 30,
        periodEnd: GalleryFixtures.now,
        providers: [
            Self.provider(.claude, plan: "Max", tokens: 182_400_000, cost: 412.50, days: 30),
            Self.provider(.codex, plan: "Pro", tokens: 96_100_000, cost: 188.20, days: 30),
            Self.provider(.cursor, plan: nil, tokens: 21_800_000, cost: 39.75, days: 24),
        ],
        topModels: [
            Self.model(.claude, model: "orbit-large", tokens: 120_000_000, cost: 301.10),
            Self.model(.codex, model: "quill-2", tokens: 80_000_000, cost: 160.00),
            Self.model(.claude, model: "orbit-mini", tokens: 41_000_000, cost: 64.30),
        ],
        currencies: [
            ShareStatsCurrencyPayload(currencyCode: "USD", estimatedCost: 640.45, coveredDayCount: 30),
        ],
        totalTokens: 300_300_000,
        periodEndTimeZone: TimeZone(identifier: "America/Vancouver") ?? .current)

    private static func provider(
        _ provider: UsageProvider,
        plan: String?,
        tokens: Int,
        cost: Double,
        days: Int) -> ShareStatsProviderPayload
    {
        ShareStatsProviderPayload(
            provider: provider,
            providerName: provider.rawValue.capitalized,
            subscriptionName: plan,
            currencyCode: "USD",
            totalTokens: tokens,
            estimatedCost: cost,
            coveredDayCount: days)
    }

    private static func model(
        _ provider: UsageProvider,
        model: String,
        tokens: Int,
        cost: Double) -> ShareStatsModelPayload
    {
        ShareStatsModelPayload(
            provider: provider,
            providerName: provider.rawValue.capitalized,
            modelName: model,
            currencyCode: "USD",
            totalTokens: tokens,
            estimatedCost: cost)
    }
}
