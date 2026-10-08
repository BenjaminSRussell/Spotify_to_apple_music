import ArgumentParser
import Foundation
import MergeCore

@main
struct MergeCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "merge-cli",
        abstract: "Spotify to Apple Music migration tool",
        version: "0.1.0",
        subcommands: [Import.self, Diff.self, Sync.self, Auth.self],
        defaultSubcommand: nil
    )
}

// MARK: - Import Command

extension MergeCLI {
    struct Import: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Import library from a music service"
        )

        @Flag(name: .long, help: "Import from Spotify")
        var spotify: Bool = false

        @Flag(name: .long, help: "Import from Apple Music")
        var apple: Bool = false

        func run() async throws {
            Log.info("🎵 Spotify to Apple Music Migration CLI v0.1.0")
            Log.info("")

            if !spotify && !apple {
                Log.error("Please specify --spotify or --apple (or both)")
                throw ExitCode.validationFailure
            }

            let coordinator = ImportCoordinator()

            // Import from Spotify
            if spotify {
                do {
                    try await coordinator.importFromSpotify()
                } catch {
                    Log.error("Spotify import failed", error: error)
                    throw error
                }
            }

            // Import from Apple Music
            if apple {
                do {
                    try await coordinator.importFromAppleMusic()
                } catch {
                    Log.error("Apple Music import failed", error: error)
                    throw error
                }
            }

            // Print summary
            Log.info("")
            let summary = try await coordinator.getImportSummary()
            print(summary.summary)
        }
    }
}

// MARK: - Diff Command

extension MergeCLI {
    struct Diff: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Preview changes that would be made during sync"
        )

        @Option(name: .long, help: "Direction: spotify-to-apple, apple-to-spotify, bidirectional")
        var direction: String = "spotify-to-apple"

        func run() async throws {
            Log.info("🎵 Spotify to Apple Music Migration CLI v0.1.0")
            Log.info("")

            let mergeDirection: MergeDirection
            switch direction {
            case "spotify-to-apple":
                mergeDirection = .spotifyToApple
            case "apple-to-spotify":
                mergeDirection = .appleToSpotify
            case "bidirectional":
                mergeDirection = .bidirectional
            default:
                Log.error("Invalid direction: \(direction)")
                throw ExitCode.validationFailure
            }

            let coordinator = SyncCoordinator()

            do {
                let diff = try await coordinator.computeDiff(direction: mergeDirection)
                let summary = coordinator.generateDiffSummary(diff: diff, direction: mergeDirection)

                print("")
                print(summary)
                print("")

                if diff.totalOperations == 0 {
                    Log.info("✨ Nothing to sync - libraries are in sync!")
                } else {
                    Log.info("💡 Run 'merge-cli sync --direction \(direction)' to apply these changes")
                }
            } catch {
                Log.error("Diff computation failed", error: error)
                throw error
            }
        }
    }
}

// MARK: - Sync Command

extension MergeCLI {
    struct Sync: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Perform sync operation"
        )

        @Option(name: .long, help: "Direction: spotify-to-apple, apple-to-spotify, bidirectional")
        var direction: String = "spotify-to-apple"

        @Flag(name: .long, help: "Dry run (don't make actual changes)")
        var dryRun: Bool = false

        @Option(name: .long, help: "Auto-resolve threshold (0.0-1.0)")
        var autoThreshold: Double = 0.85

        func run() async throws {
            Log.info("🎵 Spotify to Apple Music Migration CLI v0.1.0")
            Log.info("")

            let mergeDirection: MergeDirection
            switch direction {
            case "spotify-to-apple":
                mergeDirection = .spotifyToApple
            case "apple-to-spotify":
                mergeDirection = .appleToSpotify
            case "bidirectional":
                mergeDirection = .bidirectional
            default:
                Log.error("Invalid direction: \(direction)")
                throw ExitCode.validationFailure
            }

            Log.info("Direction: \(direction)")
            Log.info("Dry run: \(dryRun)")
            Log.info("Auto-resolve threshold: \(autoThreshold)")
            Log.info("")

            let coordinator = SyncCoordinator()

            do {
                let result = try await coordinator.performSync(
                    direction: mergeDirection,
                    dryRun: dryRun,
                    autoThreshold: autoThreshold
                )

                if result.failureCount > 0 {
                    throw ExitCode.failure
                }
            } catch {
                Log.error("Sync failed", error: error)
                throw error
            }
        }
    }
}

// MARK: - Auth Command (#11)

extension MergeCLI {
    struct Auth: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Inspect or reset stored OAuth credentials (macOS Keychain)",
            subcommands: [Status.self, Reset.self]
        )

        struct Status: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Show which services have stored tokens (values are never printed)")

            func run() throws {
                let store = CredentialStores.platformDefault()
                for service in [MusicService.spotify, .appleMusic] {
                    let line: String
                    if let tokens = try store.load(for: service) {
                        line = tokens.isExpired() ? "expired\(tokens.refreshToken != nil ? " (refreshable)" : "")" : "stored"
                    } else {
                        line = "none"
                    }
                    print("\(service.rawValue): \(line)")
                }
            }
        }

        struct Reset: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Delete stored tokens; you will be asked to sign in again")

            @Option(name: .long, help: "spotify, apple-music, or all")
            var service: String = "all"

            func run() throws {
                let store = CredentialStores.platformDefault()
                switch service {
                case "all": try store.deleteAll()
                case "spotify": try store.delete(for: .spotify)
                case "apple-music", "apple": try store.delete(for: .appleMusic)
                default: throw ValidationError("unknown service \(service)")
                }
                print("Removed stored credentials for \(service)")
            }
        }
    }
}
