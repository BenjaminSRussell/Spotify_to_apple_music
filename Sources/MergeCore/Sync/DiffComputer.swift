import Foundation

/// Computes diffs between source and target libraries
/// Generates sync operations based on matching results
public struct DiffComputer: Sendable {
    private let matchEngine: MatchEngine

    public init(matchEngine: MatchEngine = MatchEngine()) {
        self.matchEngine = matchEngine
    }

    // MARK: - Diff Computation

    /// Compute diff for tracks from source to target service
    public func computeTrackDiff(
        sourceTracks: [CanonicalTrack],
        targetService: MusicService
    ) async throws -> [SyncOperation] {
        var operations: [SyncOperation] = []

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

        Log.info("Generated \(operations.count) track operations")
        return operations
    }

    /// Compute diff for playlists from source to target service
    public func computePlaylistDiff(
        sourcePlaylists: [CanonicalPlaylist],
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
        targetService: MusicService
    ) async throws -> LibraryDiff {
        let trackOps = try await computeTrackDiff(
            sourceTracks: sourceTracks,
            targetService: targetService
        )

        let playlistOps = try await computePlaylistDiff(
            sourcePlaylists: sourcePlaylists,
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

    /// Create playlist update operation (if needed)
    private func createUpdatePlaylistOperation(
        playlist: CanonicalPlaylist,
        targetService: MusicService
    ) -> SyncOperation? {
        // TODO: Check if playlist tracks differ from target
        // For now, always update to ensure sync
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

        summary += "\n\nTotal Operations: \(diff.totalOperations)"
        summary += "\n═══════════════════════"

        return summary
    }
}
