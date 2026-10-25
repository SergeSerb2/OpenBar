import AppKit
import OpenBarCore
@testable import OpenBar

/// Menu bar glyph states drawn by the production renderers: real size at 2x and 1x, zoomed pixels,
/// Increase Contrast, loading frames, the quota warning flash, and Icon & percent layouts.
/// Owner during the redesign: the Glyph agent (see docs/design/README.md, work split).
/// Critters are a legacy opt-in style and are deliberately not shown here.
@MainActor
enum GalleryMenuBarSection {
    struct GlyphState {
        let label: String
        var primary: Double?
        var weekly: Double?
        var credits: Double?
        var stale = false
        var indicator: ProviderStatusIndicator = .none
        var policy: UsageProvider = .claude
        var showsUsed = false
    }

    static let states: [GlyphState] = [
        GlyphState(label: "Full", primary: 100, weekly: 100),
        GlyphState(label: "Typical", primary: 62, weekly: 41),
        GlyphState(label: "Warning", primary: 18, weekly: 55),
        GlyphState(label: "Critical", primary: 6, weekly: 30),
        GlyphState(label: "Exhausted", primary: 0, weekly: 12),
        GlyphState(label: "Stale", primary: 62, weekly: 41, stale: true),
        GlyphState(label: "No weekly", primary: 62, weekly: nil),
        GlyphState(label: "One quota", primary: 46, weekly: nil, policy: .codex),
        GlyphState(label: "Credits only", primary: nil, weekly: nil, credits: 640, policy: .codex),
        GlyphState(label: "Weekly out", primary: 62, weekly: 0, credits: 640, policy: .codex),
        GlyphState(label: "Show used", primary: 38, weekly: 59, showsUsed: true),
        GlyphState(label: "Minor issue", primary: 62, weekly: 41, indicator: .minor),
        GlyphState(label: "Outage", primary: 62, weekly: 41, indicator: .major),
        GlyphState(label: "Warning + stale", primary: 18, weekly: 55, stale: true),
    ]

