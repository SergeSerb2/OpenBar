import AppKit
import OpenBarCore
import WebKit

@MainActor
final class OpenAICreditsPurchaseWindowController: NSWindowController, WKNavigationDelegate, WKScriptMessageHandler {
    private static let defaultSize = NSSize(width: 980, height: 760)
    private static let logHandlerName = "openbarLog"
    /// The auto-start script and its log handler live in their own world, so page and iframe scripts cannot post logs.
    private static let scriptWorld = WKContentWorld.world(name: "OpenBarBuyCredits")
    private static let maxLogMessageLength = 1000
    private static let maxDebugLogBytes = 64 * 1024
    private static let debugLogURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("openbar-buy-credits.log")
    /// Opens the "Add more" credits dialog and stops there. It never clicks inside a dialog or form, and never
    /// clicks a next, confirm, or submit control: choosing an amount and paying stay with the user.
    private static let autoStartScript = """
    (() => {
      if (window.__openbarAutoBuyCreditsStarted) return 'already';
      window.__openbarAutoBuyCreditsStarted = true;
      const log = (...args) => {
        try {
          window.webkit?.messageHandlers?.openbarLog?.postMessage(args);
        } catch {}
      };
      const isVisible = (el) => {
        const rect = el.getBoundingClientRect();
        if (rect.width < 2 || rect.height < 2) return false;
        const style = window.getComputedStyle(el);
        if (style.display === 'none' || style.visibility === 'hidden') return false;
        return parseFloat(style.opacity || '1') !== 0;
      };
      const isDisabled = (el) => {
        if (el.disabled) return true;
        return String(el.getAttribute('aria-disabled') || '').toLowerCase() === 'true';
      };
      const labelOf = (el) => {
        const text = String(el.innerText || el.textContent || '').trim() || el.getAttribute('aria-label') || '';
        return String(text).replace(/\\s+/g, ' ').trim().toLowerCase();
      };
      const isSafeTarget = (el) => {
        if (el.closest('[role="dialog"], [role="alertdialog"], dialog, [aria-modal="true"], form')) return false;
        if (el.form) return false;
        if (String(el.type || '').toLowerCase() === 'submit') return false;
        return isVisible(el) && !isDisabled(el);
      };
      const findAddMoreButtons = () => Array.from(document.querySelectorAll('button, [role="button"]'))
        .filter(el => labelOf(el) === 'add more')
        .filter(isSafeTarget);
      // Click only when exactly one candidate exists; several matches mean the page shape is unknown.
      const tryClick = () => {
        const buttons = findAddMoreButtons();
        if (buttons.length > 1) {
          log('add_more_ambiguous', { count: buttons.length });
          return 'ambiguous';
        }
        if (buttons.length === 0) return 'missing';
        log('add_more_click', { tag: buttons[0].tagName });
        buttons[0].click();
        return 'clicked';
      };
      log('auto_start', { ready: document.readyState });
      const first = tryClick();
      if (first !== 'missing') return first;
      let attempts = 0;
      const timer = setInterval(() => {
        attempts += 1;
        if (tryClick() !== 'missing') {
          clearInterval(timer);
        } else if (attempts >= 14) {
          log('add_more_missing', { attempts });
          clearInterval(timer);
        }
      }, 500);
      return 'scheduled';
    })();
    """

    private let logger = OpenBarLog.logger(LogCategories.creditsPurchase)
    private var webView: WKWebView?
    private var accountEmail: String?
    private var cacheScope: CookieHeaderCache.Scope?
    private var pendingAutoStart = false
    private let logHandler = WeakScriptMessageHandler()

