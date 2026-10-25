import AppKit
import OpenBarCore
import SwiftUI
@testable import OpenBar

/// Menu surfaces: provider cards, the provider switcher, Overview and compact account rows, and
/// composites of the open menu. Owner during the redesign: the Menu agent (docs/design/README.md).
///
/// Every row goes through the production `MenuRowContainerView`, so padding, highlight, submenu
/// chevrons, and measured heights match the menu. Native `NSMenuItem` rows and separators cannot be
/// captured offscreen; composites draw a hairline stand-in where the menu has a separator item.
@MainActor
enum GalleryMenuSection {
    static let menuWidth: CGFloat = 310

    static func render(_ gallery: GalleryWriter) throws {
        try self.renderCards(gallery)
        try self.renderSwitcher(gallery)
        try self.renderComposites(gallery)
        try self.renderOverview(gallery)
        try self.renderCompactAccounts(gallery)
    }

    // MARK: Cards

    private static func renderCards(_ gallery: GalleryWriter) throws {
        for fixture in GalleryFixtures.providers {
            guard let model = GalleryFixtures.menuCardModel(fixture) else { continue }
            let name = ProviderDefaults.metadata[fixture.provider]?.displayName ?? fixture.provider.rawValue
            try gallery.add(
                section: "menu",
                title: "Card · \(name)",
                name: "card-\(fixture.provider.rawValue)",
                note: "UsageMenuCardView (one hosting view: provider card + cost card), \(Int(self.menuWidth)) pt "
                    + "wide, on an opaque stand-in for menu glass.")
            { appearance in
                try GalleryCapture.appKit(
                    self.cardRow(model: model),
                    appearance: appearance,
                    backdrop: appearance.menuBackdrop)
            }
        }

        if let model = GalleryFixtures.emptyModel(.copilot) {
            try gallery.add(
                section: "menu",
                title: "Card · empty",
                name: "card-empty",
                note: "A provider that has not fetched yet: header and one secondary line.")
            { appearance in
                try GalleryCapture.appKit(
                    self.cardRow(model: model),
                    appearance: appearance,
                    backdrop: appearance.menuBackdrop)
            }
        }

        for language in ["de", "ru"] {
            try gallery.add(
                section: "menu",
                title: "Card · long name, \(language)",
                name: "card-long-\(language)",
                note: "Long provider name, plan, and account under the \(language) localization; reset and pace "
                    + "text reflow onto two lines instead of truncating.")
            { appearance in
                try OpenBarLocalizationOverride.$appLanguage.withValue(language) {
                    guard let model = GalleryFixtures.menuCardModel(GalleryFixtures.longName) else {
                        throw GalleryError.bitmap
                    }
                    return try GalleryCapture.appKit(
                        self.cardRow(model: model),
                        appearance: appearance,
                        backdrop: appearance.menuBackdrop)
                }
            }
        }

        if let model = GalleryFixtures.providers.dropFirst().first.flatMap(GalleryFixtures.menuCardModel) {
            try gallery.add(
                section: "menu",
                title: "Card · Increase Contrast (fixture)",
                name: "card-increased-contrast",
                note: "Codex card drawn with the high-contrast appearance and the card hairline forced on. A fixture "
                    + "render of the token values, not proof of the system toggle.")
            { appearance in
                let row = self.row(
                    UsageMenuCardView(model: model, width: self.menuWidth)
                        .environment(\.menuCardIncreasedContrastOverride, true),
                    containsInteractiveControls: true)
                row.appearance = NSAppearance(
                    named: appearance.isDark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua)
                return try GalleryCapture.appKit(row, appearance: appearance, backdrop: appearance.menuBackdrop)
            }
        }

        if let model = GalleryFixtures.providers.first.flatMap(GalleryFixtures.menuCardModel) {
            try gallery.add(
                section: "menu",
                title: "Card · highlighted",
                name: "card-highlighted",
                note: "Sectioned provider card that owns a submenu, highlighted: the whole card fills with the "
                    + "accent; text, meter, and pace tick turn white.")
            { appearance in
                let row = self.row(
                    UsageMenuCardHeaderAndUsageSectionView(
                        model: model,
                        layoutModel: model,
                        bottomPadding: 0,
                        width: self.menuWidth),
                    showsSubmenu: true,
                    highlighted: true)
                return try GalleryCapture.appKit(row, appearance: appearance, backdrop: appearance.menuBackdrop)
            }
        }
    }

