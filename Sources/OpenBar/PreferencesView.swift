import AppKit
import OpenBarCore
import SwiftUI

/// Sidebar destinations of the settings window: fixed app panes plus one entry per provider.
enum SettingsPane: Hashable {
    case general
    case iCloudSync
    case usageSpend
    case notifications
    case menuBar
    case menu
    case advanced
    case hooks
    case plugins
    case about
    case debug
    case provider(ProviderInstanceID)

    static let windowWidth: CGFloat = 880
    static let windowHeight: CGFloat = 620
    static let windowMinWidth: CGFloat = 800
    static let windowMinHeight: CGFloat = 540
    static let sidebarWidth: CGFloat = 260
    static let sidebarMinWidth: CGFloat = 200
    static let sidebarMaxWidth: CGFloat = 380
    static let sidebarWidthDefaultsKey = "settingsSidebarWidth"
    static let detailMaxWidth: CGFloat = 780

    var title: String {
        switch self {
        case .general: L("tab_general")
        case .iCloudSync: L("iCloud Sync")
        case .usageSpend: L("tab_usage_spend")
        case .notifications: L("tab_notifications")
        case .menuBar: L("tab_menu_bar")
        case .menu: L("tab_menu")
        case .advanced: L("tab_advanced")
        case .hooks: L("tab_hooks")
        case .plugins: L("Plugins")
        case .about: L("tab_about")
        case .debug: L("tab_debug")
        case let .provider(instanceID):
            instanceID.firstPartyProvider
                .map { ProviderDescriptorRegistry.descriptor(for: $0).metadata.displayName }
                ?? instanceID.rawValue
        }
    }
}

@MainActor
struct PreferencesView: View {
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore
    @Bindable var cloudSyncState: CloudSyncState
    let updater: UpdaterProviding
    @Bindable var selection: PreferencesSelection
    let managedCodexAccountCoordinator: ManagedCodexAccountCoordinator
    let codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator
    let runProviderLoginFlow: @MainActor (UsageProvider) async -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(SettingsPane.sidebarWidthDefaultsKey) private var sidebarWidth: Double = SettingsPane.sidebarWidth

    /// The persisted width, guarded against out-of-range values (edited defaults,
    /// bounds that shrank in an update) so a bad stored value can't wreck the layout.
    private var clampedSidebarWidth: CGFloat {
        min(max(self.sidebarWidth, SettingsPane.sidebarMinWidth), SettingsPane.sidebarMaxWidth)
    }

    init(
        settings: SettingsStore,
        store: UsageStore,
        cloudSyncState: CloudSyncState = CloudSyncState(),
        updater: UpdaterProviding,
        selection: PreferencesSelection,
        managedCodexAccountCoordinator: ManagedCodexAccountCoordinator = ManagedCodexAccountCoordinator(),
        codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator? = nil,
        runProviderLoginFlow: @escaping @MainActor (UsageProvider) async -> Void = { _ in })
    {
        self.settings = settings
        self.store = store
        self.cloudSyncState = cloudSyncState
        self.updater = updater
        self.selection = selection
        self.managedCodexAccountCoordinator = managedCodexAccountCoordinator
        self.codexAccountPromotionCoordinator = codexAccountPromotionCoordinator
            ?? CodexAccountPromotionCoordinator(
                settingsStore: settings,
                usageStore: store,
                managedAccountCoordinator: managedCodexAccountCoordinator)
        self.runProviderLoginFlow = runProviderLoginFlow
    }

    /// One lightweight shell on every macOS version (docs/design/README.md §9.4): an edge-to-edge sidebar, a
    /// hairline, and the detail column. It replaces `NavigationSplitView` (about 11 MB heavier at first open in the
    /// synthetic shell bench; release-app trials are the acceptance measurement). The whole shell runs up behind
    /// the transparent titlebar; the sidebar starts its content below the traffic lights and the detail column
    /// draws its own back/forward strip in that band.
    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebarView(
                settings: self.settings,
                store: self.store,
                selection: self.$selection.pane,
                onSelectAbout: { self.selection.requestAboutRoot() },
                search: self.$selection.sidebarSearchText)
                .frame(width: self.clampedSidebarWidth)
                .frame(maxHeight: .infinity)
                .background {
                    // The only material in the window. With Reduce Transparency the sidebar is an opaque fill
                    // instead, so no effect view exists at all.
                    if self.reduceTransparency {
                        SettingsOpaqueSidebarBackground()
                    } else {
                        SettingsSidebarMaterial()
                    }
                }

