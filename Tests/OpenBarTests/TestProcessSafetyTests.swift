import Testing
@testable import OpenBarCore

struct TestProcessSafetyTests {
    @Test
    func `current process is recognized without callers supplying runner signals`() {
        #expect(TestProcessSafety.isRunning)
    }

    @Test(arguments: [["/tmp/Suite.xctest"], ["swift-testing"], ["/tmp/XCTestRunner"]])
    func `recognizes runner executable arguments`(arguments: [String]) {
        #expect(TestProcessSafety.isRunningUnderTests(
            processName: "runner",
            environment: [:],
            arguments: arguments))
    }

    @Test(arguments: [
        ["/usr/local/bin/openbar", "--account", "swift-testing"],
        ["/usr/local/bin/openbar", "--account", "xctest"],
        ["/usr/local/bin/openbar", "--account", "Example.xctest"],
        ["/tmp/swift-testing/openbar", "usage"],
        ["/tmp/Example.xctest/openbar", "usage"],
        ["/tmp/XCTestRunnerTools/openbar", "usage"],
    ])
    func `ordinary argument values and installation paths retain production behavior`(arguments: [String]) {
        #expect(!TestProcessSafety.isRunningUnderTests(
            processName: "openbar",
            environment: [:],
            arguments: arguments))
    }

    @Test(arguments: [
        ("swiftpm-testing-helper", [:]),
        ("OpenBarPackageTests", [:]),
        ("OpenBarPackageTests.xctest", [:]),
        ("OpenBar", ["XCTestConfigurationFilePath": "fixture"]),
        ("OpenBar", ["XCTestBundlePath": "fixture"]),
        ("OpenBar", ["XCTestSessionIdentifier": "fixture"]),
        ("OpenBar", ["TESTING_LIBRARY_VERSION": "fixture"]),
        ("OpenBar", ["SWIFT_TESTING": "fixture"]),
        ("OpenBar", ["SWIFT_TESTING_ENABLED": "fixture"]),
    ] as [(String, [String: String])])
    func `recognizes every supported runner signal`(
        processName: String,
        environment: [String: String])
    {
        #expect(TestProcessSafety.isRunningUnderTests(
            processName: processName,
            environment: environment))
    }

    @Test
    func `recognizes the loaded XCTest fallback without class lookup side effects`() {
        #expect(TestProcessSafety.isRunningUnderTests(
            processName: "OpenBar",
            environment: [:],
            hasLoadedXCTestCase: true))
    }

    @Test
    func `does not classify an ordinary app process as a test runner`() {
        #expect(!TestProcessSafety.isRunningUnderTests(
            processName: "OpenBar",
            environment: [:]))
    }
}