    static func render(_ gallery: GalleryWriter) throws {
        // Fixed time zone for reset times, so renders repeat on any machine. Gallery only.
        let savedTimeZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "America/Vancouver") ?? savedTimeZone
        defer { NSTimeZone.default = savedTimeZone }
        try self.renderGlyphStates(gallery)
        try self.renderLoading(gallery)
        try self.renderWarningFlash(gallery)
        try self.renderLayouts(gallery)
        try GalleryOverlaysSection.render(gallery)
    }

    // MARK: Glyph states

    private static func glyph(
        _ state: GlyphState,
        display: MeterBarsGlyph.DisplayOptions = .standard) -> NSImage
    {
        IconRenderer.makeIcon(
            primaryRemaining: state.primary,
            weeklyRemaining: state.weekly,
            creditsRemaining: state.credits,
            stale: state.stale,
            style: .combined,
            statusIndicator: state.indicator,
            hideCritters: true,
            quotaLayoutPolicy: .provider(state.policy),
            laneValues: state.showsUsed ? .used : .remaining,
            displayOptions: display)
    }

    private static func renderGlyphStates(_ gallery: GalleryWriter) throws {
        let regular = self.states.map { self.glyph($0) }
        let contrast = self.states.map {
            self.glyph($0, display: .init(increasedContrast: true, reduceTransparency: false))
        }
        let opaque = self.states.map {
            self.glyph($0, display: .init(increasedContrast: false, reduceTransparency: true))
        }
        let labels = self.states.map(\.label)
        try gallery.add(
            section: "menubar",
            title: "Meter bars · every state at real size (2x and 1x displays)",
            name: "meter-bars-actual",
            note: labels.joined(separator: " · ")
                + ". Rows: 2x display, 1x display (each 1x pixel shown as one point), Increase Contrast (IC) "
                + "at 2x and 1x, Reduce Transparency (RT) at 2x.")
        { appearance in
            try GalleryCapture.appKit(
                self.table(
                    rows: [
                        ("2x", regular.map { self.imageView($0, zoom: 1) }),
                        ("1x", regular.map { self.imageView(self.oneXPixels($0, magnify: 2), zoom: 1) }),
                        ("IC 2x", contrast.map { self.imageView($0, zoom: 1) }),
                        ("IC 1x", contrast.map { self.imageView(self.oneXPixels($0, magnify: 2), zoom: 1) }),
                        ("RT 2x", opaque.map { self.imageView($0, zoom: 1) }),
                    ],
                    columnLabels: labels,
                    spacing: 14),
                appearance: appearance,
                backdrop: appearance.menuBarBackdrop,
                padding: 8)
        }
        try gallery.add(
            section: "menubar",
            title: "Meter bars · zoomed 4× (2x pixels, 1x pixels, Increase Contrast)",
            name: "meter-bars-zoom",
            note: "Each 2x image pixel is 2 output pixels; each 1x image pixel is 8 output pixels.")
        { appearance in
            try GalleryCapture.appKit(
                self.table(
                    rows: [
                        ("2x", regular.map { self.imageView($0, zoom: 4) }),
                        ("1x", regular.map { self.imageView(self.oneXPixels($0, magnify: 8), zoom: 1) }),
                        ("IC 2x", contrast.map { self.imageView($0, zoom: 4) }),
                        ("IC 1x", contrast.map { self.imageView(self.oneXPixels($0, magnify: 8), zoom: 1) }),
                    ],
                    columnLabels: labels,
                    spacing: 18),
                appearance: appearance,
                backdrop: appearance.menuBarBackdrop,
                padding: 10)
        }
    }

    private static func renderLoading(_ gallery: GalleryWriter) throws {
        let phases: [Double] = [0, .pi / 4, .pi / 2, .pi * 3 / 4, .pi]
        let pattern = LoadingPattern.knightRider
        let frames = phases.map { phase in
            IconRenderer.makeIcon(
                primaryRemaining: max(pattern.value(phase: phase), 0.0001),
                weeklyRemaining: max(pattern.value(phase: phase + pattern.secondaryOffset), 0.0001),
                creditsRemaining: nil,
                stale: false,
                style: .combined,
                hideCritters: true,
                quotaLayoutPolicy: .provider(.claude),
                displayOptions: .standard)
        }
        let morph = [0, 0.25, 0.5, 0.75, 1].map {
            IconRenderer.makeMorphIcon(progress: $0, style: .combined, hideCritters: true)
        }
        try gallery.add(
            section: "menubar",
            title: "Meter bars · loading frames, zoomed 4×",
            name: "meter-bars-loading",
            note: "Knight Rider at five phases, then the Unbraid morph at 0, 25, 50, 75, 100 %.")
        { appearance in
            try GalleryCapture.appKit(
                self.table(
                    rows: [
                        ("Rider", frames.map { self.imageView($0, zoom: 4) }),
                        ("Morph", morph.map { self.imageView($0, zoom: 4) }),
                    ],
                    columnLabels: nil,
                    spacing: 18),
                appearance: appearance,
                backdrop: appearance.menuBarBackdrop,
                padding: 10)
        }
    }

    private static func renderWarningFlash(_ gallery: GalleryWriter) throws {
        let glyph = self.glyph(self.states[1])
        let brand = ProviderBrandIcon.image(for: .claude) ?? glyph
        let images = [glyph, brand].map { StatusItemController.quotaWarningFlashImage(base: $0) }
        try gallery.add(
            section: "menubar",
            title: "Quota warning flash · real size and 4×",
            name: "warning-flash",
            note: "Meter bars glyph and the provider logo (Icon & percent) during the 60 s warning flash.")
        { appearance in
            try GalleryCapture.appKit(
                self.table(
                    rows: [
                        ("1×", images.map { self.imageView($0, zoom: 1, tint: false) }),
                        ("4×", images.map { self.imageView($0, zoom: 4, tint: false) }),
                    ],
                    columnLabels: nil,
                    spacing: 18),
                appearance: appearance,
                backdrop: appearance.menuBarBackdrop,
                padding: 10)
        }
    }

    // MARK: Icon & percent layouts

    private struct LayoutSample {
        let label: String
        let lines: [[MenuBarLayoutToken]]
        var colorPace = false
        var stale = false
    }

    private static let layoutSamples: [LayoutSample] = [
        LayoutSample(label: "Percent", lines: [[.icon, .percent(window: .automatic)]]),
        LayoutSample(label: "Pace", lines: [[.icon, .pace(window: .weekly)]]),
        LayoutSample(
            label: "Both",
            lines: [[.icon, .percent(window: .automatic), .separatorDot, .pace(window: .weekly)]]),
        LayoutSample(label: "Reset time", lines: [[.icon, .resetAbsolute]]),
        LayoutSample(
            label: "Colored pace (opt-in)",
            lines: [[.icon, .percent(window: .automatic), .separatorDot, .pace(window: .weekly)]],
            colorPace: true),
        LayoutSample(
            label: "Progress bar",
            lines: [[.icon, .progressBar(window: .session), .windowResetCountdown(window: .session)]]),
        LayoutSample(label: "Bars stacked", lines: [
            [.progressBar(window: .session), .windowResetCountdown(window: .session)],
            [.progressBar(window: .weekly), .windowResetCountdown(window: .weekly)],
        ]),
        LayoutSample(label: "Tokens / min", lines: [[.icon, .tokensSparkline]]),
        LayoutSample(
            label: "Stale",
            lines: [[.icon, .percent(window: .automatic), .progressBar(window: .weekly)]],
            stale: true),
    ]

    private static func renderLayouts(_ gallery: GalleryWriter) throws {
        try gallery.add(
            section: "menubar",
            title: "Icon & percent · layouts rendered through MenuBarLayoutRenderer",
            name: "icon-percent",
            note: self.layoutSamples.map(\.label).joined(separator: " · "))
        { appearance in
            let rows = self.layoutSamples.map { sample in
                (sample.label, [self.layoutButton(sample, appearance: appearance)] as [NSView])
            }
            return try GalleryCapture.appKit(
                self.table(rows: rows, columnLabels: nil, spacing: 10, labelWidth: 130),
                appearance: appearance,
                backdrop: appearance.menuBarBackdrop,
                padding: 8)
        }
    }

    private static func layoutButton(_ sample: LayoutSample, appearance: GalleryAppearance) -> NSView {
        let now = GalleryFixtures.now
        let session = RateWindow(
            usedPercent: 38,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(2 * 3600 + 14 * 60),
            resetDescription: nil)
        let weekly = RateWindow(
            usedPercent: 59,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(3 * 86400),
            resetDescription: nil)
        let metrics = MenuBarLayoutRenderMetrics(
            sessionPaceDelta: -4,
            weeklyPaceDelta: 11,
            automaticPaceDelta: -4,
            runsOutMinutes: nil,
            balanceRemainingUSD: nil,
            balanceUsedUSD: nil,
            costTodayUSD: nil,
            cost30dUSD: nil)
        var data = MenuBarLayoutRenderData(
            provider: .claude,
            iconKey: "gallery-claude",
            providerName: "Claude",
            accountLabel: nil,
            laneLabels: MenuBarLayoutLaneLabels(provider: .claude, snapshot: nil),
            primary: MenuBarLayoutRenderWindow(session),
            secondary: MenuBarLayoutRenderWindow(weekly),
            tertiary: nil,
            session: MenuBarLayoutRenderWindow(session),
            weekly: MenuBarLayoutRenderWindow(weekly),
            scopedWeekly: nil,
            scopedWeeklyTitle: nil,
            automatic: MenuBarLayoutRenderWindow(session),
            automaticText: nil,
            sessionPace: "-4%",
            weeklyPace: "+11%",
            automaticPace: "-4%",
            runsOut: "Runs out in 2d 2h",
            balance: nil,
            costToday: nil,
            cost30d: nil,
            metrics: metrics)
        data.tokensSparkline = MenuBarTokensSparkline(
            values: [2, 3, 1, 4, 6, 5, 8, 7, 9, 6, 4, 5, 7, 10, 8, 6, 9, 12],
            latest: 12400)
        let rendered = MenuBarLayoutRenderer().render(
            layout: MenuBarLayout(lines: sample.lines),
            data: data,
            icon: ProviderBrandIcon.image(for: .claude),
            options: MenuBarLayoutRenderOptions(
                size: .regular,
                highContrast: false,
                showUsed: false,
                conditionals: [],
                appearanceName: appearance.name.rawValue,
                isDebugApp: false,
                isStale: sample.stale,
                now: now,
                verticalAdjustment: 0,
                colorPace: sample.colorPace))
        let button = NSButton(frame: CGRect(x: 0, y: 0, width: 200, height: 22))
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.font = NSFont.menuBarFont(ofSize: 0)
        let width = StatusItemController.applyMenuBarLayoutContent(rendered, for: button, gap: .regular)
        button.frame.size = CGSize(width: max(width, button.fittingSize.width), height: 22)
        button.widthAnchor.constraint(equalToConstant: button.frame.width).isActive = true
        button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return button
    }

    // MARK: Helpers

    /// What a 1x display shows: the image drawn into an 18 × 18 px context (AppKit picks the 1x
    /// representation when one exists, otherwise it downsamples the 2x one), then each pixel copied
    /// to a `magnify` × `magnify` block so the gallery's 2x capture shows the real pixels.
    static func oneXPixels(_ image: NSImage, magnify: Int) -> NSImage {
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        guard let small = self.bitmap(width: width, height: height),
              let big = self.bitmap(width: width * magnify, height: height * magnify)
        else { return image }
        small.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        for y in 0..<height {
            for x in 0..<width {
                let color = small.colorAt(x: x, y: y) ?? .clear
                for dy in 0..<magnify {
                    for dx in 0..<magnify {
                        big.setColor(color, atX: x * magnify + dx, y: y * magnify + dy)
                    }
                }
            }
        }
        big.size = CGSize(width: CGFloat(width * magnify) / 2, height: CGFloat(height * magnify) / 2)
        let output = NSImage(size: big.size)
        output.addRepresentation(big)
        output.isTemplate = image.isTemplate
        return output
    }

    private static func bitmap(width: Int, height: Int) -> NSBitmapImageRep? {
        NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0)
    }

    static func imageView(_ image: NSImage, zoom: CGFloat, tint: Bool = true) -> NSView {
        let view = NSImageView(image: image)
        view.imageScaling = .scaleProportionallyUpOrDown
        if tint {
            view.contentTintColor = .labelColor
        }
        let size = NSSize(width: image.size.width * zoom, height: image.size.height * zoom)
        view.frame.size = size
        view.widthAnchor.constraint(equalToConstant: size.width).isActive = true
        view.heightAnchor.constraint(equalToConstant: size.height).isActive = true
        return view
    }

    static func label(_ text: String, width: CGFloat? = nil) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 9)
        field.textColor = .secondaryLabelColor
        if let width {
            field.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        return field
    }

    /// Grid of image rows with a leading row label and optional column captions.
    static func table(
        rows: [(String, [NSView])],
        columnLabels: [String]?,
        spacing: CGFloat,
        labelWidth: CGFloat = 40) -> NSView
    {
        var gridRows: [[NSView]] = rows.map { [self.label($0.0, width: labelWidth)] + $0.1 }
        if let columnLabels {
            gridRows.append([NSGridCell.emptyContentView] + columnLabels.map { self.label($0) })
        }
        let grid = NSGridView(views: gridRows)
        grid.columnSpacing = spacing
        grid.rowSpacing = 8
        grid.yPlacement = .center
        grid.xPlacement = .center
        grid.column(at: 0).xPlacement = .leading
        grid.frame = CGRect(origin: .zero, size: grid.fittingSize)
        return grid
    }
}
