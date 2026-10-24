import AppKit
import OpenBarCore
import SwiftUI

enum SettingsWindowIdentity {
    static let identifier = "com.serbinenko.openbar.settings"
    static let frameAutosaveName = "OpenBar.SettingsWindow"
}

@MainActor
final class SettingsWindowController: NSWindowController {
    enum Outcome: Equatable {
        case created
        case reused
        case failed
    }

    typealias WindowFactory = @MainActor () -> NSWindow?
    typealias WindowAction = @MainActor (NSWindow) -> Void

    private let selection: PreferencesSelection
    private let makeWindow: WindowFactory
    private let prepareToPresent: @MainActor () -> Void
    private let registerWindow: WindowAction
    private let presentWindow: WindowAction
    private let didPresentWindow: WindowAction
    private let presentationFailed: @MainActor () -> Void
    private let logger = OpenBarLog.logger(LogCategories.app)
    private var retainedWindow: NSWindow?
    private var didCloseWindow: (@MainActor () -> Void)?
    private var makeRootView: (@MainActor () -> AnyView)?
    private var rootViewReleased = false

    init(
        selection: PreferencesSelection,
        makeWindow: @escaping WindowFactory,
        prepareToPresent: @escaping @MainActor () -> Void = {
            DockIconController.shared.prepareToOpenSettings()
        },
        registerWindow: @escaping WindowAction = { window in
            DockIconController.shared.registerSettingsWindow(window)
        },
        presentWindow: @escaping WindowAction = { window in
            SettingsWindowStageBehavior.present(window)
        },
        didPresentWindow: @escaping WindowAction = { window in
            DockIconController.shared.settingsWindowDidPresent(window)
        },
        presentationFailed: @escaping @MainActor () -> Void = {
            DockIconController.shared.settingsWindowPresentationFailed()
        })
    {
        self.selection = selection
        self.makeWindow = makeWindow
        self.prepareToPresent = prepareToPresent
        self.registerWindow = registerWindow
        self.presentWindow = presentWindow
        self.didPresentWindow = didPresentWindow
        self.presentationFailed = presentationFailed
        super.init(window: nil)
    }

    convenience init(
        settings: SettingsStore,
        store: UsageStore,
        cloudSyncState: CloudSyncState,
        updater: UpdaterProviding,
        selection: PreferencesSelection,
        managedCodexAccountCoordinator: ManagedCodexAccountCoordinator,
        codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator,
        runProviderLoginFlow: @escaping @MainActor (UsageProvider) async -> Void)
    {
        let makeRootView: @MainActor () -> AnyView = {
            AnyView(PreferencesView(
                settings: settings,
                store: store,
                cloudSyncState: cloudSyncState,
                updater: updater,
                selection: selection,
                managedCodexAccountCoordinator: managedCodexAccountCoordinator,
                codexAccountPromotionCoordinator: codexAccountPromotionCoordinator,
                runProviderLoginFlow: runProviderLoginFlow))
        }
        self.init(selection: selection) {
            // Type-erased so close can swap the preferences tree out of the one long-lived window.
            let hostingController = NSHostingController(rootView: makeRootView())
            let window = NSWindow(
                contentRect: NSRect(
                    x: 0,
                    y: 0,
                    width: SettingsPane.windowWidth,
                    height: SettingsPane.windowHeight),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false)
            window.contentViewController = hostingController
            window.title = selection.title
            SettingsWindowToolbar.configure(window)
            window.isReleasedWhenClosed = false
            SettingsWindowSizing.enforceMinimumSize(window)
            if !window.setFrameUsingName(SettingsWindowIdentity.frameAutosaveName) {
                window.center()
            }
            window.setFrameAutosaveName(SettingsWindowIdentity.frameAutosaveName)
            return window
        }
        self.makeRootView = makeRootView
        self.didCloseWindow = { [weak store] in
            store?.sharedSpendDashboardControllerStorage?.setDetailsVisible(false)
            // Hand the closed window's freed allocator pages back to macOS.
            store?.scheduleMemoryPressureRelief()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @discardableResult
    func open(pane: SettingsPane?) -> Outcome {
        if let pane {
            self.selection.pane = pane
        }
        if pane == .about {
            self.selection.requestAboutRoot()
        }

        self.prepareToPresent()
        let outcome: Outcome
        let window: NSWindow
        if let retainedWindow {
            if self.rootViewReleased, let makeRootView,
               let hosting = retainedWindow.contentViewController as? NSHostingController<AnyView>
            {
                hosting.rootView = makeRootView()
                self.rootViewReleased = false
            }
            window = retainedWindow
            outcome = .reused
        } else if let createdWindow = self.makeWindow() {
            createdWindow.identifier = NSUserInterfaceItemIdentifier(SettingsWindowIdentity.identifier)
            SettingsWindowStageBehavior.applyCollectionBehavior(createdWindow)
            self.retainedWindow = createdWindow
            self.window = createdWindow
            createdWindow.delegate = self
            window = createdWindow
            outcome = .created
        } else {
            self.presentationFailed()
            self.logger.error("Failed to create Settings window")
            return .failed
        }

        self.registerWindow(window)
        self.presentWindow(window)
        self.didPresentWindow(window)
        self.logger.info(
            "Settings window presented",
            metadata: [
                "outcome": outcome == .created ? "created" : "reused",
                "pane": self.selection.pane.persistenceToken,
            ])
        return outcome
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === self.retainedWindow else { return }
        // SwiftUI keeps a closed window's NavigationSplitView graph alive through internal cycles, so
        // recreating the window would leak a graph per open. Keep one window and swap its root out
        // instead, after AppKit finishes closing; reopening restores the root.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, !window.isVisible,
                  let hosting = window.contentViewController as? NSHostingController<AnyView>
            else { return }
            hosting.rootView = AnyView(Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity))
            self.rootViewReleased = true
            self.didCloseWindow?()
        }
    }
}
