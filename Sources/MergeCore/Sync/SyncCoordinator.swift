import Foundation

/// High-level coordinator for diff and sync operations
/// Orchestrates the full sync workflow
public final class SyncCoordinator: Sendable {
    private let trackStore: TrackStore
    private let playlistStore: PlaylistStore
    private let diffComputer: DiffComputer
    private let syncRunStore: SyncRunStore
    private let syncStateStore: PlaylistSyncStateStore?
    private let syncExecutor: EnhancedSyncExecutor

    public init(
        trackStore: TrackStore = TrackStoreImpl(),
        playlistStore: PlaylistStore = PlaylistStoreImpl(),
        outcomeStore: MatchOutcomeStore? = MatchOutcomeStoreImpl(),
        syncRunStore: SyncRunStore = SyncRunStoreImpl(),
        checkpointStore: SyncCheckpointStore? = SyncCheckpointStoreImpl(),
        syncStateStore: PlaylistSyncStateStore? = PlaylistSyncStateStoreImpl(),
        mappingStore: MappingStore? = nil,
        remote: SyncRemote? = nil
    ) {
        self.trackStore = trackStore
        self.playlistStore = playlistStore
        self.syncRunStore = syncRunStore
        self.syncStateStore = syncStateStore
        let engine = mappingStore.map { MatchEngine(trackStore: trackStore, mappingStore: $0) }
            ?? MatchEngine(trackStore: trackStore)
        self.diffComputer = DiffComputer(matchEngine: engine, outcomeStore: outcomeStore)
        // Rate-limited, retrying, checkpointed executor (#8) with progress + cancel (#12).
        self.syncExecutor = EnhancedSyncExecutor(
            trackStore: trackStore,
            playlistStore: playlistStore,
            syncRunStore: syncRunStore,
            checkpointStore: checkpointStore,
            syncStateStore: syncStateStore,
            remote: remote
        )
    }

    // MARK: - Diff Operations

    /// Compute diff for given direction
    public func computeDiff(direction: MergeDirection, runID: String? = nil) async throws -> LibraryDiff {
        let full = try await computeFullDiff(direction: direction, runID: runID)
        // Incremental sync (#8): skip playlists whose members match what was last applied.
        guard let syncStateStore else { return full }
        let diff = try await full.incremental(using: syncStateStore)
        let dropped = full.totalOperations - diff.totalOperations
        if dropped > 0 {
            Log.info("⏭️  \(dropped) playlist operation(s) unchanged since last sync")
        }
        return diff
    }

    private func computeFullDiff(direction: MergeDirection, runID: String?) async throws -> LibraryDiff {
        Log.info("📊 Computing library diff...")
        Log.info("Direction: \(direction.rawValue)")

        let allTracks = try await trackStore.fetchAll()
        let allPlaylists = try await playlistStore.fetchAll()

        switch direction {
        case .spotifyToApple:
            return try await computeSpotifyToAppleDiff(
                tracks: allTracks,
                playlists: allPlaylists,
                runID: runID
            )

        case .appleToSpotify:
            return try await computeAppleToSpotifyDiff(
                tracks: allTracks,
                playlists: allPlaylists,
                runID: runID
            )

        case .bidirectional:
            // For bidirectional, compute both and merge
            let spotifyToApple = try await computeSpotifyToAppleDiff(
                tracks: allTracks,
                playlists: allPlaylists,
                runID: runID
            )
            let appleToSpotify = try await computeAppleToSpotifyDiff(
                tracks: allTracks,
                playlists: allPlaylists,
                runID: runID
            )

            return LibraryDiff(
                trackOps: spotifyToApple.trackOps + appleToSpotify.trackOps,
                playlistOps: spotifyToApple.playlistOps + appleToSpotify.playlistOps
            )
        }
    }

    /// Generate diff summary
    public func generateDiffSummary(diff: LibraryDiff, direction: MergeDirection) -> String {
        return diffComputer.generateDiffSummary(diff, direction: direction)
    }

    // MARK: - Sync Operations

    /// Perform full sync workflow
    /// - Parameters:
    ///   - direction: Sync direction
    ///   - dryRun: If true, only preview changes without executing
    ///   - autoThreshold: Confidence threshold for auto-matching (0.0-1.0)
    public func performSync(
        direction: MergeDirection,
        dryRun: Bool = false,
        autoThreshold: Double = 0.85,
        runID: String? = nil,
        progress: SyncProgressHandler? = nil
    ) async throws -> SyncResult {
        // Step 1: Compute diff (match decisions are recorded under this run, #9)
        let runID = runID ?? UUID().uuidString
        let diff = try await computeDiff(direction: direction, runID: runID)

        // Step 2: Display summary
        let summary = generateDiffSummary(diff: diff, direction: direction)
        print("\n" + summary + "\n")

        if diff.totalOperations == 0 {
            Log.info("✨ Nothing to sync - libraries are in sync!")
            return SyncResult(
                totalOps: 0,
                successCount: 0,
                failureCount: 0,
                duration: 0,
                runID: runID
            )
        }

        // Step 3: Execute sync
        let result = try await syncExecutor.execute(
            diff: diff,
            direction: direction,
            dryRun: dryRun,
            runID: runID,
            progress: progress
        )

        // Step 4: Display results
        if dryRun {
            print("\n✅ Dry run complete - no changes were made")
            print("Run without --dry-run to perform actual sync\n")
        } else {
            print("\n" + formatSyncResult(result) + "\n")
        }

        return result
    }

