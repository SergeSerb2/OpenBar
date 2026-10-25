// swift-tools-version: 6.2
import Foundation
import PackageDescription

let sweetCookieKitPath = "../SweetCookieKit"
let useLocalSweetCookieKit =
    ProcessInfo.processInfo.environment["OPENBAR_USE_LOCAL_SWEETCOOKIEKIT"] == "1"
let sweetCookieKitDependency: Package.Dependency =
    useLocalSweetCookieKit && FileManager.default.fileExists(atPath: sweetCookieKitPath)
    ? .package(path: sweetCookieKitPath)
    : .package(url: "https://github.com/steipete/SweetCookieKit", from: "0.5.9")

let sqlite3LibDir = ProcessInfo.processInfo.environment["OPENBAR_SQLITE3_LIB_DIR"]?
    .trimmingCharacters(in: .whitespacesAndNewlines)
let sqlite3LinkerSettings: [LinkerSetting] = if let sqlite3LibDir, !sqlite3LibDir.isEmpty {
    [.unsafeFlags(["-L\(sqlite3LibDir)"], .when(platforms: [.linux]))]
} else {
    []
}

let package = Package(
    name: "OpenBar",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: {
        var products: [Product] = [
            .library(name: "OpenBarCore", targets: ["OpenBarCore"]),
            .executable(name: "OpenBarCLI", targets: ["OpenBarCLI"]),
            // Offline adaptive-refresh replay harness. Keep the supporting library package-internal.
            .executable(name: "AdaptiveReplayCLI", targets: ["AdaptiveReplayCLI"]),
        ]

        #if os(macOS)
        products.append(contentsOf: [
            .executable(name: "OpenBar", targets: ["OpenBar"]),
            .executable(name: "OpenBarClaudeWatchdog", targets: ["OpenBarClaudeWatchdog"]),
            .executable(name: "OpenBarWidget", targets: ["OpenBarWidget"]),
            .executable(name: "OpenBarClaudeWebProbe", targets: ["OpenBarClaudeWebProbe"]),
        ])
        #endif

        return products
    }(),
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6"),
        .package(url: "https://github.com/steipete/Commander", from: "0.2.4"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.5.2"),
        .package(url: "https://github.com/apple/swift-log", from: "1.15.1"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
        sweetCookieKitDependency,
    ],
    targets: {
        var targets: [Target] = [
            .target(
                name: "CQuickJS",
                path: "Sources/CQuickJS",
                exclude: ["README.md", "LICENSE"],
                publicHeadersPath: "include",
                cSettings: [
                    .define("_GNU_SOURCE"),
                ],
                linkerSettings: [
                    .linkedLibrary("m", .when(platforms: [.linux])),
                ]),
            // Both glibc and static-musl CLI builds use this target; the module map supplies sqlite3 linkage.
            .systemLibrary(
                name: "CSQLite3",
                providers: [
                    .apt(["libsqlite3-dev"]),
                    .brew(["sqlite3"]),
                ]),
            .target(
                name: "OpenBarCore",
                dependencies: [
                    "CQuickJS",
                    .target(name: "CSQLite3", condition: .when(platforms: [.linux])),
                    .product(name: "Crypto", package: "swift-crypto"),
                    .product(name: "Logging", package: "swift-log"),
                    .product(name: "SweetCookieKit", package: "SweetCookieKit"),
                ],
                resources: [
                    .process("Resources"),
                ],
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ],
                linkerSettings: sqlite3LinkerSettings + [
                    .linkedFramework("JavaScriptCore", .when(platforms: [.macOS])),
                ]),
            .executableTarget(
                name: "OpenBarCLI",
                dependencies: [
                    "OpenBarCore",
                    .product(name: "Commander", package: "Commander"),
                    .product(name: "Crypto", package: "swift-crypto"),
                ],
                path: "Sources/OpenBarCLI",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ],
                linkerSettings: sqlite3LinkerSettings + [
                    // musl's default thread stack is too small for synchronous Swift cost scans.
                    .unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=8388608"], .when(platforms: [.linux])),
                ]),
            // Crash-test subprocess: tests SIGKILL it mid-save to prove the cost store's
            // save cycle is atomic. Not shipped; built only as a test dependency.
            .executableTarget(
                name: "OpenBarCostStoreCrashProbe",
                dependencies: ["OpenBarCore"],
                path: "Sources/OpenBarCostStoreCrashProbe",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ],
                linkerSettings: sqlite3LinkerSettings),
            // Sole owner of the adaptive refresh decision table. Package-internal so the app and
            // offline replay tool share behavior without publishing another library product.
            .target(
                name: "AdaptiveRefreshCore",
                dependencies: [],
                path: "Sources/AdaptiveRefreshCore",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ]),
            // Offline adaptive-refresh replay harness: pure Foundation,
            // no OpenBar/OpenBarCore dependency, so it builds anywhere OpenBarCore does.
            .target(
                name: "AdaptiveReplayKit",
                dependencies: ["AdaptiveRefreshCore"],
                path: "Sources/AdaptiveReplayKit",
                exclude: ["README.md"],
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ]),
            .executableTarget(
                name: "AdaptiveReplayCLI",
                dependencies: ["AdaptiveReplayKit"],
                path: "Sources/AdaptiveReplayCLI",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ]),
            .testTarget(
                name: "AdaptiveReplayCLITests",
                dependencies: ["AdaptiveReplayCLI", "AdaptiveReplayKit"],
                path: "Tests/AdaptiveReplayCLITests",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                    .enableExperimentalFeature("SwiftTesting"),
                ]),
            .testTarget(
                name: "AdaptiveReplayKitTests",
                dependencies: ["AdaptiveRefreshCore", "AdaptiveReplayKit"],
                path: "Tests/AdaptiveReplayKitTests",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                    .enableExperimentalFeature("SwiftTesting"),
                ]),
            .testTarget(
                name: "OpenBarPluginTests",
                dependencies: ["OpenBarCore"],
                path: "TestsPlugin",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                    .enableExperimentalFeature("SwiftTesting"),
                ]),
            .testTarget(
                name: "OpenBarLinuxTests",
                dependencies: [
                    "OpenBarCore",
                    "OpenBarCLI",
                    .target(name: "CSQLite3", condition: .when(platforms: [.linux])),
                ],
                path: "TestsLinux",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                    .enableExperimentalFeature("SwiftTesting"),
                ]),
        ]

        #if os(macOS)
        targets.append(contentsOf: [
            .executableTarget(
                name: "OpenBarClaudeWatchdog",
                dependencies: [],
                path: "Sources/OpenBarClaudeWatchdog",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ]),
            .executableTarget(
                name: "OpenBar",
                dependencies: [
                    .product(name: "Sparkle", package: "Sparkle"),
                    .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                    "AdaptiveRefreshCore",
                    "OpenBarCore",
                ],
                path: "Sources/OpenBar",
                resources: [
                    .process("Resources"),
                ],
                swiftSettings: [
                    // Opt into Swift 6 strict concurrency (approachable migration path).
                    .enableUpcomingFeature("StrictConcurrency"),
                    .define("ENABLE_SPARKLE"),
                    // Keep the app shell small; scanner and provider work in OpenBarCore stays at -O.
                    .unsafeFlags(["-Osize"], .when(configuration: .release)),
                ]),
            .executableTarget(
                name: "OpenBarWidget",
                dependencies: ["OpenBarCore"],
                path: "Sources/OpenBarWidget",
                resources: [
                    .process("Resources"),
                ],
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ]),
            .executableTarget(
                name: "OpenBarClaudeWebProbe",
                dependencies: ["OpenBarCore"],
                path: "Sources/OpenBarClaudeWebProbe",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ]),
        ])

        targets.append(.testTarget(
            name: "OpenBarTests",
            dependencies: [
                "OpenBar", "OpenBarCore", "OpenBarCLI", "OpenBarCostStoreCrashProbe", "OpenBarWidget",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Tests",
            exclude: [
                "AdaptiveReplayCLITests",
                "AdaptiveReplayKitTests",
                "OpenBarTests/ProviderPluginDetailsParityTests.swift",
                "OpenBarTests/ProviderPluginExtensionParityTests.swift",
                "OpenBarTests/ProviderPluginParityTests.swift",
                "OpenBarTests/ProviderPluginRuntimeTests.swift",
                "OpenBarTests/Sub2APIPluginGoldenTests.swift",
            ],
            resources: [
                .copy("OpenBarTests/Fixtures"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("SwiftTesting"),
            ],
            linkerSettings: [
                // XCTest's executable is three directories below its sibling framework products.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../.."]),
            ]))
        #endif

        return targets
    }())
