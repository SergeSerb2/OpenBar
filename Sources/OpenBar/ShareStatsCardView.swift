import OpenBarCore
import SwiftUI

/// The 1200 × 630 share image (docs/design/README.md §9.6): Calm native type on a dark Iris-black field,
/// the Open Ring mark, and provider rows marked with each provider's own color.
struct ShareStatsCardView: View {
    static let size = CGSize(width: 1200, height: 630)

    let payload: ShareStatsPayload

    static func providerDisplayLimit(for providerCount: Int) -> Int {
        providerCount > 5 ? 4 : min(providerCount, 5)
    }

    static func providerPaletteIndex(
        for model: ShareStatsModelPayload,
        providers: [ShareStatsProviderPayload]) -> Int?
    {
        providers.firstIndex { $0.provider == model.provider }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            self.header
            self.hero
                .padding(.top, 16)
            Rectangle()
                .fill(ShareStatsTheme.hairline)
                .frame(height: 1)
                .padding(.vertical, 17)
            self.rankings
                .frame(height: 286, alignment: .top)
            Spacer(minLength: 10)
            self.footer
        }
        .padding(.horizontal, 52)
        .padding(.vertical, 34)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(ShareStatsTheme.background)
        .foregroundStyle(ShareStatsTheme.primary)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 12) {
                OpenRingMark()
                    .frame(width: 40, height: 40)
                Text("OpenBar")
                    .font(.system(size: 26, weight: .semibold))
            }
            Spacer()
            Text(L("LOCAL SNAPSHOT"))
                .font(.system(size: 13, weight: .semibold))
                .tracking(ShareStatsTheme.capsTracking)
                .foregroundStyle(ShareStatsTheme.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(ShareStatsTheme.cardFill, in: Capsule())
        }
    }

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 52) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("TRACKED TOKENS · %@", String(describing: self.periodLabel)))
                    .font(.system(size: 18, weight: .semibold))
                    .tracking(ShareStatsTheme.capsTracking)
                    .foregroundStyle(ShareStatsTheme.accent)
                Text(self.trackedTokensText)
                    .font(.system(size: 104, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 9) {
                Text(L("EST. %@", String(describing: self.spendLabel)))
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(ShareStatsTheme.capsTracking)
                    .foregroundStyle(ShareStatsTheme.secondary)
                ForEach(self.payload.currencies.prefix(2)) { currency in
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(currency.currencyCode) · \(currency.coveredDayCount)/\(self.coverageDenominator)")
                            .font(.system(size: 17, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(ShareStatsTheme.secondary)
                        Spacer()
                        Text(self.spendText(for: currency))
                            .font(.system(size: 32, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
                Text(self.currencySummary)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(ShareStatsTheme.secondary)
            }
            .frame(width: 390, alignment: .leading)
        }
        .frame(height: 132, alignment: .bottom)
    }

    private var currencySummary: String {
        let hiddenCount = self.payload.currencies.count - min(self.payload.currencies.count, 2)
        return hiddenCount > 0
            ? L("+%d more currencies · see subscription rows", hiddenCount)
            : ShareStatsFormatting.subscriptionSummary(count: self.payload.providers.count)
            + L(" · native currencies kept separate")
    }

    private var rankings: some View {
        HStack(alignment: .top, spacing: 46) {
            VStack(alignment: .leading, spacing: 6) {
                self.sectionHeader(L("SUBSCRIPTIONS"), detail: L("%d CONNECTED", self.payload.providers.count))
                ForEach(
                    Array(self.payload.providers.prefix(self.providerDisplayLimit).enumerated()),
                    id: \.offset)
                { index, provider in
                    ShareStatsProviderRow(
                        rank: index + 1,
                        provider: provider,
                        days: self.payload.days,
                        color: ShareStatsTheme.providerColor(provider.provider))
                }
                if self.payload.providers.count > self.providerDisplayLimit {
                    Text(L(
                        "+%@ more configured",
                        String(describing: self.payload.providers.count - self.providerDisplayLimit)))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(ShareStatsTheme.secondary)
                        .padding(.leading, 20)
                }
            }
            .frame(width: 554, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    self.sectionHeader(L("TOP MODELS"), detail: self.payload.modelRankingDetail)
                    if self.payload.topModels.isEmpty {
                        Text(L("No model-level history in this local snapshot"))
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(ShareStatsTheme.secondary)
                            .padding(.top, 4)
                    } else {
                        ForEach(
                            Array(self.payload.topModels.prefix(3).enumerated()),
                            id: \.offset)
                        { index, model in
                            ShareStatsModelRow(
                                rank: self.payload.hasPartialModels ? nil : index + 1,
                                model: model,
                                color: ShareStatsTheme.providerColor(model.provider))
                        }
                    }
                }
                Text(L("Only aggregate usage, plan tier, and estimated spend are included."))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(ShareStatsTheme.secondary)
                    .padding(.top, 18)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var providerDisplayLimit: Int {
        Self.providerDisplayLimit(for: self.payload.providers.count)
    }

    private var isAllTime: Bool {
        ShareStatsFormatting.isAllTime(self.payload)
    }

    private var periodLabel: String {
        self.isAllTime ? L("ALL") : L("%d DAYS", self.payload.days)
    }

    private var spendLabel: String {
        self.isAllTime ? L("ALL-TIME SPEND") : L("%d-DAY SPEND", self.payload.days)
    }

    private var trackedTokensText: String {
        guard let tokens = self.payload.totalTokens else { return "—" }
        let formatted = ShareStatsFormatting.compactCount(tokens)
        return self.payload.hasPartialTokens ? "~\(formatted)" : formatted
    }

    private var coverageDenominator: String {
        self.isAllTime ? L("all") : L("%dd", self.payload.days)
    }

    private func spendText(for currency: ShareStatsCurrencyPayload) -> String {
        guard let cost = currency.estimatedCost else { return L("Unavailable") }
        let formatted = ShareStatsFormatting.currency(cost, code: currency.currencyCode)
        return currency.isPartial ? "~\(formatted)" : formatted
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .tracking(ShareStatsTheme.capsTracking)
            Spacer()
            Text(detail)
                .font(.system(size: 14, weight: .medium))
                .tracking(ShareStatsTheme.capsTracking)
                .monospacedDigit()
        }
        .foregroundStyle(ShareStatsTheme.secondary)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label(L("LOCAL · AGGREGATE ONLY"), systemImage: "lock.shield")
            Spacer()
            Text(L("DATA THROUGH %@", String(describing: ShareStatsFormatting.dataThrough(self.payload).uppercased())))
                .monospacedDigit()
        }
        .font(.system(size: 13, weight: .medium))
        .tracking(ShareStatsTheme.capsTracking)
        .foregroundStyle(ShareStatsTheme.tertiary)
    }
}

/// Fixed dark palette for the exported image. It never follows the system appearance: the card must look
/// the same wherever it is posted.
private enum ShareStatsTheme {
    /// Iris-black, `#0E0D1A` → `#17143A`, top-leading to bottom-trailing. A static fill on an export
    /// image; nothing animates or redraws.
    static let background = LinearGradient(
        colors: [Self.color(0x0E0D1A), Self.color(0x17143A)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing)
    static let primary = Self.color(0xF2F2F7)
    static let secondary = Self.color(0xA1A1AA)
    static let tertiary = Self.color(0x8A8A93)
    /// Iris on dark (the `accent` token's dark value).
    static let accent = Color(nsColor: OpenBarPalette.accent.dark.nsColor)
    static let cardFill = Color.white.opacity(0.06)
    static let hairline = Color.white.opacity(0.10)
    /// The labels are uppercase strings; a little tracking keeps the caps legible at this size.
    static let capsTracking: CGFloat = 0.6

    static func providerColor(_ provider: UsageProvider) -> Color {
        let color = ProviderAccentPalette.color(for: provider)
        return Color(red: color.red, green: color.green, blue: color.blue)
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(nsColor: OpenBarColorValue(hex: hex).nsColor)
    }
}

/// The app icon's Open Ring in white: a thick ring with a gap at the upper right and a detached dot in
/// the gap. Geometry from `docs/design/icon/final-openbar-icon.svg` (1024-unit canvas).
private struct OpenRingMark: View {
    var body: some View {
        OpenRingShape()
            .fill(Color.white)
            .accessibilityHidden(true)
    }
}

/// Ring and dot in one shape: the arc's stroke outline plus the dot, filled once.
private struct OpenRingShape: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 652
        let origin = CGPoint(x: rect.midX - 326 * unit, y: rect.midY - 326 * unit)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + (x - 186) * unit, y: origin.y + (y - 186) * unit)
        }
        var arc = Path()
        arc.addArc(
            center: point(512, 512),
            radius: 262 * unit,
            startAngle: .degrees(-2.483),
            endAngle: .degrees(272.483),
            clockwise: false)
        var path = arc.strokedPath(StrokeStyle(lineWidth: 128 * unit, lineCap: .round))
        let dot = point(685.3, 338.7)
        let dotRadius = 64 * unit
        path.addEllipse(in: CGRect(
            x: dot.x - dotRadius,
            y: dot.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2))
        return path
    }
}