    init() {
        super.init(window: nil)
        self.logHandler.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(
        purchaseURL: URL,
        accountEmail: String?,
        cacheScope: CookieHeaderCache.Scope?,
        autoStartPurchase: Bool)
    {
        guard Self.canOpenPurchaseWindow(accountEmail: accountEmail, cacheScope: cacheScope) else {
            self.close()
            self.accountEmail = nil
            self.cacheScope = nil
            self.logger.error("Buy credits blocked: scoped account email unavailable")
            return
        }
        let normalizedEmail = Self.normalizeEmail(accountEmail)
        if self.window == nil || normalizedEmail != self.accountEmail || cacheScope != self.cacheScope {
            self.accountEmail = normalizedEmail
            self.cacheScope = cacheScope
            self.buildWindow()
        }
        Self.resetDebugLog()
        let accountValue = normalizedEmail == nil ? "none" : "set"
        let sanitizedURL = Self.sanitizedURLString(purchaseURL)
        Self.appendDebugLog(
            "show autoStart=\(autoStartPurchase) url=\(sanitizedURL) account=\(accountValue)")
        self.logger.info("Buy credits window opened")
        self.logger.debug("Auto-start purchase", metadata: ["enabled": autoStartPurchase ? "1" : "0"])
        self.logger.debug("Purchase URL", metadata: ["url": sanitizedURL])
        self.logger.debug("Account email", metadata: ["state": accountValue])
        self.pendingAutoStart = autoStartPurchase
        self.load(url: purchaseURL)
        self.window?.center()
        self.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindow() {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self.logHandler, contentWorld: Self.scriptWorld, name: Self.logHandlerName)
        config.websiteDataStore = OpenAIDashboardWebsiteDataStore.store(
            forAccountEmail: self.accountEmail,
            scope: self.cacheScope)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: .zero)
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let window = NSWindow(
            contentRect: Self.defaultFrame(),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = L("Buy Credits")
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.contentView = container
        window.center()
        window.delegate = self

        self.window = window
        self.webView = webView
    }

    private func load(url: URL) {
        guard let webView else { return }
        let request = URLRequest(url: url)
        webView.load(request)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard self.pendingAutoStart else { return }
        self.pendingAutoStart = false
        let currentURL = webView.url?.absoluteString ?? "unknown"
        Self.appendDebugLog("didFinish url=\(currentURL)")
        self.logger.debug("Buy credits navigation finished", metadata: ["url": currentURL])
        webView.evaluateJavaScript(Self.autoStartScript, in: nil, in: Self.scriptWorld) { [logger] result in
            switch result {
            case let .failure(error):
                Self.appendDebugLog("autoStart error=\(error.localizedDescription)")
                logger.error("Auto-start purchase failed", metadata: ["error": error.localizedDescription])
            case let .success(value):
                Self.appendDebugLog("autoStart result=\(String(describing: value))")
                logger.debug("Auto-start purchase result", metadata: ["result": String(describing: value)])
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.logHandlerName,
              message.world == Self.scriptWorld,
              message.frameInfo.isMainFrame
        else { return }
        let payload = String(String(describing: message.body).prefix(Self.maxLogMessageLength))
        Self.appendDebugLog("js \(payload)")
        self.logger.debug("Auto-buy log", metadata: ["payload": payload])
    }

    private static func normalizeEmail(_ email: String?) -> String? {
        guard let raw = email?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw.lowercased()
    }

    static func canOpenPurchaseWindow(accountEmail: String?, cacheScope: CookieHeaderCache.Scope?) -> Bool {
        cacheScope == nil || self.normalizeEmail(accountEmail) != nil
    }

    private static func defaultFrame() -> NSRect {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 900)
        let width = min(Self.defaultSize.width, visible.width * 0.92)
        let height = min(Self.defaultSize.height, visible.height * 0.88)
        let origin = NSPoint(x: visible.midX - width / 2, y: visible.midY - height / 2)
        return NSRect(origin: origin, size: NSSize(width: width, height: height))
    }

    private static func appendDebugLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(LogRedactor.redact(message))\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: Self.debugLogURL.path) {
            let size = (try? FileManager.default.attributesOfItem(atPath: Self.debugLogURL.path)[.size] as? Int) ?? 0
            guard size + data.count <= Self.maxDebugLogBytes else { return }
            if let handle = try? FileHandle(forWritingTo: Self.debugLogURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: Self.debugLogURL, options: .atomic)
        }
    }

    private static func resetDebugLog() {
        try? FileManager.default.removeItem(at: self.debugLogURL)
    }

    private static func sanitizedURLString(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.query = nil
        components.fragment = nil
        return components.string ?? url.absoluteString
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        self.delegate?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - NSWindowDelegate

extension OpenAICreditsPurchaseWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = self.window else { return }
        let webView = self.webView
        self.pendingAutoStart = false
        self.webView = nil
        self.window = nil
        self.logger.info("Buy credits window closing")
        WebKitTeardown.scheduleCleanup(owner: window, window: window, webView: webView)
    }
}