    // MARK: Switcher

    private static func renderSwitcher(_ gallery: GalleryWriter) throws {
        try gallery.add(
            section: "menu",
            title: "Provider switcher",
            name: "switcher",
            note: "ProviderSwitcherView with five providers, Claude selected, weekly strips on, and each provider's "
                + "worst-lane figure: Codex warning, Cursor critical, Gemini last-known.")
        { appearance in
            try GalleryCapture.appKit(self.switcher(), appearance: appearance, backdrop: appearance.menuBackdrop)
        }

        try gallery.add(
            section: "menu",
            title: "Provider switcher · six providers",
            name: "switcher-six",
            note: "Six providers in the 310-pt menu, with figures.")
        { appearance in
            try GalleryCapture.appKit(
                self.switcher(providers: [.codex, .claude, .cursor, .gemini, .copilot, .alibabatokenplan]),
                appearance: appearance,
                backdrop: appearance.menuBackdrop)
        }

        try gallery.add(
            section: "menu",
            title: "Provider switcher · no figures",
            name: "switcher-plain",
            note: "The same switcher before any provider reports usage: no figures, weekly strips only.")
        { appearance in
            try GalleryCapture.appKit(
                self.switcher(showsFigures: false),
                appearance: appearance,
                backdrop: appearance.menuBackdrop)
        }
    }

    // MARK: Composites

    private static func renderComposites(_ gallery: GalleryWriter) throws {
        try gallery.add(
            section: "menu",
            title: "Menu composite",
            name: "composite",
            note: "Switcher, the Claude card (provider + cost cards in one hosting view), and the Refresh row, "
                + "stacked as the menu stacks them. Hairlines stand in for native separator items.")
        { appearance in
            var views: [NSView] = [self.switcher(), self.separator()]
            if let model = GalleryFixtures.providers.first.flatMap(GalleryFixtures.menuCardModel) {
                views.append(self.cardRow(model: model, showsSubmenu: false))
            }
            views.append(self.separator())
            views.append(self.refreshRow(highlighted: false))
            return try self.capture(stack: views, appearance: appearance)
        }

        guard let longModel = GalleryFixtures.menuCardModel(GalleryFixtures.longClaude) else { return }
        try gallery.add(
            section: "menu",
            title: "Long menu (sectioned)",
            name: "long-menu",
            note: "Claude with an error subline, extra usage, and cost as separate hosted rows (the sectioned "
                + "menu), then the highlighted Refresh row. Checks height; the other native rows are not drawn.")
        { appearance in
            let views: [NSView] = [
                self.switcher(),
                self.separator(),
                self.row(
                    UsageMenuCardHeaderAndUsageSectionView(
                        model: longModel,
                        layoutModel: longModel,
                        bottomPadding: 0,
                        width: self.menuWidth),
                    showsSubmenu: true,
                    containsInteractiveControls: true),
                self.separator(),
                self.row(
                    UsageMenuCardExtraUsageSectionView(
                        model: longModel,
                        topPadding: 0,
                        bottomPadding: 0,
                        width: self.menuWidth),
                    showsSubmenu: true),
                self.separator(),
                self.row(
                    CostMenuCardRowView(
                        title: StatusItemController.costMenuTitleForProvider(.claude),
                        detailLines: StatusItemController.costMenuVisibleDetailLines(
                            provider: .claude,
                            tokenUsage: longModel.tokenUsage,
                            hasSubmenu: false),
                        valueLines: StatusItemController.costMenuValueLines(tokenUsage: longModel.tokenUsage),
                        width: self.menuWidth)),
                self.separator(),
                self.refreshRow(highlighted: true),
            ]
            return try self.capture(stack: views, appearance: appearance)
        }
    }

