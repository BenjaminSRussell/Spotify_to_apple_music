import Foundation

/// High-level coordinator for diff and sync operations
/// Orchestrates the full sync workflow
public final class SyncCoordinator: Sendable {
    private let trackStore: TrackStore
    private let playlistStore: PlaylistStore
    private let diffComputer: DiffComputer
    private let syncExecutor: SyncExecutor

    public init(
        trackStore: TrackStore = TrackStoreImpl(),
        playlistStore: PlaylistStore = PlaylistStoreImpl()
    ) {
        self.trackStore = trackStore
        self.playlistStore = playlistStore
        self.diffComputer = DiffComputer()
        self.syncExecutor = SyncExecutor(trackStore: trackStore, playlistStore: playlistStore)
    }

    // MARK: - Diff Operations

    /// Compute diff for given direction
    public func computeDiff(direction: MergeDirection) async throws -> LibraryDiff {
        Log.info("📊 Computing library diff...")
        Log.info("Direction: \(direction.rawValue)")

        let allTracks = try await trackStore.fetchAll()
        let allPlaylists = try await playlistStore.fetchAll()

        switch direction {
        case .spotifyToApple:
            return try await computeSpotifyToAppleDiff(
                tracks: allTracks,
                playlists: allPlaylists
            )

        case .appleToSpotify:
            return try await computeAppleToSpotifyDiff(
                tracks: allTracks,
                playlists: allPlaylists
            )

        case .bidirectional:
            // For bidirectional, compute both and merge
            let spotifyToApple = try await computeSpotifyToAppleDiff(
                tracks: allTracks,
                playlists: allPlaylists
            )
            let appleToSpotify = try await computeAppleToSpotifyDiff(
                tracks: allTracks,
                playlists: allPlaylists
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
        autoThreshold: Double = 0.85
    ) async throws -> SyncResult {
        // Step 1: Compute diff
        let diff = try await computeDiff(direction: direction)

        // Step 2: Display summary
        let summary = generateDiffSummary(diff: diff, direction: direction)
        print("\n" + summary + "\n")

        if diff.totalOperations == 0 {
            Log.info("✨ Nothing to sync - libraries are in sync!")
            return SyncResult(
                totalOps: 0,
                successCount: 0,
                failureCount: 0,
                duration: 0
            )
        }

        // Step 3: Execute sync
        let result = try await syncExecutor.execute(
            diff: diff,
            direction: direction,
            dryRun: dryRun
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

    // MARK: - Private Helpers

    /// Compute diff for Spotify → Apple Music
    private func computeSpotifyToAppleDiff(
        tracks: [CanonicalTrack],
        playlists: [CanonicalPlaylist]
    ) async throws -> LibraryDiff {
        // Filter to Spotify-only tracks
        let spotifyTracks = tracks.filter { $0.availability.contains(.spotify) }
        let spotifyPlaylists = playlists.filter { $0.sourceSpotifyID != nil }

        return try await diffComputer.computeLibraryDiff(
            sourceTracks: spotifyTracks,
            sourcePlaylists: spotifyPlaylists,
            targetService: .appleMusic
        )
    }

    /// Compute diff for Apple Music → Spotify
    private func computeAppleToSpotifyDiff(
        tracks: [CanonicalTrack],
        playlists: [CanonicalPlaylist]
    ) async throws -> LibraryDiff {
        // Filter to Apple-only tracks
        let appleTracks = tracks.filter { $0.availability.contains(.appleMusic) }
        let applePlaylists = playlists.filter { $0.sourceAppleID != nil }

        return try await diffComputer.computeLibraryDiff(
            sourceTracks: appleTracks,
            sourcePlaylists: applePlaylists,
            targetService: .spotify
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

        output += "\n═══════════════════════════════════════"

        return output
    }
}
