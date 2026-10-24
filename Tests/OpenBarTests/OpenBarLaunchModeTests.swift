import Testing
@testable import OpenBar

struct OpenBarLaunchModeTests {
    @Test
    func `normal launch starts the application`() {
        #expect(OpenBarLaunchMode.resolve(arguments: ["/Applications/OpenBar"]) == .application)
    }

    @Test
    func `hook event launch skips application initialization`() {
        #expect(OpenBarLaunchMode.resolve(
            arguments: ["/Applications/OpenBar", "--hook-event"]) == .hookEvent)
    }

    @Test
    func `hook event is recognized among other arguments`() {
        #expect(OpenBarLaunchMode.resolve(
            arguments: ["/Applications/OpenBar", "--verbose", "--hook-event"]) == .hookEvent)
    }

    @Test
    func `similar argument still starts the application`() {
        #expect(OpenBarLaunchMode.resolve(
            arguments: ["/Applications/OpenBar", "--hook-events"]) == .application)
    }
}
