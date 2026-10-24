import OpenBarCore
import Testing
@testable import OpenBar

struct KeychainPromptCoordinatorTests {
    @Test
    func `detects raw SwiftPM debug executable`() {
        #expect(KeychainPromptCoordinator.isUnbundledOpenBarExecutable(
            "/Users/me/OpenBar/.build/arm64-apple-macosx/debug/OpenBar"))
        #expect(KeychainPromptCoordinator.isUnbundledOpenBarExecutable(
            "/Users/me/OpenBar/.build/debug/OpenBar"))
    }

    @Test
    func `detects raw SwiftPM release executable`() {
        #expect(KeychainPromptCoordinator.isUnbundledOpenBarExecutable(
            "/Users/me/OpenBar/.build/arm64-apple-macosx/release/OpenBar"))
    }

    @Test
    func `detects custom SwiftPM scratch path`() {
        #expect(KeychainPromptCoordinator.isUnbundledOpenBarExecutable(
            "/tmp/openbar-build/arm64-apple-macosx/debug/OpenBar"))
    }

    @Test
    func `keeps packaged app keychain behavior`() {
        #expect(!KeychainPromptCoordinator.isUnbundledOpenBarExecutable(
            "/Applications/OpenBar.app/Contents/MacOS/OpenBar"))
        #expect(!KeychainPromptCoordinator.isUnbundledOpenBarExecutable(
            "/Users/me/OpenBar/.build/package/OpenBar.app/Contents/MacOS/OpenBar"))
    }

    @Test
    func `ignores unrelated executable paths`() {
        #expect(!KeychainPromptCoordinator.isUnbundledOpenBarExecutable(
            "/Users/me/OpenBar/.build/debug/OpenBarCLI"))
        #expect(!KeychainPromptCoordinator.isUnbundledOpenBarExecutable(""))
        #expect(!KeychainPromptCoordinator.isUnbundledOpenBarExecutable("OpenBar"))
    }

    @Test
    func `browser cookie alert explains password handling and opt out`() {
        let model = KeychainPromptCoordinator.browserCookieAlertModel(label: "Chrome Safe Storage")

        #expect(model.title == "Keychain Access Required")
        #expect(model.message.contains("Chrome Safe Storage"))
        #expect(model.message.contains("macOS—not OpenBar—handles any Mac login password entry"))
        #expect(model.message.contains("Settings → Advanced"))
        #expect(model.primaryButtonTitle == "OK")
        #expect(model.learnMoreButtonTitle == "Learn More…")
        #expect(model.documentationURL.hasSuffix("/docs/keychain-prompts.md"))
    }

    @Test
    func `provider alert preserves the requested keychain purpose`() {
        let context = KeychainPromptContext(
            kind: .claudeOAuth,
            service: "Claude Code-credentials",
            account: nil)

        let model = KeychainPromptCoordinator.alertModel(for: context)

        #expect(model.message.contains("Claude Code OAuth token"))
        #expect(model.message.contains("fetch your Claude usage"))
        #expect(model.learnMoreButtonTitle == "Learn More…")
    }

    @Test
    func `cookie explanations retain each provider and credential purpose`() {
        let providers: [(KeychainPromptContext.Kind, String)] = [
            (.cursorCookie, "Cursor"), (.opencodeCookie, "OpenCode"), (.factoryCookie, "Factory"),
            (.minimaxCookie, "MiniMax"), (.augmentCookie, "Augment"), (.ampCookie, "Amp"),
        ]
        for (kind, name) in providers {
            let model = KeychainPromptCoordinator.alertModel(for: .init(
                kind: kind, service: "fixture", account: nil))
            #expect(model.message.contains("your \(name) cookie header so it can fetch usage"))
        }
    }

    @Test
    func `muse alert preserves the requested keychain purpose`() {
        let context = KeychainPromptContext(
            kind: .museToken,
            service: MuseCredentials.keychainService,
            account: MuseCredentials.keychainAccount)

        let model = KeychainPromptCoordinator.alertModel(for: context)

        #expect(model.message.contains("Muse Code login token"))
        #expect(model.message.contains("fetch your Muse Code subscription usage"))
        #expect(model.learnMoreButtonTitle == "Learn More…")
    }
}
