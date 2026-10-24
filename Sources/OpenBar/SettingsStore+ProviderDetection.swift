import AppKit
import Foundation
import OpenBarCore

enum ProviderDetectionPolicy {
    struct Signals {
        let codexCLIInstalled: Bool
        let claudeCLIInstalled: Bool
        let claudeDesktopInstalled: Bool
        let geminiCLIInstalled: Bool
        let geminiConfigured: Bool
        let antigravityAvailable: Bool
    }

    static func enabledProviders(signals: Signals) -> Set<UsageProvider> {
        // Provider-specific by design: first-run detection probes these four concrete CLI/app credential sources.
        var enabled: Set<UsageProvider> = []
        if signals.codexCLIInstalled {
            enabled.insert(.codex)
        }
        if signals.claudeCLIInstalled || signals.claudeDesktopInstalled {
            enabled.insert(.claude)
        }
        if signals.geminiCLIInstalled, signals.geminiConfigured {
            enabled.insert(.gemini)
        }
        if signals.antigravityAvailable {
            enabled.insert(.antigravity)
        }

        // Keep the historical Codex default when no usable provider source is found.
        if enabled.isEmpty {
            enabled.insert(.codex)
        }
        return enabled
    }
}

extension SettingsStore {
    func runInitialProviderDetectionIfNeeded(force: Bool = false) {
        guard force || !self.providerDetectionCompleted else { return }
        self.providerDetectionGeneration &+= 1
        let generation = self.providerDetectionGeneration
        let enablementRevisions = self.providerEnablementRevisions
        LoginShellPathCache.shared.captureOnce { [weak self] _ in
            Task { @MainActor in
                await self?.applyProviderDetection(
                    force: force,
                    enablementRevisions: enablementRevisions,
                    generation: generation)
            }
        }
    }

    func applyProviderDetection(
        force: Bool = false,
        enablementRevisions: [ProviderInstanceID: UInt64]? = nil,
        generation: UInt64? = nil) async
    {
        guard force || !self.providerDetectionCompleted else { return }
        guard generation == nil || generation == self.providerDetectionGeneration else { return }
        let expectedRevisions = enablementRevisions ?? self.providerEnablementRevisions
        // Provider-specific by design: detection reads each provider's installed app, CLI, or credential artifact.
        let codexCLIInstalled = BinaryLocator.resolveCodexBinary() != nil
        let claudeCLIInstalled = BinaryLocator.resolveClaudeBinary() != nil
        let claudeDesktopInstalled = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.anthropic.claudefordesktop") != nil
        let geminiCLIInstalled = BinaryLocator.resolveGeminiBinary() != nil
        let geminiConfigured = FileManager.default.fileExists(
            atPath: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".gemini/oauth_creds.json").path)
        let antigravityRunning = await AntigravityStatusProbe.isRunning()
        guard !Task.isCancelled, force || !self.providerDetectionCompleted,
              generation == nil || generation == self.providerDetectionGeneration else { return }
        let antigravityLoggedIn = FileManager.default.fileExists(
            atPath: AntigravityOAuthCredentialsStore().fileURL.path)
        let logger = OpenBarLog.logger(LogCategories.providerDetection)

        let enabledProviders = ProviderDetectionPolicy.enabledProviders(signals: .init(
            codexCLIInstalled: codexCLIInstalled,
            claudeCLIInstalled: claudeCLIInstalled,
            claudeDesktopInstalled: claudeDesktopInstalled,
            geminiCLIInstalled: geminiCLIInstalled,
            geminiConfigured: geminiConfigured,
            antigravityAvailable: antigravityRunning || antigravityLoggedIn))

        logger.info(
            "Provider detection results",
            metadata: [
                "codexCLIInstalled": codexCLIInstalled ? "1" : "0",
                "claudeCLIInstalled": claudeCLIInstalled ? "1" : "0",
                "claudeDesktopInstalled": claudeDesktopInstalled ? "1" : "0",
                "geminiCLIInstalled": geminiCLIInstalled ? "1" : "0",
                "geminiConfigured": geminiConfigured ? "1" : "0",
                "antigravityRunning": antigravityRunning ? "1" : "0",
                "antigravityLoggedIn": antigravityLoggedIn ? "1" : "0",
            ])
        logger.info(
            "Provider detection enablement",
            metadata: [
                "codex": enabledProviders.contains(.codex) ? "1" : "0",
                "claude": enabledProviders.contains(.claude) ? "1" : "0",
                "gemini": enabledProviders.contains(.gemini) ? "1" : "0",
                "antigravity": enabledProviders.contains(.antigravity) ? "1" : "0",
            ])

        for provider in [UsageProvider.codex, .claude, .gemini, .antigravity]
            where self.providerEnablementRevision(for: provider) == expectedRevisions[provider.instanceID, default: 0]
        {
            self.updateProviderConfig(provider: provider) { entry in
                entry.enabled = enabledProviders.contains(provider)
            }
        }
        self.providerDetectionCompleted = true
        logger.info("Provider detection completed")
    }
}
