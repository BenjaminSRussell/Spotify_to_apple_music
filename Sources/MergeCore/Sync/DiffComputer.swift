import Foundation

/// Computes diffs between source and target libraries
/// Generates sync operations based on matching results
///
/// This is the **single diff entrypoint** for MergeCore (#16). The old
/// `LibraryDiffEngine` stub always returned an empty diff, which looked like a successful
/// no-op sync; it has been removed.
public struct DiffComputer: Sendable {
    private let matchEngine: MatchEngine
    /// When set, every match decision is persisted for `merge-cli export-metrics` (#9)
    private let outcomeStore: MatchOutcomeStore?

    public init(matchEngine: MatchEngine = MatchEngine(), outcomeStore: MatchOutcomeStore? = nil) {
        self.matchEngine = matchEngine
        self.outcomeStore = outcomeStore
    }

    // MARK: - Diff Computation

    /// Compute diff for tracks from source to target service
    public func computeTrackDiff(
        sourceTracks: [CanonicalTrack],
        targetService: MusicService,
        runID: String? = nil
    ) async throws -> [SyncOperation] {
        var operations: [SyncOperation] = []
        var outcomes: [MatchOutcome] = []

        Log.info("Computing track diff for \(sourceTracks.count) source tracks...")

        // Match each source track to target service
        for sourceTrack in sourceTracks {
            // Check if track already exists in target
            if trackExistsInTarget(sourceTrack, targetService: targetService) {
                // Already synced, skip
                continue
            }

            // Try to match track in target service
            let decision: MatchDecision
            if targetService == .appleMusic {
                decision = try await matchEngine.matchSpotifyTrackToApple(sourceTrack)
            } else {
                decision = try await matchEngine.matchAppleTrackToSpotify(sourceTrack)
            }
            if outcomeStore != nil {
                outcomes.append(MatchOutcome(decision: decision, source: sourceTrack, targetService: targetService, runID: runID))
            }

            switch decision {
            case .auto(let match):
                // Found automatic match - track exists but needs linking
                Log.debug("Auto-matched track: \(sourceTrack.title)")
                // No operation needed - track already exists

            case .ambiguous:
                // Needs manual resolution - skip for now
                Log.debug("Ambiguous match for: \(sourceTrack.title) - skipping")

            case .noMatch:
                // No match found - need to add to target
                let operation = createAddOperation(
                    track: sourceTrack,
                    targetService: targetService
                )
                operations.append(operation)
            }
        }

        if let store = outcomeStore {
            try await store.record(outcomes)
        }

        Log.info("Generated \(operations.count) track operations")
        return operations
    }

    /// Compute diff for playlists from source to target service
    ///
    /// - Parameter targetPlaylists: Known state of playlists on the target service. A source
    ///   playlist that already exists on the target is only updated when its members differ
    ///   from the matching target playlist. If the target contents are unknown (not in this
    ///   list), an update is emitted so the target is brought in line.
    public func computePlaylistDiff(
        sourcePlaylists: [CanonicalPlaylist],
        targetPlaylists: [CanonicalPlaylist] = [],
        targetService: MusicService
    ) async throws -> [SyncOperation] {
        var operations: [SyncOperation] = []

        Log.info("Computing playlist diff for \(sourcePlaylists.count) playlists...")

        for playlist in sourcePlaylists {
            // Check if playlist already exists in target
            if playlistExistsInTarget(playlist, targetService: targetService) {
                // Playlist exists - check if tracks need updating
                if let updateOp = createUpdatePlaylistOperation(
                    playlist: playlist,
                    target: findTargetPlaylist(for: playlist, in: targetPlaylists, targetService: targetService),
                    targetService: targetService
                ) {
                    operations.append(updateOp)
                }
            } else {
                // Playlist doesn't exist - create it
                let createOp = createPlaylistOperation(
                    playlist: playlist,
                    targetService: targetService
                )
                operations.append(createOp)
            }
        }

        Log.info("Generated \(operations.count) playlist operations")
        return operations
    }

    /// Compute full library diff (tracks + playlists)
    public func computeLibraryDiff(
        sourceTracks: [CanonicalTrack],
        sourcePlaylists: [CanonicalPlaylist],
        targetPlaylists: [CanonicalPlaylist] = [],
        targetService: MusicService,
        runID: String? = nil
    ) async throws -> LibraryDiff {
        let trackOps = try await computeTrackDiff(
            sourceTracks: sourceTracks,
            targetService: targetService,
            runID: runID
        )

        let playlistOps = try await computePlaylistDiff(
            sourcePlaylists: sourcePlaylists,
            targetPlaylists: targetPlaylists,
            targetService: targetService
        )

        return LibraryDiff(trackOps: trackOps, playlistOps: playlistOps)
    }

