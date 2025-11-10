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
        // Spotify API client
        .package(url: "https://github.com/Peter-Schorn/SpotifyAPI", from: "3.0.0"),

        // Apple Music API wrapper
        .package(url: "https://github.com/rryam/MusadoraKit", from: "4.0.0"),

        // Fuzzy string matching
        .package(url: "https://github.com/seanoshea/FuzzyMatchingSwift", from: "1.0.0"),
        .package(url: "https://github.com/krisk/fuse-swift", from: "2.1.0"),

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
                .product(name: "SpotifyAPI", package: "SpotifyAPI"),
                .product(name: "MusadoraKit", package: "MusadoraKit"),
                .product(name: "FuzzyMatchingSwift", package: "FuzzyMatchingSwift"),
                .product(name: "Fuse", package: "fuse-swift"),
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
