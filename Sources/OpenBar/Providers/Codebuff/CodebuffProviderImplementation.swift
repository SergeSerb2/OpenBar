import OpenBarCore
import Foundation

struct CodebuffProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .codebuff

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings[providerConfig: .codebuff, field: .apiKey]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "codebuff-api-key",
                title: "API key",
                subtitle: "Stored in ~/.openbar/config.json. You can also provide CODEBUFF_API_KEY or let " +
                    "OpenBar read ~/.config/manicode/credentials.json (created by `codebuff login`).",
                kind: .secure,
                placeholder: "cb_...",
                binding: context.providerConfigBinding(.apiKey),
                actions: [
                    ProviderSettingsActionDescriptor.openURL(
                        id: "codebuff-open-dashboard",
                        title: "Open Codebuff Dashboard",
                        url: URL(string: "https://www.codebuff.com/usage")),
                ],
                isVisible: nil),
        ]
    }
}