    // MARK: Overview

    private static func renderOverview(_ gallery: GalleryWriter) throws {
        let models = GalleryFixtures.providers.compactMap(GalleryFixtures.menuCardModel)
        for layout in [MergedOverviewLayout.detailed, .compact] {
            try gallery.add(
                section: "menu",
                title: "Overview · \(layout == .compact ? "compact" : "detailed")",
                name: "overview-\(layout.rawValue)",
                note: "Merged Overview rows (one card per provider, GPU selection like the menu); the first row "
                    + "is highlighted. Offscreen capture skips the layer tint filter, so its text is not turned "
                    + "white here as it is in the menu. Tones: Codex warning, Cursor critical, Gemini last-known.")
            { appearance in
                var views: [NSView] = [self.switcher(includesOverview: true), self.separator()]
                for (index, model) in models.enumerated() {
                    if index > 0 { views.append(self.separator()) }
                    views.append(self.row(
                        OverviewMenuCardRowView(
                            model: model,
                            storageText: index == 0 ? "1.4 GB" : nil,
                            width: self.menuWidth,
                            layout: layout),
                        showsSubmenu: true,
                        highlighted: index == 0,
                        usesGPUSelection: true))
                }
                return try self.capture(stack: views, appearance: appearance)
            }
        }
    }

    // MARK: Compact account rows

    private static func renderCompactAccounts(_ gallery: GalleryWriter) throws {
        let accounts = GalleryFixtures.compactAccounts()
        let plan = AccountMenuLayoutPlanner.plan(accounts: accounts)
        let progressColor = UsageMenuCardView.Model.progressColor(for: .claude)
        try gallery.add(
            section: "menu",
            title: "Compact account rows",
            name: "compact-accounts",
            note: "Multi-account layout (AccountMenuLayoutPlanner): the active account's card, then one-line rows "
                + "sorted by headroom with the shared tones (warning ≤ 25 %, critical ≤ 10 %). The second row is "
                + "highlighted.")
        { appearance in
            var views: [NSView] = []
            var compactIndex = 0
            for row in plan.rows {
                switch row {
                case let .card(accountID):
                    guard let account = accounts.first(where: { $0.id == accountID }),
                          let model = self.accountCardModel(account) else { continue }
                    views.append(self.cardRow(model: model, showsSubmenu: false))
                    views.append(self.separator())
                case let .compact(compactRow):
                    let model = MenuCardCompactAccountRowView.Model(
                        row: compactRow,
                        resetTimeDisplayStyle: .countdown,
                        now: GalleryFixtures.now)
                    views.append(self.row(
                        MenuCardCompactAccountRowView(
                            model: model,
                            progressColor: progressColor,
                            width: self.menuWidth),
                        highlighted: compactIndex == 1,
                        chrome: .row,
                        clickable: true))
                    compactIndex += 1
                case let .collapsedHealthy(count):
                    views.append(self.row(
                        MenuCardCollapsedAccountsRowView(count: count, width: self.menuWidth),
                        chrome: .row,
                        clickable: true))
                }
            }
            return try self.capture(stack: views, appearance: appearance)
        }
    }

