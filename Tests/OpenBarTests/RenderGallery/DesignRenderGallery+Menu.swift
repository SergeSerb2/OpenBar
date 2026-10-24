import AppKit
import OpenBarCore
import SwiftUI
@testable import OpenBar

/// Menu surfaces: provider cards, the provider switcher, and a composite of the open menu.
/// Owner during the redesign: the Menu agent (see docs/design/README.md, work split).
@MainActor
enum GalleryMenuSection {
    static let menuWidth: CGFloat = 310

    static func render(_ gallery: GalleryWriter) throws {
        for fixture in GalleryFixtures.providers {
            guard let model = GalleryFixtures.menuCardModel(fixture) else { continue }
            let name = ProviderDefaults.metadata[fixture.provider]?.displayName ?? fixture.provider.rawValue
            try gallery.add(
                section: "menu",
                title: "Card · \(name)",
                name: "card-\(fixture.provider.rawValue)",
                note: "UsageMenuCardView, \(Int(self.menuWidth)) pt wide, on an opaque stand-in for menu glass.")
            { appearance in
                try GalleryCapture.appKit(
                    self.cardRow(model: model),
                    appearance: appearance,
                    backdrop: appearance.menuBackdrop)
            }
        }

        try gallery.add(
            section: "menu",
            title: "Provider switcher",
            name: "switcher",
            note: "ProviderSwitcherView with five providers, Claude selected, weekly strips on.")
        { appearance in
            try GalleryCapture.appKit(self.switcher(), appearance: appearance, backdrop: appearance.menuBackdrop)
        }

        try gallery.add(
            section: "menu",
            title: "Menu composite",
            name: "composite",
            note: "Switcher above the Claude card, stacked the way the menu stacks its custom rows.")
        { appearance in
            let stack = NSStackView(views: [self.switcher()])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 4
            if let fixture = GalleryFixtures.providers.first, let model = GalleryFixtures.menuCardModel(fixture) {
                stack.addArrangedSubview(self.cardRow(model: model))
            }
            stack.frame = CGRect(origin: .zero, size: stack.fittingSize)
            return try GalleryCapture.appKit(stack, appearance: appearance, backdrop: appearance.menuBackdrop)
        }
    }

    /// The production row container, so padding, submenu indicator, and height match the menu.
    static func cardRow(model: UsageMenuCardView.Model) -> NSView {
        let payload = MenuCardRowPayload(
            content: AnyView(UsageMenuCardView(model: model, width: self.menuWidth)),
            showsSubmenuIndicator: true,
            submenuIndicatorAlignment: .topTrailing,
            submenuIndicatorTopPadding: 8,
            allowsMenuHighlight: true,
            containsInteractiveControls: false,
            usesGPUSelection: false,
            onClick: nil)
        let row = MenuRowContainerView(payload: payload, refreshMonitor: nil)
        let height = ceil(row.measuredHeight(width: self.menuWidth) + 7)
        row.applyMeasuredSize(width: self.menuWidth, height: height)
        return row
    }

    static func switcher() -> ProviderSwitcherView {
        let switcher = ProviderSwitcherView(
            providers: [.codex, .claude, .cursor, .gemini, .copilot],
            selected: .provider(UsageProvider.claude.instanceID),
            includesOverview: false,
            width: self.menuWidth,
            showsIcons: true,
            iconProvider: { ProviderBrandIcon.image(for: $0) ?? NSImage(size: NSSize(width: 16, height: 16)) },
            weeklyRemainingProvider: { instanceID in
                instanceID.firstPartyProvider.flatMap(GalleryFixtures.weeklyRemaining)
            },
            onSelect: { _ in })
        switcher.frame.size = NSSize(width: self.menuWidth, height: switcher.frame.height)
        return switcher
    }
}
