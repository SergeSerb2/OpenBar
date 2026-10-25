import AppKit
import OpenBarCore

/// OpenBar's "Meter bars" menu bar glyph (docs/design/README.md §9.1, as revised by the design council).
///
/// Two continuous capsule rails, each filled from the leading edge up to a straight level edge, and at most
/// one mark in the top-right corner. The mark carries state without color, so the glyph warns at a glance:
/// a dot for low quota or a minor incident, a ring for stale data, and an exclamation for critical or
/// exhausted quota or a major incident. Each mark clears a 1-point halo out of the rails.
///
/// The image is a template with a 1x and a 2x representation, each drawn on its own pixel grid. Images are
/// cached by what they draw, so a redraw happens only when a fill crosses a pixel or the layout, mark,
/// stale state, or accessibility display options change.
enum MeterBarsGlyph {
    /// Fill of one rail, quantized to the 2x pixel grid.
    enum Lane: Hashable {
        /// Filled pixels on the 2x grid, `0...railLengthPx`.
        case fill(Int)
        /// The lane exists but has no value, such as a plan without a weekly quota.
        case missing
    }

    enum Layout: Hashable {
        /// Session rail over a thinner weekly rail.
        case pair(primary: Lane, secondary: Lane)
        /// One meaningful quota: a single 6-point rail, centered.
        case single(Lane)
        /// Credits only: a single rail at the session rail's height, centered.
        case credits(Lane)
    }

    /// Ordered by severity: a stronger mark replaces a weaker one.
    enum Mark: Int, Hashable, Comparable {
        case none
        case dot
        case ring
        case exclamation

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        init(indicator: ProviderStatusIndicator) {
            switch indicator {
            case .none: self = .none
            case .minor, .maintenance: self = .dot
            case .major, .critical, .unknown: self = .exclamation
            }
        }

        init(tone: OpenBarQuotaTone) {
            switch tone {
            case .normal: self = .none
            case .warning: self = .dot
            case .stale: self = .ring
            case .critical: self = .exclamation
            }
        }
    }

    /// How the caller's lane values read. Quota marks always judge the *remaining* quota, whatever the
    /// "show used" display setting; animated or unclassified values never produce quota marks.
    enum LaneValues: Hashable {
        case remaining
        case used
        case unrated

        func remaining(_ value: Double) -> Double? {
            switch self {
            case .remaining: value
            case .used: 100 - value
            case .unrated: nil
            }
        }
    }

    /// Accessibility display options that change the drawing. Part of the cache key.
    struct DisplayOptions: Hashable {
        var increasedContrast: Bool
        var reduceTransparency: Bool

        static let standard = Self(increasedContrast: false, reduceTransparency: false)

        static var current: Self {
            let workspace = NSWorkspace.shared
            return Self(
                increasedContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
                reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency)
        }

        var trackAlpha: Double {
            if self.increasedContrast { return OpenBarGlyphMetrics.trackAlphaHighContrast }
            if self.reduceTransparency { return OpenBarGlyphMetrics.trackAlphaReducedTransparency }
            return OpenBarGlyphMetrics.trackAlpha
        }
    }

    struct Key: Hashable {
        let layout: Layout
        let mark: Mark
        let stale: Bool
        let display: DisplayOptions
    }

    /// Rail length on the 2x grid (16 points).
    static let railLengthPx = 32

    static func lane(_ percent: Double?) -> Lane {
        guard let percent else { return .missing }
        guard percent > 0 else { return .fill(0) }
        let minimum = Int((OpenBarGlyphMetrics.minimumFill * 2).rounded())
        let pixels = Int((Double(Self.railLengthPx) * min(percent, 100) / 100).rounded())
        return .fill(min(Self.railLengthPx, max(minimum, pixels)))
    }

    // MARK: Layout

