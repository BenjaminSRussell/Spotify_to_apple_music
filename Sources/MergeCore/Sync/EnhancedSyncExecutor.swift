import Foundation

/// Enhanced sync executor with retry logic, rate limiting, and parallel execution
public final class EnhancedSyncExecutor: Sendable {
    private let trackStore: TrackStore
    private let playlistStore: PlaylistStore
    private let syncRunStore: SyncRunStore
    private let retryPolicy: RetryPolicy
    private let rateLimiter: RateLimiter
    private let maxParallelism: Int
    
    public init(
        trackStore: TrackStore = TrackStoreImpl(),
        playlistStore: PlaylistStore = PlaylistStoreImpl(),
        syncRunStore: SyncRunStore = SyncRunStoreImpl(),
        maxParallelism: Int = 5
    ) {
        self.trackStore = trackStore
        self.playlistStore = playlistStore
        self.syncRunStore = syncRunStore
        self.retryPolicy = RetryPolicy(maxAttempts: 4, baseDelay: 2.0)
        self.rateLimiter = RateLimiter(requestsPerSecond: 2.0) // Conservative
        self.maxParallelism = maxParallelism
    }
    
    // MARK: - Enhanced Sync Execution
    
    /// Execute sync with retry logic and parallel processing
    public func execute(
        diff: LibraryDiff,
        direction: MergeDirection,
        dryRun: Bool = false,
        useParallel: Bool = true
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
        
        Log.info("🚀 Starting enhanced sync (\(dryRun ? "DRY RUN" : "LIVE"))...")
        Log.info("Parallelism: \(useParallel ? "\(maxParallelism) concurrent" : "sequential")")
        Log.info("Total operations: \(diff.totalOperations)")
        
        // Execute operations
        let (successCount, failureCount, errors) = if useParallel {
            await executeParallel(diff: diff, dryRun: dryRun)
        } else {
            await executeSequential(diff: diff, dryRun: dryRun)
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
        
        Log.info("✅ Enhanced sync complete: \(successCount) succeeded, \(failureCount) failed")
        
        return SyncResult(
            totalOps: diff.totalOperations,
            successCount: successCount,
            failureCount: failureCount,
            duration: duration,
            errors: errors
        )
    }
    
    // MARK: - Parallel Execution
    
    private func executeParallel(diff: LibraryDiff, dryRun: Bool) async -> (Int, Int, [SyncError]) {
        var successCount = 0
        var failureCount = 0
        var errors: [SyncError] = []
        
        // Execute track operations in parallel
        await withTaskGroup(of: Result<String, Error>.self) { group in
            var activeCount = 0
            var iterator = diff.trackOps.makeIterator()
            
            // Start initial batch
            while activeCount < maxParallelism, let operation = iterator.next() {
                group.addTask {
                    await self.executeWithRetry(operation: operation, dryRun: dryRun, isTrack: true)
                }
                activeCount += 1
            }
            
            // Process remaining
            while let result = await group.next() {
                switch result {
                case .success(let desc):
                    successCount += 1
                    Log.info("  ✅ \(desc)")
                case .failure(let error):
                    failureCount += 1
                    await globalErrorHandler.record(error, context: "Parallel sync")
                    errors.append(SyncError(
                        operation: "Track operation",
                        error: error.localizedDescription
                    ))
                }
                
                // Add next operation if available
                if let operation = iterator.next() {
                    group.addTask {
                        await self.executeWithRetry(operation: operation, dryRun: dryRun, isTrack: true)
                    }
                }
            }
        }
        
        // Execute playlist operations (sequential, they depend on tracks)
        for operation in diff.playlistOps {
            let result = await executeWithRetry(operation: operation, dryRun: dryRun, isTrack: false)
            switch result {
            case .success(let desc):
                successCount += 1
                Log.info("  ✅ \(desc)")
            case .failure(let error):
                failureCount += 1
                await globalErrorHandler.record(error, context: "Parallel sync")
                errors.append(SyncError(
                    operation: "Playlist operation",
                    error: error.localizedDescription
                ))
            }
        }
        
        return (successCount, failureCount, errors)
    }
    
    // MARK: - Sequential Execution
    
    private func executeSequential(diff: LibraryDiff, dryRun: Bool) async -> (Int, Int, [SyncError]) {
        var successCount = 0
        var failureCount = 0
        var errors: [SyncError] = []
        
        // Track operations
        for operation in diff.trackOps {
            let result = await executeWithRetry(operation: operation, dryRun: dryRun, isTrack: true)
            switch result {
            case .success(let desc):
                successCount += 1
                Log.info("  ✅ \(desc)")
            case .failure(let error):
                failureCount += 1
                await globalErrorHandler.record(error, context: "Sequential sync")
                errors.append(SyncError(
                    operation: describeOperation(operation),
                    error: error.localizedDescription
                ))
            }
        }
        
        // Playlist operations
        for operation in diff.playlistOps {
            let result = await executeWithRetry(operation: operation, dryRun: dryRun, isTrack: false)
            switch result {
            case .success(let desc):
                successCount += 1
                Log.info("  ✅ \(desc)")
            case .failure(let error):
                failureCount += 1
                await globalErrorHandler.record(error, context: "Sequential sync")
                errors.append(SyncError(
                    operation: describeOperation(operation),
                    error: error.localizedDescription
                ))
            }
        }
        
        return (successCount, failureCount, errors)
    }
    
    // MARK: - Operation Execution with Retry
    
    private func executeWithRetry(
        operation: SyncOperation,
        dryRun: Bool,
        isTrack: Bool
    ) async -> Result<String, Error> {
        do {
            // Acquire rate limit token
            await rateLimiter.acquire()
            
            // Execute with retry
            try await retryPolicy.execute(
                operation: {
                    if dryRun {
                        // Dry run - just return success
                        return
                    }
                    
                    if isTrack {
                        try await self.executeTrackOperation(operation)
                    } else {
                        try await self.executePlaylistOperation(operation)
                    }
                },
                shouldRetry: { error in
                    await globalErrorHandler.shouldRetry(error, attempt: 0, maxAttempts: 4)
                }
            )
            
            let description = dryRun ? "[DRY RUN] \(describeOperation(operation))" : describeOperation(operation)
            return .success(description)
        } catch {
            return .failure(error)
        }
    }
    
    // MARK: - Low-level Operations
    
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
    
    // MARK: - Service Operations (stubs for now)
    
    private func addTrackToAppleMusic(trackID: CanonicalTrackID) async throws {
        guard var track = try await trackStore.fetch(id: trackID) else {
            throw SyncExecutorError.trackNotFound(trackID.value)
        }
        track.availability.insert(.appleMusic)
        try await trackStore.save(track)
    }
    
    private func addTrackToSpotify(trackID: CanonicalTrackID) async throws {
        guard var track = try await trackStore.fetch(id: trackID) else {
            throw SyncExecutorError.trackNotFound(trackID.value)
        }
        track.availability.insert(.spotify)
        try await trackStore.save(track)
    }
    
    private func removeTrackFromAppleMusic(trackID: CanonicalTrackID) async throws {
        guard var track = try await trackStore.fetch(id: trackID) else {
            throw SyncExecutorError.trackNotFound(trackID.value)
        }
        track.availability.remove(.appleMusic)
        try await trackStore.save(track)
    }
    
    private func removeTrackFromSpotify(trackID: CanonicalTrackID) async throws {
        guard var track = try await trackStore.fetch(id: trackID) else {
            throw SyncExecutorError.trackNotFound(trackID.value)
        }
        track.availability.remove(.spotify)
        try await trackStore.save(track)
    }
    
    private func createAppleMusicPlaylist(playlist: CanonicalPlaylist) async throws {
        try await playlistStore.save(playlist)
    }
    
    private func createSpotifyPlaylist(playlist: CanonicalPlaylist) async throws {
        try await playlistStore.save(playlist)
    }
    
    private func updateAppleMusicPlaylistMembers(
        playlistID: CanonicalPlaylistID,
        trackIDs: [CanonicalTrackID]
    ) async throws {
        guard var playlist = try await playlistStore.fetch(id: playlistID) else {
            throw SyncExecutorError.playlistNotFound(playlistID.value)
        }
        playlist.trackIDs = trackIDs
        try await playlistStore.save(playlist)
    }
    
    private func updateSpotifyPlaylistMembers(
        playlistID: CanonicalPlaylistID,
        trackIDs: [CanonicalTrackID]
    ) async throws {
        guard var playlist = try await playlistStore.fetch(id: playlistID) else {
            throw SyncExecutorError.playlistNotFound(playlistID.value)
        }
        playlist.trackIDs = trackIDs
        try await playlistStore.save(playlist)
    }
    
    // MARK: - Helpers
    
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

public enum SyncExecutorError: Error {
    case trackNotFound(String)
    case playlistNotFound(String)
    case invalidOperation(String)
}
