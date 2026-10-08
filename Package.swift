// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SpotifyAppleMerge",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // MergeCore library - core business logic
        .library(
            name: "MergeCore",
            targets: ["MergeCore"]
        ),
        // CLI executable
        .executable(
            name: "merge-cli",
            targets: ["MergeCLI"]
        ),
        // macOS SwiftUI app
        .executable(
            name: "MergeApp",
            targets: ["MergeApp"]
        )
    ],
    dependencies: [
        // Database - SQLite with GRDB
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),

        // CLI argument parsing
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        // MergeCore - Core business logic library
        .target(
            name: "MergeCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),

        // MergeCLI - Command-line interface
        .executableTarget(
            name: "MergeCLI",
            dependencies: [
                "MergeCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),

        // MergeApp - macOS SwiftUI application
        .executableTarget(
            name: "MergeApp",
            dependencies: [
                "MergeCore"
            ]
        ),

        // Tests
        .testTarget(
            name: "MergeCoreTests",
            dependencies: ["MergeCore"]
        )
    ]
)