            Divider()

            // The sidebar width is user-resizable via the input-only drag strip on the detail's leading edge.
            self.detailColumn
                .overlay(alignment: .leading) {
                    self.sidebarResizeHandle
                }
        }
        .ignoresSafeArea(edges: .top)
        .tint(OpenBarTheme.Colors.accent)
        .frame(
            minWidth: SettingsPane.windowMinWidth,
            idealWidth: SettingsPane.windowWidth,
            maxWidth: .infinity,
            minHeight: SettingsPane.windowMinHeight,
            idealHeight: SettingsPane.windowHeight,
            maxHeight: .infinity)
        .id(self.settings.appLanguage)
        .openBarLocalized()
        .background {
            SettingsWindowAppearanceBridge(colorScheme: self.colorScheme, windowTitle: self.selection.title)
                .allowsHitTesting(false)
        }
        .onAppear {
            self.ensureValidSelection()
        }
        .onChange(of: self.settings.debugMenuEnabled) { _, _ in
            self.ensureValidSelection()
        }
        .onChange(of: self.settings.shouldRequestAdaptiveActivityScanConsent) { _, shouldRequest in
            guard shouldRequest else { return }
            AdaptiveActivityConsentPresenter.presentIfNeeded(settings: self.settings)
        }
    }

    /// The detail column: the back/forward strip in the titlebar band, then the selected pane. Forms are capped
    /// at 600 pt of content and centered; Usage & Spend keeps its wider dashboard width. No backing view: the
    /// window's own background shows through, and pane content scrolls inside its own frame below the strip.
    private var detailColumn: some View {
        VStack(spacing: 0) {
            // Above the pane: in the real window a pane's scroll view extends up into the titlebar band (its safe
            // area), and as a later sibling it would otherwise cover the strip and take its clicks. The opaque
            // window-background fill hides content that scrolls beneath; it is a plain fill, not a material.
            SettingsDetailHeader(selection: self.selection, showsTitle: self.showsHeaderTitle)
                .background(Color(nsColor: .windowBackgroundColor))
                .zIndex(1)

            // Zero minimum widths: a pane whose content asks for more width (long translations, fixed-size
            // controls) stays inside the column instead of pushing the whole shell wider than the window, which
            // NavigationSplitView's AppKit columns used to prevent.
            self.detailView
                .frame(minWidth: 0, maxWidth: self.detailMaxWidth, maxHeight: .infinity, alignment: .top)
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
    }

    /// Usage & Spend draws its own `title` heading, so the strip leaves the title to the window title there.
    private var showsHeaderTitle: Bool {
        self.selection.pane != .usageSpend
    }

    private var detailMaxWidth: CGFloat {
        self.selection.pane == .usageSpend ? SettingsPane.detailMaxWidth : OpenBarSettingsMetrics.formMaxWidth
    }

    @ViewBuilder
    private var sidebarResizeHandle: some View {
        let handle = SidebarResizeHandle(
            width: self.$sidebarWidth,
            minWidth: SettingsPane.sidebarMinWidth,
            maxWidth: SettingsPane.sidebarMaxWidth)
            .frame(width: SidebarResizeHandleView.grabWidth)
            .ignoresSafeArea()
        if #available(macOS 15.0, *) {
            handle.pointerStyle(.columnResize)
        } else {
            handle
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch self.selection.pane {
        case .general:
            GeneralPane(settings: self.settings)
        case .iCloudSync:
            ICloudSyncPane(settings: self.settings, state: self.cloudSyncState)
        case .usageSpend:
            SpendDashboardPane(settings: self.settings, store: self.store)
        case .notifications:
            NotificationsPane(settings: self.settings)
        case .menuBar:
            MenuBarPane(settings: self.settings, store: self.store)
        case .menu:
            MenuPane(settings: self.settings, store: self.store)
        case .advanced:
            AdvancedPane(settings: self.settings, store: self.store)
        case .hooks:
            HooksPane(settings: self.settings)
        case .plugins:
            PluginsPane(settings: self.settings, store: self.store)
        case .about:
            AboutPane(updater: self.updater, selection: self.selection)
        case .debug:
            DebugPane(settings: self.settings, store: self.store)
        case let .provider(instanceID):
            if let provider = instanceID.firstPartyProvider {
                ProvidersPane(
                    provider: provider,
                    settings: self.settings,
                    store: self.store,
                    managedCodexAccountCoordinator: self.managedCodexAccountCoordinator,
                    codexAccountPromotionCoordinator: self.codexAccountPromotionCoordinator,
                    runProviderLoginFlow: self.runProviderLoginFlow)
                    .id(instanceID)
            }
        }
    }

    private func ensureValidSelection() {
        guard !self.settings.debugMenuEnabled else { return }
        if self.selection.pane == .debug {
            self.selection.pane = .general
        }
        self.selection.removeFromHistory { $0 == .debug }
    }
}

