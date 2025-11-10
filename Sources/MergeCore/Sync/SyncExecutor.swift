import Foundation

/// Executes sync operations against music services
/// Supports dry-run mode for preview
public final class SyncExecutor: Sendable {
    private let trackStore: TrackStore
    private let playlistStore: PlaylistStore
    private let syncRunStore: SyncRunStore

    public init(
        trackStore: TrackStore = TrackStoreImpl(),
        playlistStore: PlaylistStore = PlaylistStoreImpl(),
        syncRunStore: SyncRunStore = SyncRunStoreImpl()
    ) {
        self.trackStore = trackStore
        self.playlistStore = playlistStore
        self.syncRunStore = syncRunStore
    }

    // MARK: - Sync Execution

    /// Execute sync operations
    /// - Parameters:
    ///   - diff: Library diff containing operations to execute
    ///   - direction: Sync direction
    ///   - dryRun: If true, only simulate without making actual changes
    public func execute(
        diff: LibraryDiff,
        direction: MergeDirection,
        dryRun: Bool = false
    ) async throws -> SyncResult {
        let startTime = Date()

        // Create sync run record
        let syncRun = SyncRun(
            direction: direction,
            operationsCount: diff.totalOperations
        )

        if !dryRun {
            try await syncRunStore.save(syncRun)
        }

        Log.info("🚀 Starting sync (\(dryRun ? "DRY RUN" : "LIVE"))...")
        Log.info("Total operations: \(diff.totalOperations)")

        var successCount = 0
        var failureCount = 0
        var errors: [SyncError] = []

        // Execute track operations
        for operation in diff.trackOps {
            do {
                if dryRun {
                    Log.info("  [DRY RUN] Would execute: \(describeOperation(operation))")
                    successCount += 1
                } else {
                    try await executeTrackOperation(operation)
                    Log.info("  ✅ \(describeOperation(operation))")
                    successCount += 1
                }
            } catch {
                Log.error("  ❌ Failed: \(describeOperation(operation))", error: error)
                failureCount += 1
                errors.append(SyncError(
                    operation: describeOperation(operation),
                    error: error.localizedDescription
                ))
            }
        }

        // Execute playlist operations
        for operation in diff.playlistOps {
            do {
                if dryRun {
                    Log.info("  [DRY RUN] Would execute: \(describeOperation(operation))")
                    successCount += 1
                } else {
                    try await executePlaylistOperation(operation)
                    Log.info("  ✅ \(describeOperation(operation))")
                    successCount += 1
                }
            } catch {
                Log.error("  ❌ Failed: \(describeOperation(operation))", error: error)
                failureCount += 1
                errors.append(SyncError(
                    operation: describeOperation(operation),
                    error: error.localizedDescription
                ))
            }
        }

        let duration = Date().timeIntervalSince(startTime)

        // Update sync run record
        if !dryRun {
            var updatedRun = syncRun
            updatedRun.completedAt = Date()
            updatedRun.successCount = successCount
            updatedRun.failureCount = failureCount
            updatedRun.status = failureCount == 0 ? .completed : .failed
            updatedRun.durationSeconds = duration

            try await syncRunStore.save(updatedRun)
        }

        Log.info("✅ Sync complete: \(successCount) succeeded, \(failureCount) failed")

        return SyncResult(
            totalOps: diff.totalOperations,
            successCount: successCount,
            failureCount: failureCount,
            duration: duration,
            errors: errors
        )
    }

    // MARK: - Operation Execution

    /// Execute a track sync operation
    private func executeTrackOperation(_ operation: SyncOperation) async throws {
        switch operation {
        case .addTrackToApple(let trackID):
            try await addTrackToAppleMusic(trackID: trackID)

        case .addTrackToSpotify(let trackID):
            try await addTrackToSpotify(trackID: trackID)

        case .removeTrackFromApple(let trackID):
            try await removeTrackFromAppleMusic(trackID: trackID)

        case .removeTrackFromSpotify(let trackID):
            try await removeTrackFromSpotify(trackID: trackID)

        default:
            throw SyncExecutorError.invalidOperation("Not a track operation")
        }
    }

    /// Execute a playlist sync operation
    private func executePlaylistOperation(_ operation: SyncOperation) async throws {
        switch operation {
        case .createApplePlaylist(let playlist):
            try await createAppleMusicPlaylist(playlist: playlist)

        case .createSpotifyPlaylist(let playlist):
            try await createSpotifyPlaylist(playlist: playlist)

        case .updateApplePlaylistMembers(let playlistID, let trackIDs):
            try await updateAppleMusicPlaylistMembers(playlistID: playlistID, trackIDs: trackIDs)

        case .updateSpotifyPlaylistMembers(let playlistID, let trackIDs):
            try await updateSpotifyPlaylistMembers(playlistID: playlistID, trackIDs: trackIDs)

        default:
            throw SyncExecutorError.invalidOperation("Not a playlist operation")
        }
    }

