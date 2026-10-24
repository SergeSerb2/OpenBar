// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StoreStress",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(name: "OpenBar", path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "StoreStress",
            dependencies: [
                .product(name: "OpenBarCore", package: "OpenBar"),
            ],
            path: ".",
            exclude: ["Package.swift", "README.md"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]),
    ])
