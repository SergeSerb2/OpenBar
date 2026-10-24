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
        self.init(selection: selection) {
            let rootView = PreferencesView(
                settings: settings,
                store: store,
                cloudSyncState: cloudSyncState,
                updater: updater,
                selection: selection,
                managedCodexAccountCoordinator: managedCodexAccountCoordinator,
                codexAccountPromotionCoordinator: codexAccountPromotionCoordinator,
                runProviderLoginFlow: runProviderLoginFlow)
            let hostingController = NSHostingController(rootView: rootView)
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
        self.didCloseWindow = { [weak store] in
            store?.sharedSpendDashboardControllerStorage?.setDetailsVisible(false)
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
        self.retainedWindow = nil
        self.window = nil
        // Tear the hosting tree down after AppKit finishes closing, not inside its close callback.
        DispatchQueue.main.async { [weak self, weak window] in
            window?.contentViewController = nil
            window?.contentView = nil
            self?.didCloseWindow?()
        }
    }
}
