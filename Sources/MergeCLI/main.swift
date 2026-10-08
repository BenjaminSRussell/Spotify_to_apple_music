import ArgumentParser
import Foundation
import MergeCore

@main
struct MergeCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "merge-cli",
        abstract: "Spotify to Apple Music migration tool",
        version: "0.1.0",
        subcommands: [Import.self, Diff.self, Sync.self, Resume.self, Rollback.self, ExportMetrics.self, Auth.self],
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
                let result = try await runCancellableSync {
                    try await coordinator.performSync(
                        direction: mergeDirection,
                        dryRun: dryRun,
                        autoThreshold: autoThreshold,
                        progress: printProgress
                    )
                }

                if result.cancelled || result.failureCount > 0 {
                    throw ExitCode.failure
                }
            } catch {
                Log.error("Sync failed", error: error)
                throw error
            }
        }
    }
}

// MARK: - Export Metrics Command (#9)

extension MergeCLI {
    struct ExportMetrics: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "export-metrics",
            abstract: "Export per-run sync counts and match-confidence histograms as CSV"
        )

        @Option(name: .long, help: "Runs CSV path; the histogram goes next to it as <name>.histogram.csv")
        var out: String

        @Option(name: .long, help: "SQLite database (default: the app database in Application Support)")
        var db: String?

        @Option(name: .long, help: "Number of equal-width confidence buckets over [0, 1]")
        var buckets: Int = 10

        func validate() throws {
            let ext = URL(fileURLWithPath: out).pathExtension.lowercased()
            if ext == "parquet" {
                throw ValidationError("""
                    Parquet is not written natively. Export CSV and convert, e.g.:
                      python -c "import pandas as p; p.read_csv('report.csv').to_parquet('report.parquet')"
                    """)
            }
            guard ext == "csv" else { throw ValidationError("--out must end in .csv") }
            guard buckets >= 1 else { throw ValidationError("--buckets must be >= 1") }
        }

        func run() throws {
            let provider = try db.map { try DatabaseProvider(path: $0) } ?? DatabaseProvider.createDefault()
            let runsURL = URL(fileURLWithPath: out)
            let histURL = MetricsExporter.histogramURL(for: runsURL)
            let exporter = MetricsExporter(dbQueue: provider.dbQueue, bucketCount: buckets)
            try exporter.writeCSV(runsURL: runsURL, histogramURL: histURL)
            print("Wrote \(runsURL.path)")
            print("Wrote \(histURL.path)")
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

// MARK: - Resume / Rollback (#8, #12)

extension MergeCLI {
    struct Resume: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Resume a cancelled or failed sync, skipping operations already applied"
        )

        @Option(name: .long, help: "Run ID to resume (default: the most recent unfinished run)")
        var runID: String?

        func run() async throws {
            let coordinator = SyncCoordinator()
            let result = try await runCancellableSync {
                try await coordinator.resumeSync(runID: runID, progress: printProgress)
            }
            if result.cancelled || result.failureCount > 0 {
                throw ExitCode.failure
            }
        }
    }

    struct Rollback: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Restore playlist memberships changed by a sync run"
        )

        @Option(name: .long, help: "Run ID whose playlist edits should be undone")
        var runID: String

        func run() async throws {
            let restored = try await SyncCoordinator().rollback(runID: runID)
            print("Restored \(restored) playlist(s) from run \(runID)")
        }
    }
}

// MARK: - Progress + Ctrl-C

/// Prints a status line whenever the sync moves to a new playlist or finishes.
@Sendable func printProgress(_ progress: SyncProgress) {
    guard progress.announcement != nil else { return }
    FileHandle.standardError.write(Data((progress.statusLine + "\n").utf8))
}

/// Runs a sync in a child task and cancels it cooperatively on Ctrl-C (SIGINT):
/// in-flight calls finish, the run is saved as cancelled, and `resume` picks it up.
func runCancellableSync(_ body: @escaping @Sendable () async throws -> SyncResult) async throws -> SyncResult {
    let task = Task { try await body() }
    signal(SIGINT, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
    source.setEventHandler {
        FileHandle.standardError.write(Data("\nCancelling after in-flight operations finish...\n".utf8))
        task.cancel()
    }
    source.resume()
    defer {
        source.cancel()
        signal(SIGINT, SIG_DFL)
    }
    return try await task.value
}