private struct ShareStatsModelRow: View {
    let rank: Int?
    let model: ShareStatsModelPayload
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            ShareStatsProviderDot(color: self.color)
            Text(self.rank.map { String(format: "%02d", $0) } ?? "·")
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(ShareStatsTheme.tertiary)
                .frame(width: 24, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(self.model.modelName)
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(self.model.providerName)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(ShareStatsTheme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 10)
            Text(self.detail)
                .font(.system(size: 17, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(ShareStatsTheme.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(ShareStatsTheme.cardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var detail: String {
        if let cost = self.model.estimatedCost, cost.isFinite {
            return "~\(ShareStatsFormatting.currency(cost, code: self.model.currencyCode))"
        }
        return self.model.totalTokens.map(ShareStatsFormatting.compactCount) ?? L("used")
    }
}

private struct ShareStatsProviderRow: View {
    let rank: Int
    let provider: ShareStatsProviderPayload
    let days: Int
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            ShareStatsProviderDot(color: self.color)
            Text(String(format: "%02d", self.rank))
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(ShareStatsTheme.tertiary)
                .frame(width: 24, alignment: .leading)
            HStack(spacing: 8) {
                Text(self.provider.providerName)
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                if let subscriptionName = self.provider.subscriptionName {
                    Text("· \(subscriptionName)")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(ShareStatsTheme.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            Text(self.detail)
                .font(.system(size: 17, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(ShareStatsTheme.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(ShareStatsTheme.cardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var detail: String {
        var metrics: [String] = []
        if let tokens = self.provider.totalTokens {
            metrics.append(ShareStatsFormatting.compactCount(tokens))
        }
        if let cost = self.provider.estimatedCost, cost.isFinite {
            metrics.append("~\(ShareStatsFormatting.currency(cost, code: self.provider.currencyCode))")
            if self.provider.coveredDayCount < self.days {
                metrics.append(L("%d/%dd", self.provider.coveredDayCount, self.days))
            }
        } else {
            metrics.append(L("Spend unavailable"))
        }
        return metrics.isEmpty ? L("connected") : metrics.joined(separator: " · ")
    }
}

/// Provider color dot. A faint white ring keeps dark brand colors visible on the dark card.
private struct ShareStatsProviderDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(self.color)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
            .frame(width: 12, height: 12)
            .accessibilityHidden(true)
    }
}
