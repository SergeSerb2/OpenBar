import AppKit
import OpenBarCore
@testable import OpenBar

/// Menu bar glyph states drawn by the production renderers, at real size and zoomed.
/// Owner during the redesign: the Glyph agent (see docs/design/README.md, work split).
@MainActor
enum GalleryMenuBarSection {
    struct GlyphState {
        let label: String
        let primary: Double?
        let weekly: Double?
        let credits: Double?
        let stale: Bool
        let indicator: ProviderStatusIndicator
    }

    static let states: [GlyphState] = [
        GlyphState(label: "Full", primary: 100, weekly: 100, credits: nil, stale: false, indicator: .none),
        GlyphState(label: "Typical", primary: 62, weekly: 41, credits: nil, stale: false, indicator: .none),
        GlyphState(label: "Warning", primary: 18, weekly: 55, credits: nil, stale: false, indicator: .none),
        GlyphState(label: "Critical", primary: 6, weekly: 30, credits: nil, stale: false, indicator: .none),
        GlyphState(label: "Exhausted", primary: 0, weekly: 12, credits: nil, stale: false, indicator: .none),
        GlyphState(label: "Stale", primary: 62, weekly: 41, credits: nil, stale: true, indicator: .none),
        GlyphState(label: "No weekly", primary: 62, weekly: nil, credits: nil, stale: false, indicator: .none),
        GlyphState(label: "Credits only", primary: nil, weekly: nil, credits: 640, stale: false, indicator: .none),
        GlyphState(label: "Minor issue", primary: 62, weekly: 41, credits: nil, stale: false, indicator: .minor),
        GlyphState(label: "Outage", primary: 62, weekly: 41, credits: nil, stale: false, indicator: .major),
    ]

    static func render(_ gallery: GalleryWriter) throws {
        let style = ProviderDescriptorRegistry.descriptor(for: .claude).branding.iconStyle
        for (styleName, hideCritters) in [("Meter bars", true), ("Critters", false)] {
            let images = self.states.map { state in
                IconRenderer.makeIcon(
                    primaryRemaining: state.primary,
                    weeklyRemaining: state.weekly,
                    creditsRemaining: state.credits,
                    stale: state.stale,
                    style: style,
                    statusIndicator: state.indicator,
                    hideCritters: hideCritters,
                    quotaLayoutPolicy: .provider(.claude))
            }
            let slug = styleName.lowercased().replacingOccurrences(of: " ", with: "-")
            try gallery.add(
                section: "menubar",
                title: "\(styleName) · states at real size",
                name: "\(slug)-actual",
                note: self.states.map(\.label).joined(separator: " · "))
            { appearance in
                try GalleryCapture.appKit(
                    self.strip(images, zoom: 1),
                    appearance: appearance,
                    backdrop: appearance.menuBarBackdrop,
                    padding: 6)
            }
            try gallery.add(section: "menubar", title: "\(styleName) · zoomed 4×", name: "\(slug)-zoom") { appearance in
                try GalleryCapture.appKit(
                    self.strip(images, zoom: 4),
                    appearance: appearance,
                    backdrop: appearance.menuBarBackdrop,
                    padding: 8)
            }
        }

        try gallery.add(
            section: "menubar",
            title: "Icon & percent · Claude",
            name: "icon-percent",
            note: "MenuBarLayoutRenderer output for the icon + automatic percent + pace + runs-out layout.")
        { appearance in
            try GalleryCapture.appKit(
                self.layoutTitle(appearance: appearance),
                appearance: appearance,
                backdrop: appearance.menuBarBackdrop,
                padding: 6)
        }
    }

    private static func strip(_ images: [NSImage], zoom: CGFloat) -> NSView {
        let views = images.map { image -> NSView in
            let view = NSImageView(image: image)
            view.imageScaling = .scaleProportionallyUpOrDown
            view.contentTintColor = .labelColor
            view.frame.size = NSSize(width: image.size.width * zoom, height: image.size.height * zoom)
            view.widthAnchor.constraint(equalToConstant: view.frame.width).isActive = true
            view.heightAnchor.constraint(equalToConstant: view.frame.height).isActive = true
            return view
        }
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 12 * zoom
        stack.frame = CGRect(origin: .zero, size: stack.fittingSize)
        return stack
    }

    private static func layoutTitle(appearance: GalleryAppearance) -> NSView {
        let data = MenuBarLayoutRenderData(
            provider: .claude,
            iconKey: "gallery-claude",
            providerName: "Claude",
            accountLabel: nil,
            laneLabels: MenuBarLayoutLaneLabels(provider: .claude, snapshot: nil),
            primary: nil,
            secondary: nil,
            tertiary: nil,
            session: nil,
            weekly: nil,
            scopedWeekly: nil,
            scopedWeeklyTitle: nil,
            automatic: nil,
            automaticText: "62%",
            sessionPace: nil,
            weeklyPace: "+11%",
            automaticPace: nil,
            runsOut: "Runs out in 2d 2h",
            balance: nil,
            costToday: nil,
            cost30d: nil,
            metrics: .unavailable)
        let rendered = MenuBarLayoutRenderer().render(
            layout: MenuBarLayout(lines: [[
                .icon,
                .percent(window: .automatic),
                .pace(window: .weekly),
                .runsOutCompact,
            ]]),
            data: data,
            icon: ProviderBrandIcon.image(for: .claude),
            options: MenuBarLayoutRenderOptions(
                size: .regular,
                highContrast: false,
                showUsed: false,
                conditionals: [],
                appearanceName: appearance.name.rawValue,
                isDebugApp: false,
                isStale: false,
                now: GalleryFixtures.now,
                verticalAdjustment: 0))
        var views: [NSView] = []
        if let icon = rendered.leadingIcon {
            let view = NSImageView(image: icon)
            view.contentTintColor = .labelColor
            views.append(view)
        }
        views.append(NSTextField(labelWithAttributedString: rendered.attributedTitle))
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.frame = CGRect(origin: .zero, size: stack.fittingSize)
        return stack
    }
}