    /// Resume a cancelled or failed run (#8, #12).
    ///
    /// The diff is recomputed for the run's direction against the current library, and
    /// operations already checkpointed under the run are skipped, so nothing is applied twice.
    /// - Parameter runID: Run to resume; defaults to the most recent unfinished run.
    public func resumeSync(
        runID: String? = nil,
        progress: SyncProgressHandler? = nil
    ) async throws -> SyncResult {
        let run: SyncRun?
        if let runID {
            run = try await syncRunStore.fetch(id: runID)
        } else {
            run = try await syncRunStore.fetchLatestResumable()
        }
        guard let run else { throw SyncCoordinatorError.nothingToResume(runID) }
        guard run.status.isResumable else { throw SyncCoordinatorError.alreadyCompleted(run.id) }
        Log.info("▶️  Resuming sync \(run.id) (\(run.direction.rawValue), was \(run.status.rawValue))")
        // Match outcomes were already recorded when the run started; don't double-count them (#9).
        let diff = try await computeDiff(direction: run.direction, runID: nil)
        let result = try await syncExecutor.execute(
            diff: diff,
            direction: run.direction,
            runID: run.id,
            progress: progress
        )
        print("\n" + formatSyncResult(result) + "\n")
        return result
    }

    /// Restore playlist memberships that a run changed.
    @discardableResult
    public func rollback(runID: String) async throws -> Int {
        try await syncExecutor.rollbackPlaylists(runID: runID)
    }

    // MARK: - Private Helpers

    /// Compute diff for Spotify → Apple Music
    private func computeSpotifyToAppleDiff(
        tracks: [CanonicalTrack],
        playlists: [CanonicalPlaylist],
        runID: String?
    ) async throws -> LibraryDiff {
        // Filter to Spotify-only tracks
        let spotifyTracks = tracks.filter { $0.availability.contains(.spotify) }
        let spotifyPlaylists = playlists.filter { $0.sourceSpotifyID != nil }

        return try await diffComputer.computeLibraryDiff(
            sourceTracks: spotifyTracks,
            sourcePlaylists: spotifyPlaylists,
            targetService: .appleMusic,
            runID: runID
        )
    }

    /// Compute diff for Apple Music → Spotify
    private func computeAppleToSpotifyDiff(
        tracks: [CanonicalTrack],
        playlists: [CanonicalPlaylist],
        runID: String?
    ) async throws -> LibraryDiff {
        // Filter to Apple-only tracks
        let appleTracks = tracks.filter { $0.availability.contains(.appleMusic) }
        let applePlaylists = playlists.filter { $0.sourceAppleID != nil }

        return try await diffComputer.computeLibraryDiff(
            sourceTracks: appleTracks,
            sourcePlaylists: applePlaylists,
            targetService: .spotify,
            runID: runID
        )
    }

    /// Format sync result for display
    private func formatSyncResult(_ result: SyncResult) -> String {
        var output = """
        ═══════════════════════════════════════
        🎉 Sync Complete!
        ═══════════════════════════════════════
        Total operations: \(result.totalOps)
        ✅ Succeeded: \(result.successCount)
        """

        if result.failureCount > 0 {
            output += "\n❌ Failed: \(result.failureCount)"
        }

        output += "\n⏱️  Duration: \(String(format: "%.2f", result.duration))s"
        output += "\n📈 Success rate: \(String(format: "%.1f%%", result.successRate * 100))"

        if !result.errors.isEmpty {
            output += "\n\n⚠️  Errors:"
            for error in result.errors.prefix(5) {
                output += "\n  - \(error.operation): \(error.error)"
            }
            if result.errors.count > 5 {
                output += "\n  ... and \(result.errors.count - 5) more"
            }
        }

        if result.skippedCount > 0 {
            output += "\n⏭️  Already applied (resumed): \(result.skippedCount)"
        }
        if let runID = result.runID, result.cancelled || result.failureCount > 0 {
            output += "\n\n\(result.cancelled ? "⏸️  Cancelled" : "⚠️  Partially applied"): finished operations are checkpointed."
            output += "\n   Resume:   merge-cli resume --run-id \(runID)"
            output += "\n   Rollback: merge-cli rollback --run-id \(runID)"
        }

        output += "\n═══════════════════════════════════════"

        return output
    }
}

public enum SyncCoordinatorError: Error, LocalizedError, Equatable {
    case nothingToResume(String?)
    case alreadyCompleted(String)

    public var errorDescription: String? {
        switch self {
        case .nothingToResume(let id?): return "No sync run with ID \(id)."
        case .nothingToResume(nil): return "No cancelled or failed sync run to resume."
        case .alreadyCompleted(let id): return "Sync run \(id) already completed; start a new sync instead."
        }
    }
}