    private static func accountCardModel(_ account: ProviderAccountUsageSnapshot) -> UsageMenuCardView.Model? {
        guard let metadata = ProviderDefaults.metadata[account.provider] else { return nil }
        return UsageMenuCardView.Model.make(.init(
            provider: account.provider,
            metadata: metadata,
            snapshot: account.snapshot,
            credits: nil,
            creditsError: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: account.displayLabel, plan: "Max"),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            quotaWarningThresholds: [:],
            now: GalleryFixtures.now))
    }

    // MARK: Building blocks

    /// The production row container, so padding, submenu indicator, and height match the menu.
    static func cardRow(model: UsageMenuCardView.Model, showsSubmenu: Bool = false) -> NSView {
        self.row(
            UsageMenuCardView(model: model, width: self.menuWidth),
            showsSubmenu: showsSubmenu,
            containsInteractiveControls: true)
    }

    static func row(
        _ view: some View,
        showsSubmenu: Bool = false,
        highlighted: Bool = false,
        usesGPUSelection: Bool = false,
        chrome: MenuRowChrome = .card,
        containsInteractiveControls: Bool = false,
        clickable: Bool = false) -> NSView
    {
        let payload = MenuCardRowPayload(
            content: AnyView(view),
            showsSubmenuIndicator: showsSubmenu,
            submenuIndicatorAlignment: .topTrailing,
            submenuIndicatorTopPadding: 8,
            allowsMenuHighlight: showsSubmenu || clickable,
            containsInteractiveControls: containsInteractiveControls,
            usesGPUSelection: usesGPUSelection,
            onClick: clickable ? {} : nil,
            chrome: chrome)
        let row = MenuRowContainerView(payload: payload, refreshMonitor: nil)
        // Same padding the menu adds around measured content (StatusItemController.menuCardHeight).
        let height = ceil(row.measuredHeight(width: self.menuWidth) + StatusItemController.menuCardRowExtraHeight)
        row.applyMeasuredSize(width: self.menuWidth, height: height)
        if highlighted {
            row.setHighlighted(true)
        }
        return row
    }

    static func refreshRow(highlighted: Bool) -> NSView {
        let view = PersistentRefreshMenuView(
            title: "Refresh",
            systemImageName: MenuDescriptor.MenuAction.refresh.systemImageName,
            shortcutText: "⌘ R")
        view.applySize(width: self.menuWidth, height: PersistentRefreshRowMetrics.defaults.rowHeight)
        view.setHighlighted(highlighted)
        return view
    }

    /// Stand-in for a native separator item: 11 pt tall with a hairline, inset like the menu's.
    static func separator() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: self.menuWidth, height: 11))
        let line = NSBox(frame: NSRect(x: 14, y: 5, width: self.menuWidth - 28, height: 1))
        line.boxType = .separator
        container.addSubview(line)
        return container
    }

    static func switcher(
        includesOverview: Bool = false,
        providers: [UsageProvider] = [.codex, .claude, .cursor, .gemini, .copilot],
        showsFigures: Bool = true) -> ProviderSwitcherView
    {
        let switcher = ProviderSwitcherView(
            providers: providers,
            selected: includesOverview ? .overview : .provider(UsageProvider.claude.instanceID),
            includesOverview: includesOverview,
            width: self.menuWidth,
            showsIcons: true,
            iconProvider: { ProviderBrandIcon.image(for: $0) ?? NSImage(size: NSSize(width: 16, height: 16)) },
            weeklyRemainingProvider: { instanceID in
                instanceID.firstPartyProvider.flatMap(GalleryFixtures.weeklyRemaining)
            },
            quotaSummaryProvider: { instanceID in
                guard showsFigures else { return nil }
                return instanceID.firstPartyProvider.flatMap(GalleryFixtures.switcherSummary)
            },
            onSelect: { _ in })
        switcher.frame.size = NSSize(width: self.menuWidth, height: switcher.frame.height)
        return switcher
    }

    /// Stacks rows top to bottom with the menu's 8-pt top and 6-pt bottom content inset.
    private static func capture(stack views: [NSView], appearance: GalleryAppearance) throws -> Data {
        let topInset: CGFloat = 8
        let bottomInset: CGFloat = 6
        let height = views.reduce(topInset + bottomInset) { $0 + $1.frame.height }
        let container = NSView(frame: NSRect(x: 0, y: 0, width: self.menuWidth, height: height))
        var y = height - topInset
        for view in views {
            y -= view.frame.height
            view.frame.origin = CGPoint(x: 0, y: y)
            container.addSubview(view)
        }
        return try GalleryCapture.appKit(
            container,
            appearance: appearance,
            size: container.frame.size,
            backdrop: appearance.menuBackdrop)
    }
}
