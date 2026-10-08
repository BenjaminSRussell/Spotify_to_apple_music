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
        )
    ],
    dependencies: [
        // Database - SQLite with GRDB
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),

        // SHA256 on Linux (CryptoKit is Apple-only); lets MergeCore + tests build anywhere
        .package(url: "https://github.com/apple/swift-crypto", "3.0.0"..<"5.0.0"),

        // CLI argument parsing
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        // MergeCore - Core business logic library
        .target(
            name: "MergeCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))
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

        // Tests
        .testTarget(
            name: "MergeCoreTests",
            dependencies: ["MergeCore"]
        )
    ]
)

// MergeApp - macOS SwiftUI application. SwiftUI only exists on Apple platforms, so the
// app is added on macOS only; MergeCore, MergeCLI and the tests also build on Linux.
#if os(macOS)
package.products.append(.executable(name: "MergeApp", targets: ["MergeApp"]))
package.targets.append(.executableTarget(name: "MergeApp", dependencies: ["MergeCore"]))
#endif
