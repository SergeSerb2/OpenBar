import Foundation
import OpenBarCore
import Testing

struct OpenBarConfigHooksTests {
    @Test
    func `hooks survive config round trip`() throws {
        let hooks = HooksConfig(
            enabled: true,
            events: [
                HookRule(
                    id: "quota-low",
                    event: .quotaLow,
                    provider: "codex",
                    threshold: 0.9,
                    executable: "/usr/bin/true",
                    timeoutSeconds: 30),
            ])
        let config = OpenBarConfig(
            providers: [ProviderConfig(id: .codex, enabled: true)],
            hooks: hooks)

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(OpenBarConfig.self, from: data)

        #expect(decoded.hooks == hooks)
    }
}

struct OpenBarConfigShareUsageTests {
    private static let legacyJSON = Data(#"{"version":1,"providers":[{"id":"codex","enabled":true}]}"#.utf8)

    @Test
    func `sharing is opt in and legacy configs omit the flag on round trip`() throws {
        var config = try OpenBarConfig.decode(from: Self.legacyJSON)
        #expect(!config.shareUsageWithCLI)
        #expect(config.providers.first?.enabled == true)
        for enabled in [false, true, false] {
            config.shareUsageWithCLI = enabled
            let data = try config.encodedData()
            #expect(try #require(String(data: data, encoding: .utf8)).contains("shareUsageWithCLI") == enabled)
            #expect(try OpenBarConfig.decode(from: data).shareUsageWithCLI == enabled)
        }
    }
}