    // swiftlint:disable function_parameter_count
    /// Chooses the rails exactly as the legacy meter did (provider layout policy, credits fallback, a missing
    /// or exhausted secondary lane), then picks the strongest mark from the incident, stale state, and quota.
    static func key(
        primary topValue: Double?,
        weekly weeklyValue: Double?,
        creditsPercent: Double?,
        stale: Bool,
        indicator: ProviderStatusIndicator,
        policy: IconRenderer.QuotaLayoutPolicy,
        laneValues: LaneValues,
        display: DisplayOptions) -> Key
    {
        let usesMissingSecondaryLayout = policy.treatsExhaustedSecondaryAsMissing
        let bottomValue: Double? = if usesMissingSecondaryLayout, let weeklyValue, weeklyValue <= 0 {
            nil
        } else {
            weeklyValue
        }
        let hasWeekly = bottomValue != nil
        let weeklyAvailable = hasWeekly && (bottomValue ?? 0) > 0

        let layout: Layout
        var quotaValues: [Double?] = []
        if let bottomValue, bottomValue > 0, topValue == nil, !policy.reservesMissingSecondaryLane,
           !usesMissingSecondaryLayout
        {
            // Some providers surface their only meaningful quota in the secondary slot.
            layout = .single(self.lane(bottomValue))
            quotaValues = [bottomValue]
        } else if weeklyAvailable {
            layout = .pair(primary: self.lane(topValue), secondary: self.lane(bottomValue))
            quotaValues = [topValue, bottomValue]
        } else if !hasWeekly || (usesMissingSecondaryLayout && !weeklyAvailable) {
            if usesMissingSecondaryLayout {
                layout = .pair(primary: self.lane(topValue), secondary: .missing)
                quotaValues = [topValue]
            } else if topValue == nil, let creditsPercent {
                layout = .credits(self.lane(creditsPercent))
            } else if !policy.reservesMissingSecondaryLane, let topValue {
                // One meaningful quota reads as one meter; a reserved empty lane would halve it visually.
                layout = .single(self.lane(topValue))
                quotaValues = [topValue]
            } else {
                layout = .pair(primary: self.lane(topValue), secondary: .missing)
                quotaValues = [topValue]
            }
        } else if let creditsPercent {
            // Weekly exhausted: credits take the session rail, the empty weekly lane stays below.
            layout = .pair(primary: self.lane(creditsPercent), secondary: self.lane(bottomValue))
            quotaValues = [bottomValue]
        } else {
            layout = .pair(primary: self.lane(topValue), secondary: self.lane(bottomValue))
            quotaValues = [topValue, bottomValue]
        }

        var mark = Mark(indicator: indicator)
        if stale {
            mark = max(mark, .ring)
        } else {
            for value in quotaValues.compactMap(\.self) {
                guard let remaining = laneValues.remaining(value) else { break }
                let tone = OpenBarQuotaTone.resolve(remainingPercent: remaining, isStale: false)
                mark = max(mark, Mark(tone: tone))
            }
        }
        return Key(layout: layout, mark: mark, stale: stale, display: display)
    }

    // swiftlint:enable function_parameter_count

    // MARK: Rendering

    static func makeImage(_ key: Key) -> NSImage {
        let size = NSSize(width: OpenBarGlyphMetrics.canvasWidth, height: OpenBarGlyphMetrics.canvasHeight)
        let image = NSImage(size: size)
        for scale in [2, 1] {
            if let rep = self.bitmap(key, scale: scale, size: size) {
                image.addRepresentation(rep)
            }
        }
        image.isTemplate = true
        return image
    }

