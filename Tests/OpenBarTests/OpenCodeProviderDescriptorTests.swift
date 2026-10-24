import Testing
@testable import OpenBarCore

struct OpenCodeProviderDescriptorTests {
    @Test
    func `dashboard links use the official auth entry point`() {
        #expect(OpenCodeProviderDescriptor.descriptor.metadata.dashboardURL == "https://opencode.ai/auth")
        #expect(OpenCodeGoProviderDescriptor.descriptor.metadata.dashboardURL == "https://opencode.ai/auth")
    }
}