    // MARK: - Helper Methods

    /// Check if track already exists in target service
    private func trackExistsInTarget(
        _ track: CanonicalTrack,
        targetService: MusicService
    ) -> Bool {
        return track.availability.contains(targetService)
    }

    /// Check if playlist already exists in target service
    private func playlistExistsInTarget(
        _ playlist: CanonicalPlaylist,
        targetService: MusicService
    ) -> Bool {
        switch targetService {
        case .spotify:
            return playlist.sourceSpotifyID != nil
        case .appleMusic:
            return playlist.sourceAppleID != nil
        }
    }

    /// Create add track operation for target service
    private func createAddOperation(
        track: CanonicalTrack,
        targetService: MusicService
    ) -> SyncOperation {
        switch targetService {
        case .appleMusic:
            return .addTrackToApple(canonicalTrackID: track.id)
        case .spotify:
            return .addTrackToSpotify(canonicalTrackID: track.id)
        }
    }

    /// Create playlist creation operation
    private func createPlaylistOperation(
        playlist: CanonicalPlaylist,
        targetService: MusicService
    ) -> SyncOperation {
        switch targetService {
        case .appleMusic:
            return .createApplePlaylist(playlist: playlist)
        case .spotify:
            return .createSpotifyPlaylist(playlist: playlist)
        }
    }

    /// Find the target-side copy of `playlist`: same canonical ID, or same ID on the target service
    private func findTargetPlaylist(
        for playlist: CanonicalPlaylist,
        in targetPlaylists: [CanonicalPlaylist],
        targetService: MusicService
    ) -> CanonicalPlaylist? {
        if let byID = targetPlaylists.first(where: { $0.id == playlist.id }) {
            return byID
        }
        let serviceID: (CanonicalPlaylist) -> String? = {
            targetService == .appleMusic ? $0.sourceAppleID : $0.sourceSpotifyID
        }
        guard let wanted = serviceID(playlist) else { return nil }
        return targetPlaylists.first { serviceID($0) == wanted }
    }

    /// Create playlist update operation (if needed)
    /// Returns nil when the known target playlist already has the same members in the same order.
    private func createUpdatePlaylistOperation(
        playlist: CanonicalPlaylist,
        target: CanonicalPlaylist?,
        targetService: MusicService
    ) -> SyncOperation? {
        if let target = target, target.trackIDs == playlist.trackIDs {
            return nil
        }
        switch targetService {
        case .appleMusic:
            return .updateApplePlaylistMembers(
                playlistID: playlist.id,
                trackIDs: playlist.trackIDs
            )
        case .spotify:
            return .updateSpotifyPlaylistMembers(
                playlistID: playlist.id,
                trackIDs: playlist.trackIDs
            )
        }
    }

    // MARK: - Summary Generation

    /// Generate human-readable diff summary
    public func generateDiffSummary(_ diff: LibraryDiff, direction: MergeDirection) -> String {
        var summary = """
        📊 Library Diff Summary
        ═══════════════════════
        Direction: \(direction.rawValue)
        
        Track Operations: \(diff.trackOps.count)
        """

        // Count operation types for tracks
        let addToApple = diff.trackOps.filter {
            if case .addTrackToApple = $0 { return true }
            return false
        }.count

        let addToSpotify = diff.trackOps.filter {
            if case .addTrackToSpotify = $0 { return true }
            return false
        }.count

        if addToApple > 0 {
            summary += "\n  - Add to Apple Music: \(addToApple)"
        }
        if addToSpotify > 0 {
            summary += "\n  - Add to Spotify: \(addToSpotify)"
        }

        summary += "\n\nPlaylist Operations: \(diff.playlistOps.count)"

        let createApplePlaylists = diff.playlistOps.filter {
            if case .createApplePlaylist = $0 { return true }
            return false
        }.count

        let createSpotifyPlaylists = diff.playlistOps.filter {
            if case .createSpotifyPlaylist = $0 { return true }
            return false
        }.count

        if createApplePlaylists > 0 {
            summary += "\n  - Create in Apple Music: \(createApplePlaylists)"
        }
        if createSpotifyPlaylists > 0 {
            summary += "\n  - Create in Spotify: \(createSpotifyPlaylists)"
        }

        let updatePlaylists = diff.playlistOps.filter {
            switch $0 {
            case .updateApplePlaylistMembers, .updateSpotifyPlaylistMembers: return true
            default: return false
            }
        }.count
        if updatePlaylists > 0 {
            summary += "\n  - Update members: \(updatePlaylists)"
        }

        summary += "\n\nTotal Operations: \(diff.totalOperations)"
        summary += "\n═══════════════════════"

        return summary
    }
}