@MainActor
enum SettingsWindowSizing {
    static func enforceMinimumSize(_ window: NSWindow) {
        let toolbarHeight = max(0, window.frame.height - window.contentLayoutRect.height)
        let minimumSize = NSSize(
            width: SettingsPane.windowMinWidth,
            height: SettingsPane.windowMinHeight + toolbarHeight)
        window.minSize = minimumSize

        if window.frame.width < minimumSize.width || window.frame.height < minimumSize.height {
            var frame = window.frame
            let repairedSize = NSSize(
                width: max(frame.width, minimumSize.width),
                height: max(frame.height, minimumSize.height))
            frame.origin.y += frame.height - repairedSize.height
            frame.size = repairedSize
            window.setFrame(frame, display: true)
        }
    }
}

@MainActor
enum SettingsWindowStageBehavior {
    /// Keep Settings on the current Stage Manager stage / Space instead of
    /// yanking focus back to wherever the window last appeared.
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .moveToActiveSpace,
        .fullScreenAuxiliary,
    ]

    static func applyCollectionBehavior(_ window: NSWindow) {
        // Assign the exact OptionSet. `.canJoinAllSpaces` is mutually exclusive
        // with `.moveToActiveSpace`, and SwiftUI may restore a stale Space mask.
        if window.collectionBehavior != self.collectionBehavior {
            window.collectionBehavior = self.collectionBehavior
        }
    }

    static func present(_ window: NSWindow) {
        self.applyCollectionBehavior(window)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
enum SettingsWindowAppearance {
    typealias ResetAction = @MainActor @Sendable () -> Void
    typealias ResetScheduler = @MainActor @Sendable (@escaping ResetAction) -> Void

    static func refresh(
        _ window: NSWindow,
        application: NSApplication = NSApp,
        scheduleReset: ResetScheduler = Self.scheduleReset)
    {
        SettingsWindowSizing.enforceMinimumSize(window)
        window.appearanceSource = application
        // Pulse the exact effective appearance so the native toolbar redraws without
        // dropping inherited accessibility attributes, then restore KVO inheritance.
        window.appearance = application.effectiveAppearance
        scheduleReset { [weak window] in
            if let window {
                SettingsWindowSizing.enforceMinimumSize(window)
            }
            window?.appearance = nil
            window?.viewsNeedDisplay = true
        }
    }

    static func scheduleReset(_ action: @escaping ResetAction) {
        Task { @MainActor in
            await Task.yield()
            action()
        }
    }
}

@MainActor
struct SettingsWindowAppearanceBridge: NSViewRepresentable {
    let colorScheme: ColorScheme
    let windowTitle: String

    func makeNSView(context: Context) -> SettingsWindowAppearanceView {
        SettingsWindowAppearanceView()
    }

    func updateNSView(_ nsView: SettingsWindowAppearanceView, context: Context) {
        nsView.refreshWindowAppearance(for: self.colorScheme, windowTitle: self.windowTitle)
    }
}

@MainActor
final class SettingsWindowAppearanceView: NSView {
    private let scheduleReset: SettingsWindowAppearance.ResetScheduler
    private var colorScheme: ColorScheme?
    private var windowTitle: String?

    init(scheduleReset: @escaping SettingsWindowAppearance.ResetScheduler = SettingsWindowAppearance.scheduleReset) {
        self.scheduleReset = scheduleReset
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didUpdateNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.windowDidUpdate(_:)),
                name: NSWindow.didUpdateNotification,
                object: window)
        }
        self.configureWindowStyle()
        self.refreshWindowAppearance()
    }

    @objc private func windowDidUpdate(_ notification: Notification) {
        self.configureWindowStyle()
    }

    func refreshWindowAppearance(for colorScheme: ColorScheme, windowTitle: String? = nil) {
        let colorSchemeChanged = self.colorScheme != colorScheme
        let windowTitleChanged = self.windowTitle != windowTitle
        guard colorSchemeChanged || windowTitleChanged else { return }
        self.colorScheme = colorScheme
        self.windowTitle = windowTitle

        guard let window else { return }
        self.configureWindowStyle()
        if windowTitleChanged, let windowTitle {
            window.title = windowTitle
        }
        if colorSchemeChanged {
            SettingsWindowAppearance.refresh(window, scheduleReset: self.scheduleReset)
        }
    }

    private func refreshWindowAppearance() {
        guard let window else { return }
        self.configureWindowStyle()
        if let windowTitle {
            window.title = windowTitle
        }
        SettingsWindowAppearance.refresh(window, scheduleReset: self.scheduleReset)
    }

    override func layout() {
        super.layout()
        self.configureWindowStyle()
    }

    private func configureWindowStyle() {
        guard let window else { return }
        if !window.styleMask.contains(.resizable) {
            window.styleMask.insert(.resizable)
        }
        if !window.styleMask.contains(.miniaturizable) {
            window.styleMask.insert(.miniaturizable)
        }
        SettingsWindowToolbar.configure(window)
        // Full-size content lets the sidebar material extend behind the titlebar so the
        // edge-to-edge sidebar reaches the top of the window; content stays below the
        // titlebar via the safe area.
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
    }
}