    // MARK: - Service-Specific Operations

    /// Add track to Apple Music library
    private func addTrackToAppleMusic(trackID: CanonicalTrackID) async throws {
        // TODO: Implement Apple Music API call
        // For now, just update our local state
        guard var track = try await trackStore.fetch(id: trackID) else {
            throw SyncExecutorError.trackNotFound(trackID.value)
        }

        track.availability.insert(.appleMusic)
        try await trackStore.save(track)

        Log.debug("Added track to Apple Music: \(track.title)")
    }

    /// Add track to Spotify library
    private func addTrackToSpotify(trackID: CanonicalTrackID) async throws {
        // TODO: Implement Spotify API call
        guard var track = try await trackStore.fetch(id: trackID) else {
            throw SyncExecutorError.trackNotFound(trackID.value)
        }

        track.availability.insert(.spotify)
        try await trackStore.save(track)

        Log.debug("Added track to Spotify: \(track.title)")
    }

    /// Remove track from Apple Music library
    private func removeTrackFromAppleMusic(trackID: CanonicalTrackID) async throws {
        // TODO: Implement Apple Music API call
        guard var track = try await trackStore.fetch(id: trackID) else {
            throw SyncExecutorError.trackNotFound(trackID.value)
        }

        track.availability.remove(.appleMusic)
        try await trackStore.save(track)

        Log.debug("Removed track from Apple Music: \(track.title)")
    }

    /// Remove track from Spotify library
    private func removeTrackFromSpotify(trackID: CanonicalTrackID) async throws {
        // TODO: Implement Spotify API call
        guard var track = try await trackStore.fetch(id: trackID) else {
            throw SyncExecutorError.trackNotFound(trackID.value)
        }

        track.availability.remove(.spotify)
        try await trackStore.save(track)

        Log.debug("Removed track from Spotify: \(track.title)")
    }

    /// Create playlist in Apple Music
    private func createAppleMusicPlaylist(playlist: CanonicalPlaylist) async throws {
        // TODO: Implement Apple Music API call
        try await playlistStore.save(playlist)
        Log.debug("Created Apple Music playlist: \(playlist.name)")
    }

    /// Create playlist in Spotify
    private func createSpotifyPlaylist(playlist: CanonicalPlaylist) async throws {
        // TODO: Implement Spotify API call
        try await playlistStore.save(playlist)
        Log.debug("Created Spotify playlist: \(playlist.name)")
    }

    /// Update Apple Music playlist members
    private func updateAppleMusicPlaylistMembers(
        playlistID: CanonicalPlaylistID,
        trackIDs: [CanonicalTrackID]
    ) async throws {
        // TODO: Implement Apple Music API call
        guard var playlist = try await playlistStore.fetch(id: playlistID) else {
            throw SyncExecutorError.playlistNotFound(playlistID.value)
        }

        playlist.trackIDs = trackIDs
        try await playlistStore.save(playlist)

        Log.debug("Updated Apple Music playlist tracks: \(playlist.name)")
    }

    /// Update Spotify playlist members
    private func updateSpotifyPlaylistMembers(
        playlistID: CanonicalPlaylistID,
        trackIDs: [CanonicalTrackID]
    ) async throws {
        // TODO: Implement Spotify API call
        guard var playlist = try await playlistStore.fetch(id: playlistID) else {
            throw SyncExecutorError.playlistNotFound(playlistID.value)
        }

        playlist.trackIDs = trackIDs
        try await playlistStore.save(playlist)

        Log.debug("Updated Spotify playlist tracks: \(playlist.name)")
    }

    // MARK: - Helpers

    /// Generate human-readable description of operation
    private func describeOperation(_ operation: SyncOperation) -> String {
        switch operation {
        case .addTrackToApple(let trackID):
            return "Add track to Apple Music (\(trackID.value.prefix(8))...)"
        case .addTrackToSpotify(let trackID):
            return "Add track to Spotify (\(trackID.value.prefix(8))...)"
        case .removeTrackFromApple(let trackID):
            return "Remove track from Apple Music (\(trackID.value.prefix(8))...)"
        case .removeTrackFromSpotify(let trackID):
            return "Remove track from Spotify (\(trackID.value.prefix(8))...)"
        case .createApplePlaylist(let playlist):
            return "Create Apple Music playlist: \(playlist.name)"
        case .createSpotifyPlaylist(let playlist):
            return "Create Spotify playlist: \(playlist.name)"
        case .updateApplePlaylistMembers(let playlistID, _):
            return "Update Apple Music playlist tracks (\(playlistID.value.prefix(8))...)"
        case .updateSpotifyPlaylistMembers(let playlistID, _):
            return "Update Spotify playlist tracks (\(playlistID.value.prefix(8))...)"
        }
    }
}

// MARK: - Errors

public enum SyncExecutorError: Error {
    case trackNotFound(String)
    case playlistNotFound(String)
    case invalidOperation(String)
    case apiError(String)
}
