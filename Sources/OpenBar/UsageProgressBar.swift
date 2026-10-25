import SwiftUI

/// Static quota meter used inside menu cards (spec §9.2 "Meter").
///
/// A provider-colored capsule fill, a 1.5-pt gap, then a capsule track. Quota-warning markers
/// and workday ticks are 1-pt gaps cut into that geometry, and the pace marker is a rounded
/// 2 × 10 pt tick with a cleared halo. Everything is a plain SwiftUI `Shape` with a computed
/// path: no bitmaps, no `Canvas`, no blend modes, no compositing groups, no animation. The
/// offscreen bench in docs/design/bench measured plain shapes ≈ 50 KiB cheaper per meter than
/// the CGImage meter this replaces, with no GPU memory committed.
struct UsageProgressBar: View {
    enum MarkerKind: Equatable {
        case quotaWarning
        case workdayBoundary
    }

    struct Marker: Equatable {
        let percent: Double
        let kind: MarkerKind
    }

    let percent: Double
    let tint: Color
    let accessibilityLabel: String
    let pacePercent: Double?
    let paceOnTop: Bool
    let warningMarkerPercents: [Double]
    let workdayMarkerPercents: [Double]
    let workdayTickAppearance: WorkdayTickAppearance
    let height: CGFloat
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.displayScale) private var displayScale

    init(
        percent: Double,
        tint: Color,
        accessibilityLabel: String,
        pacePercent: Double? = nil,
        paceOnTop: Bool = true,
        warningMarkerPercents: [Double] = [],
        workdayMarkerPercents: [Double] = [],
        workdayTickAppearance: WorkdayTickAppearance = .subtle,
        height: CGFloat = OpenBarMenuStyle.meterHeight)
    {
        self.percent = percent
        self.tint = tint
        self.accessibilityLabel = accessibilityLabel
        self.pacePercent = pacePercent
        self.paceOnTop = paceOnTop
        self.warningMarkerPercents = warningMarkerPercents
        self.workdayMarkerPercents = workdayMarkerPercents
        self.workdayTickAppearance = workdayTickAppearance
        self.height = height
    }

    private var clamped: Double {
        min(100, max(0, self.percent))
    }

    var body: some View {
        let layout = MeterLayout(
            fillPercent: Self.renderedFillPercent(self.clamped),
            pacePercent: self.pacePercent.map { Self.clampedPercent($0) },
            markers: Self.resolvedMarkers(
                warningPercents: self.warningMarkerPercents,
                workdayPercents: self.workdayMarkerPercents,
                workdayAppearance: self.workdayTickAppearance),
            workdayAppearance: self.workdayTickAppearance,
            scale: max(self.displayScale, 1))
        ZStack(alignment: .leading) {
            MeterShape(layout: layout, part: .track)
                .fill(MenuHighlightStyle.progressTrack(self.isHighlighted))
            MeterShape(layout: layout, part: .fill)
                .fill(MenuHighlightStyle.progressTint(self.isHighlighted, fallback: self.tint))
            if layout.pacePercent != nil {
                MeterShape(layout: layout, part: .paceTick)
                    .fill(MenuHighlightStyle.primary(self.isHighlighted))
            }
        }
        .frame(height: self.height)
        .accessibilityElement()
        .accessibilityLabel(self.accessibilityLabel)
        .accessibilityValue(self.markerAccessibilityValue)
    }

    private var markerAccessibilityValue: String {
        let percent = L("%d percent", Self.displayPercent(self.clamped))
        guard let markers = Self.markerAccessibilityText(
            warningPercents: self.warningMarkerPercents,
            workdayPercents: self.workdayMarkerPercents,
            workdayAppearance: self.workdayTickAppearance)
        else { return percent }
        return "\(percent). \(markers)"
    }

    /// Spoken marker summary ("Quota warnings: 50%, 80%. Work days: 20%, …"), or nil without markers.
    static func markerAccessibilityText(
        warningPercents: [Double],
        workdayPercents: [Double],
        workdayAppearance: WorkdayTickAppearance) -> String?
    {
        let markers = Self.resolvedMarkers(
            warningPercents: warningPercents,
            workdayPercents: workdayPercents,
            workdayAppearance: workdayAppearance)
        let warnings = markers.filter { $0.kind == .quotaWarning }.map(Self.markerPercentText)
        let workdays = markers.filter { $0.kind == .workdayBoundary }.map(Self.markerPercentText)
        var parts: [String] = []
        if !warnings.isEmpty {
            parts.append("\(L("quota_warnings_title")): \(warnings.joined(separator: ", "))")
        }
        if !workdays.isEmpty {
            parts.append("\(L("weekly_progress_work_days_title")): \(workdays.joined(separator: ", "))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ". ")
    }

    nonisolated static func resolvedMarkers(
        warningPercents: [Double],
        workdayPercents: [Double],
        workdayAppearance: WorkdayTickAppearance = .subtle) -> [Marker]
    {
        let warnings = Self.normalizedMarkerPercents(warningPercents)
        let workdays = workdayAppearance == .hidden ? [] : Self.normalizedMarkerPercents(workdayPercents)
            .filter { workday in !warnings.contains { abs($0 - workday) < 0.001 } }
        return (
            warnings.map { Marker(percent: $0, kind: .quotaWarning) } +
                workdays.map { Marker(percent: $0, kind: .workdayBoundary) })
            .sorted { lhs, rhs in lhs.percent < rhs.percent }
    }

    private nonisolated static func normalizedMarkerPercents(_ values: [Double]) -> [Double] {
        values
            .map(self.clampedPercent)
            .filter { $0 > 0 && $0 < 100 }
            .reduce(into: [Double]()) { result, value in
                if !result.contains(where: { abs($0 - value) < 0.001 }) {
                    result.append(value)
                }
            }
    }

    private nonisolated static func markerPercentText(_ marker: Marker) -> String {
        "\(Int(marker.percent.rounded()))%"
    }

    /// Aligns edge rendering with the rounded percent label: sub-0.5% is empty and 99.5%+ is full.
    nonisolated static func renderedFillPercent(_ percent: Double) -> Double {
        let clamped = Self.clampedPercent(percent)
        let displayPercent = Self.displayPercent(clamped)
        if displayPercent <= 0 { return 0 }
        if displayPercent >= 100 { return 100 }
        return clamped
    }

    /// The gap a quota-warning marker cuts through the fill and track: 1 pt, full height.
    nonisolated static func warningMarkerRect(x: CGFloat, size: CGSize, scale rawScale: CGFloat) -> CGRect {
        self.markerGapRect(x: x, width: OpenBarMenuStyle.meterMarkerGap, size: size, scale: rawScale)
    }

    /// The gap a workday boundary cuts through the fill and track: 1 pt, or 2 pt with the
    /// high-contrast tick appearance. Hidden ticks cut nothing.
    nonisolated static func workdayMarkerRect(
        x: CGFloat,
        size: CGSize,
        scale rawScale: CGFloat,
        appearance: WorkdayTickAppearance = .subtle) -> CGRect
    {
        switch appearance {
        case .hidden:
            .zero
        case .subtle:
            self.markerGapRect(x: x, width: OpenBarMenuStyle.meterMarkerGap, size: size, scale: rawScale)
        case .highContrast:
            self.markerGapRect(x: x, width: OpenBarMenuStyle.meterHighContrastMarkerGap, size: size, scale: rawScale)
        }
    }

    private nonisolated static func markerGapRect(
        x: CGFloat,
        width: CGFloat,
        size: CGSize,
        scale rawScale: CGFloat) -> CGRect
    {
        let scale = max(rawScale, 1)
        let minX = Self.align(x - width / 2, scale: scale)
        return CGRect(x: minX, y: 0, width: width, height: Self.align(size.height, scale: scale))
    }

    fileprivate nonisolated static func align(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }

    private nonisolated static func displayPercent(_ percent: Double) -> Int {
        Int(self.clampedPercent(percent).rounded())
    }

    fileprivate nonisolated static func clampedPercent(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        return min(100, max(0, value))
    }
}

/// Resolved meter inputs. Geometry is computed from the frame the shape is given, so the meter
/// needs no `GeometryReader`.
private struct MeterLayout: Equatable {
    let fillPercent: Double
    let pacePercent: Double?
    let markers: [UsageProgressBar.Marker]
    let workdayAppearance: WorkdayTickAppearance
    let scale: CGFloat

    func fillRange(width: CGFloat, height: CGFloat) -> ClosedRange<CGFloat>? {
        guard self.fillPercent > 0, width > 0 else { return nil }
        // A sliver still reads as a dot: never narrower than the meter is tall.
        let raw = max(height, width * self.fillPercent / 100)
        let end = min(width, UsageProgressBar.align(raw, scale: self.scale))
        return 0...end
    }

    func trackRange(width: CGFloat, height: CGFloat) -> ClosedRange<CGFloat>? {
        let start: CGFloat = if let fill = self.fillRange(width: width, height: height) {
            fill.upperBound + OpenBarMenuStyle.meterSplitGap
        } else {
            0
        }
        guard width - start >= 1 else { return nil }
        return start...width
    }

    func paceTickX(width: CGFloat) -> CGFloat? {
        guard let pacePercent else { return nil }
        let half = OpenBarMenuStyle.paceTickWidth / 2 + OpenBarMenuStyle.paceTickHalo
        let x = min(max(width * pacePercent / 100, half), max(half, width - half))
        return UsageProgressBar.align(x, scale: self.scale)
    }

    /// Gaps cut through both the fill and the track.
    func cuts(in rect: CGRect) -> Path {
        var path = Path()
        let size = rect.size
        let extended = { (gap: CGRect) in
            CGRect(x: gap.minX, y: rect.minY, width: gap.width, height: size.height).insetBy(dx: 0, dy: -size.height)
        }
        for marker in self.markers {
            let x = rect.minX + size.width * marker.percent / 100
            let gap = switch marker.kind {
            case .quotaWarning:
                UsageProgressBar.warningMarkerRect(x: x, size: size, scale: self.scale)
            case .workdayBoundary:
                UsageProgressBar.workdayMarkerRect(
                    x: x,
                    size: size,
                    scale: self.scale,
                    appearance: self.workdayAppearance)
            }
            if gap.width > 0 {
                path.addRect(extended(gap))
            }
        }
        if let tickX = self.paceTickX(width: size.width) {
            let width = OpenBarMenuStyle.paceTickWidth + OpenBarMenuStyle.paceTickHalo * 2
            path.addRect(extended(CGRect(
                x: rect.minX + tickX - width / 2,
                y: rect.minY,
                width: width,
                height: size.height)))
        }
        return path
    }
}

private struct MeterShape: Shape {
    enum Part {
        case track
        case fill
        case paceTick
    }

    let layout: MeterLayout
    let part: Part

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        switch self.part {
        case .track:
            guard let range = self.layout.trackRange(width: width, height: height) else { return Path() }
            return Self.capsule(range, in: rect).subtractingIfNeeded(self.layout.cuts(in: rect))
        case .fill:
            guard let range = self.layout.fillRange(width: width, height: height) else { return Path() }
            return Self.capsule(range, in: rect).subtractingIfNeeded(self.layout.cuts(in: rect))
        case .paceTick:
            guard let x = self.layout.paceTickX(width: width) else { return Path() }
            let tick = CGRect(
                x: rect.minX + x - OpenBarMenuStyle.paceTickWidth / 2,
                y: rect.midY - OpenBarMenuStyle.paceTickHeight / 2,
                width: OpenBarMenuStyle.paceTickWidth,
                height: OpenBarMenuStyle.paceTickHeight)
            return Path(roundedRect: tick, cornerRadius: OpenBarMenuStyle.paceTickWidth / 2)
        }
    }

    private static func capsule(_ range: ClosedRange<CGFloat>, in rect: CGRect) -> Path {
        let segment = CGRect(
            x: rect.minX + range.lowerBound,
            y: rect.minY,
            width: range.upperBound - range.lowerBound,
            height: rect.height)
        return Path(roundedRect: segment, cornerRadius: min(segment.width, segment.height) / 2)
    }
}

extension Path {
    fileprivate func subtractingIfNeeded(_ cuts: Path) -> Path {
        cuts.isEmpty ? self : self.subtracting(cuts)
    }
}
