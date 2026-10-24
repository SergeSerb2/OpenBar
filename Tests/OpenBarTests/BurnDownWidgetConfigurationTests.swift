import Testing
@testable import OpenBarWidget

struct BurnDownWidgetConfigurationTests {
    @Test
    func `burn down widget background is removable by the system`() {
        #expect(BurnDownWidgetBackgroundConfiguration.isRemovable)
    }
}