@MainActor
enum SettingsWindowToolbar {
    static let identifier = NSToolbar.Identifier("com.serbinenko.openbar.settings.toolbar")

    /// The HStack shell draws its own back/forward strip and title in the titlebar band (docs/design §9.4). The
    /// window keeps an empty unified toolbar only so the titlebar has its standard height and the traffic
    /// lights share the strip's vertical center. Clicks in the band still reach the SwiftUI content, and empty
    /// areas still drag the window. The title stays set for the Window menu, Mission Control, and VoiceOver.
    static func configure(_ window: NSWindow) {
        if !window.titlebarAppearsTransparent {
            window.titlebarAppearsTransparent = true
        }
        if window.titleVisibility != .hidden {
            window.titleVisibility = .hidden
        }
        if window.toolbar?.identifier != self.identifier {
            let toolbar = NSToolbar(identifier: self.identifier)
            toolbar.allowsUserCustomization = false
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
        }
        if window.toolbarStyle != .unified {
            window.toolbarStyle = .unified
        }
        if window.titlebarSeparatorStyle != .none {
            window.titlebarSeparatorStyle = .none
        }
    }
}

/// The detail column's titlebar strip: back/forward, then the pane title.
@MainActor
struct SettingsDetailHeader: View {
    @Bindable var selection: PreferencesSelection
    let showsTitle: Bool

    var body: some View {
        HStack(spacing: OpenBarSpacing.section) {
            SettingsHistoryButtons(selection: self.selection)
            if self.showsTitle {
                Text(self.selection.title)
                    .font(OpenBarTheme.Fonts.cardTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, OpenBarSpacing.group)
        .frame(minHeight: OpenBarSettingsMetrics.titlebarBandHeight)
    }
}

@MainActor
struct SettingsHistoryButtons: View {
    @Bindable var selection: PreferencesSelection

    var body: some View {
        HStack(spacing: 0) {
            SettingsHistoryButton(
                title: L("Back"),
                systemImage: "chevron.backward",
                isEnabled: self.selection.canGoBack,
                shortcut: "[",
                action: { self.selection.goBack() })
            SettingsHistoryButton(
                title: L("Forward"),
                systemImage: "chevron.forward",
                isEnabled: self.selection.canGoForward,
                shortcut: "]",
                action: { self.selection.goForward() })
        }
        .background(SettingsFillBackground(shape: Capsule(style: .continuous)))
        .fixedSize()
    }
}

private struct SettingsHistoryButton: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let shortcut: KeyEquivalent
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(self.isEnabled ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.tertiary)
                .frame(
                    width: OpenBarSettingsMetrics.historyButtonWidth,
                    height: OpenBarSettingsMetrics.historyButtonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!self.isEnabled)
        .keyboardShortcut(self.shortcut, modifiers: .command)
        .help(self.title)
        .accessibilityLabel(self.title)
    }
}

@MainActor
private struct SettingsSidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
