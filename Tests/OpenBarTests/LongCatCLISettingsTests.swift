import Foundation
import OpenBarCore
import Testing
@testable import OpenBarCLI

struct LongCatCLISettingsTests {
    @Test
    func `manual config is carried into CLI settings snapshot`() throws {
        let config = OpenBarConfig(providers: [
            ProviderConfig(
                id: .longcat,
                cookieHeader: "passport_token=manual-token",
                cookieSource: .manual),
        ])
        let selection = TokenAccountCLISelection(label: nil, index: nil, allAccounts: false)
        let tokenContext = try TokenAccountCLIContext(selection: selection, config: config, verbose: false)
        let settings = try #require(tokenContext.settingsSnapshot(for: .longcat, account: nil)?.longcat)

        #expect(settings.cookieSource == .manual)
        #expect(settings.manualCookieHeader == "passport_token=manual-token")
    }

    @Test
    func `off config is carried into CLI settings snapshot`() throws {
        let config = OpenBarConfig(providers: [
            ProviderConfig(
                id: .longcat,
                cookieHeader: "passport_token=ignored-token",
                cookieSource: .off),
        ])
        let selection = TokenAccountCLISelection(label: nil, index: nil, allAccounts: false)
        let tokenContext = try TokenAccountCLIContext(selection: selection, config: config, verbose: false)
        let settings = try #require(tokenContext.settingsSnapshot(for: .longcat, account: nil)?.longcat)

        #expect(settings.cookieSource == .off)
        #expect(settings.manualCookieHeader == "passport_token=ignored-token")
    }
}