    private static func bitmap(_ key: Key, scale: Int, size: NSSize) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width) * scale,
            pixelsHigh: Int(size.height) * scale,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0)
        else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = context
        let canvas = GlyphCanvas(cgContext: context.cgContext, scale: scale, size: size)
        self.draw(key, on: canvas)
        return rep
    }

    /// Glyph geometry is written with a top-left origin, as in the spec; `rect` flips it into the
    /// bitmap's bottom-left origin.
    struct GlyphCanvas {
        let cgContext: CGContext
        let scale: Int
        let size: CGSize

        var isRetina: Bool {
            self.scale >= 2
        }

        func rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
            CGRect(x: x, y: self.size.height - y - height, width: width, height: height)
        }
    }

    private struct Rail {
        let y: CGFloat
        let height: CGFloat
    }

    private static let railX: CGFloat = 1
    private static let railLength: CGFloat = 16

    /// Rail rows per layout. The 1x grid snaps to whole pixels; a 3.5-point rail would blur there.
    private static func rails(_ layout: Layout, canvas: GlyphCanvas) -> [(Rail, Lane)] {
        switch layout {
        case let .pair(primary, secondary):
            canvas.isRetina
                ? [(Rail(y: 3.5, height: 5), primary), (Rail(y: 11, height: 3.5), secondary)]
                : [(Rail(y: 4, height: 5), primary), (Rail(y: 11, height: 3), secondary)]
        case let .single(lane):
            [(Rail(y: 6, height: 6), lane)]
        case let .credits(lane):
            [(Rail(y: canvas.isRetina ? 6.5 : 7, height: 5), lane)]
        }
    }

    private static func draw(_ key: Key, on canvas: GlyphCanvas) {
        let context = canvas.cgContext
        context.setShouldAntialias(true)
        let railAlpha = key.stale ? OpenBarGlyphMetrics.staleRailAlpha : 1
        let markOrigin = CGPoint(x: 0, y: Self.markDrop(for: key.layout))

        context.saveGState()
        if let halo = self.haloPath(key.mark, origin: markOrigin, canvas: canvas) {
            // Even-odd clip: the rails draw everywhere except inside the halo. Geometry, not a mask.
            let clip = CGMutablePath()
            clip.addRect(CGRect(origin: .zero, size: canvas.size))
            clip.addPath(halo)
            context.addPath(clip)
            context.clip(using: .evenOdd)
        }
        for (rail, lane) in self.rails(key.layout, canvas: canvas) {
            self.drawRail(rail, lane: lane, railAlpha: railAlpha, trackAlpha: key.display.trackAlpha, canvas: canvas)
        }
        context.restoreGState()

        self.drawMark(key.mark, origin: markOrigin, canvas: canvas)
    }

    private static func drawRail(_ rail: Rail, lane: Lane, railAlpha: Double, trackAlpha: Double, canvas: GlyphCanvas) {
        let context = canvas.cgContext
        let bounds = canvas.rect(x: self.railX, y: rail.y, width: self.railLength, height: rail.height)
        let capsule = CGPath(
            roundedRect: bounds,
            cornerWidth: rail.height / 2,
            cornerHeight: rail.height / 2,
            transform: nil)

        guard case let .fill(fillPx) = lane else {
            context.setFillColor(CGColor(gray: 0, alpha: OpenBarGlyphMetrics.missingLaneAlpha * railAlpha))
            context.addPath(capsule)
            context.fillPath()
            return
        }

        // Fill and track split the capsule at one pixel edge, so their alphas never stack.
        let pixels = canvas.isRetina ? fillPx : Int((Double(fillPx) / 2).rounded())
        let fillWidth = CGFloat(pixels) / CGFloat(canvas.scale)
        context.saveGState()
        context.addPath(capsule)
        context.clip()
        if fillWidth < self.railLength {
            context.setFillColor(CGColor(gray: 0, alpha: trackAlpha * railAlpha))
            context.fill(CGRect(
                x: bounds.minX + fillWidth,
                y: bounds.minY,
                width: bounds.width - fillWidth,
                height: bounds.height))
        }
        if fillWidth > 0 {
            context.setFillColor(CGColor(gray: 0, alpha: railAlpha))
            context.fill(CGRect(x: bounds.minX, y: bounds.minY, width: fillWidth, height: bounds.height))
        }
        context.restoreGState()
    }

    // MARK: Marks

    /// Over a single centered rail the dot and ring drop 3 points, so they still sit on the rail's
    /// corner instead of floating above it. The exclamation already reaches the rail.
    private static func markDrop(for layout: Layout) -> CGFloat {
        if case .pair = layout { return 0 }
        return 3
    }

    /// On the 2x grid the dot sits half a point lower so its halo bites visibly into the session rail's
    /// rounded end; the 1x grid keeps it on whole pixels.
    private static func dotNudge(_ canvas: GlyphCanvas) -> CGFloat {
        canvas.isRetina ? 0.5 : 0
    }

    /// Mark geometry on an 18-point canvas. `origin.x` shifts the mark sideways (wider canvases);
    /// `origin.y` drops the dot and ring.
    static func haloPath(_ mark: Mark, origin: CGPoint, canvas: GlyphCanvas) -> CGPath? {
        let x = origin.x
        let y = origin.y
        let path = CGMutablePath()
        switch mark {
        case .none:
            return nil
        case .dot:
            let dotY = y + Self.dotNudge(canvas)
            path.addEllipse(in: canvas.rect(x: x + 13, y: dotY - 1, width: 6, height: 6))
        case .ring:
            path.addEllipse(in: canvas.rect(x: x + 11, y: y - 1, width: 8, height: 8))
        case .exclamation:
            path.addRoundedRect(
                in: canvas.rect(x: x + 15, y: -1, width: 4, height: 8),
                cornerWidth: 2,
                cornerHeight: 2)
            path.addEllipse(in: canvas.rect(x: x + 15, y: 7, width: 4, height: 4))
        }
        return path
    }

    static func drawMark(_ mark: Mark, origin: CGPoint, canvas: GlyphCanvas) {
        let context = canvas.cgContext
        let x = origin.x
        let y = origin.y
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        switch mark {
        case .none:
            return
        case .dot:
            context.fillEllipse(in: canvas.rect(x: x + 14, y: y + Self.dotNudge(canvas), width: 4, height: 4))
        case .ring:
            let ring = CGMutablePath()
            ring.addEllipse(in: canvas.rect(x: x + 12, y: y, width: 6, height: 6))
            ring.addEllipse(in: canvas.rect(x: x + 13.5, y: y + 1.5, width: 3, height: 3))
            context.addPath(ring)
            context.fillPath(using: .evenOdd)
        case .exclamation:
            let bar = canvas.rect(x: x + 16, y: 0, width: 2, height: 6)
            context.addPath(CGPath(roundedRect: bar, cornerWidth: 1, cornerHeight: 1, transform: nil))
            context.fillPath()
            context.fillEllipse(in: canvas.rect(x: x + 16, y: 8, width: 2, height: 2))
        }
    }
}
