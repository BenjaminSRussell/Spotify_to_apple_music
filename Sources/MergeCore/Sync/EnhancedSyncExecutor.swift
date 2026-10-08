import Foundation

/// Sync executor with rate limiting, retry/backoff, per-operation checkpoints,
/// cooperative cancellation, and progress reporting (#8, #12).
///
/// - Every operation goes through `remote` inside `retryPolicy`; network remotes also
///   acquire a `rateLimiter` token per attempt, and 429/503 `Retry-After` is honoured.
/// - Each applied operation is checkpointed under the run ID. Re-running with the same
///   run ID (see `SyncCoordinator.resumeSync`) skips operations that already happened.
/// - Cancelling the calling task stops new remote calls; in-flight calls finish, the run
///   is saved as `.cancelled`, and it can be resumed later.
/// - Playlist member updates store the previous membership so `rollbackPlaylists(runID:)`
///   can restore it.
public final class EnhancedSyncExecutor: Sendable {
    private let playlistStore: PlaylistStore
    private let syncRunStore: SyncRunStore
    private let checkpointStore: SyncCheckpointStore?
    private let syncStateStore: PlaylistSyncStateStore?
    private let remote: SyncRemote
    private let retryPolicy: RetryPolicy
    private let rateLimiter: RateLimiter
    private let maxParallelism: Int

    public init(
        trackStore: TrackStore = TrackStoreImpl(),
        playlistStore: PlaylistStore = PlaylistStoreImpl(),
        syncRunStore: SyncRunStore = SyncRunStoreImpl(),
        checkpointStore: SyncCheckpointStore? = nil,
        syncStateStore: PlaylistSyncStateStore? = nil,
        remote: SyncRemote? = nil,
        retryPolicy: RetryPolicy = RetryPolicy(maxAttempts: 4, baseDelay: 2.0),
        rateLimiter: RateLimiter = RateLimiter(requestsPerSecond: 2.0), // Conservative
        maxParallelism: Int = 5
    ) {
        self.playlistStore = playlistStore
        self.syncRunStore = syncRunStore
        self.checkpointStore = checkpointStore
        self.syncStateStore = syncStateStore
        self.remote = remote ?? LocalStoreSyncRemote(trackStore: trackStore, playlistStore: playlistStore)
        self.retryPolicy = retryPolicy
        self.rateLimiter = rateLimiter
        self.maxParallelism = max(1, maxParallelism)
    }

    // MARK: - Execution

    /// Execute (or resume) a sync run.
    /// - Parameters:
    ///   - runID: Reuse an earlier run's ID to resume it; operations checkpointed as done are skipped.
    ///   - progress: Called after every operation, on the executor's task.
    public func execute(
        diff: LibraryDiff,
        direction: MergeDirection,
        dryRun: Bool = false,
        useParallel: Bool = true,
        runID: String? = nil,
        progress: SyncProgressHandler? = nil
    ) async throws -> SyncResult {
        let startTime = Date()
        let runID = runID ?? UUID().uuidString
        let existingRun = try await syncRunStore.fetch(id: runID)
        let completedKeys = try await checkpointStore?.completedKeys(runID: runID) ?? []

        var syncRun = existingRun ?? SyncRun(id: runID, direction: direction, operationsCount: diff.totalOperations)
        syncRun.status = .running
        syncRun.completedAt = nil
        if !dryRun {
            try await syncRunStore.save(syncRun)
        }

        Log.info("🚀 \(existingRun == nil ? "Starting" : "Resuming") sync \(runID) (\(dryRun ? "DRY RUN" : "LIVE"))")
        Log.info("Total operations: \(diff.totalOperations) (\(completedKeys.count) already checkpointed)")

        var state = RunState(runID: runID, total: diff.totalOperations, handler: progress)

        // Phase 1: library tracks (independent, so optionally parallel).
        state.phase = .tracks
        if useParallel {
            await runTracksParallel(diff.trackOps, completedKeys: completedKeys, dryRun: dryRun, state: &state)
        } else {
            for operation in diff.trackOps {
                if Task.isCancelled { state.cancelled = true; break }
                if completedKeys.contains(operation.checkpointKey) { state.skip(); continue }
                let outcome = await perform(operation, dryRun: dryRun)
                await record(outcome, for: operation, previousTrackIDs: nil, dryRun: dryRun, state: &state)
                if state.cancelled { break }
            }
        }

        // Phase 2: playlists (sequential; they depend on the tracks above).
        if !state.cancelled {
            await runPlaylists(diff.playlistOps, completedKeys: completedKeys, dryRun: dryRun, state: &state)
        }
        if Task.isCancelled { state.cancelled = true }

        let duration = Date().timeIntervalSince(startTime)
        if !dryRun {
            syncRun.completedAt = Date()
            syncRun.successCount = state.succeeded + state.skipped
            syncRun.failureCount = state.failed
            syncRun.status = state.cancelled ? .cancelled : (state.failed == 0 ? .completed : .failed)
            syncRun.durationSeconds = (existingRun?.durationSeconds ?? 0) + duration
            let finalRun = syncRun
            let store = syncRunStore
            // Detached from the (possibly cancelled) caller so the final state is always saved.
            try await Task { try await store.save(finalRun) }.value
        }

        if state.cancelled {
            state.phase = .cancelled
            state.emit(announcement: "Sync cancelled. \(state.completed) of \(state.total) operations done.")
            Log.info("⏸️  Sync \(runID) cancelled after \(state.completed)/\(state.total); resume with `merge-cli resume --run-id \(runID)`")
        } else {
            state.phase = .finished
            state.emit(announcement: state.failed == 0
                ? "Sync finished. \(state.total) operations."
                : "Sync finished with \(state.failed) failures.")
            Log.info("✅ Sync complete: \(state.succeeded) succeeded, \(state.skipped) skipped, \(state.failed) failed")
        }

        return SyncResult(
            totalOps: diff.totalOperations,
            successCount: state.succeeded + state.skipped,
            failureCount: state.failed,
            duration: duration,
            errors: state.errors,
            skippedCount: state.skipped,
            cancelled: state.cancelled,
            runID: runID
        )
    }

    /// Restore playlist memberships changed by a run, newest change first.
    /// - Returns: number of playlists restored.
    @discardableResult
    public func rollbackPlaylists(runID: String) async throws -> Int {
        guard let checkpointStore else { return 0 }
        var restored = 0
        for checkpoint in try await checkpointStore.checkpoints(runID: runID).reversed() {
            guard checkpoint.status == .done,
                  let previous = checkpoint.previousTrackIDs,
                  let operation = Self.restoreOperation(for: checkpoint.key, previous: previous) else { continue }
            switch await perform(operation, dryRun: false) {
            case .success:
                restored += 1
            case .failure(let error):
                throw error
            case .cancelled:
                throw CancellationError()
            }
        }
        Log.info("↩️  Rolled back \(restored) playlist(s) from run \(runID)")
        return restored
    }

    // MARK: - Phases

    private func runTracksParallel(
        _ operations: [SyncOperation],
        completedKeys: Set<String>,
        dryRun: Bool,
        state: inout RunState
    ) async {
        var pending = operations.makeIterator()

        func nextToRun(_ state: inout RunState) -> SyncOperation? {
            while let operation = pending.next() {
                if completedKeys.contains(operation.checkpointKey) {
                    state.skip()
                    continue
                }
                return operation
            }
            return nil
        }

        await withTaskGroup(of: (SyncOperation, Outcome).self) { group in
            var active = 0
            while active < maxParallelism, !Task.isCancelled, let operation = nextToRun(&state) {
                group.addTask { (operation, await self.perform(operation, dryRun: dryRun)) }
                active += 1
            }
            while let (operation, outcome) = await group.next() {
                await record(outcome, for: operation, previousTrackIDs: nil, dryRun: dryRun, state: &state)
                // Cooperative cancel: stop scheduling new remote calls; in-flight ones drain.
                if Task.isCancelled || state.cancelled {
                    state.cancelled = true
                    continue
                }
                if let next = nextToRun(&state) {
                    group.addTask { (next, await self.perform(next, dryRun: dryRun)) }
                }
            }
        }
    }

    private func runPlaylists(
        _ operations: [SyncOperation],
        completedKeys: Set<String>,
        dryRun: Bool,
        state: inout RunState
    ) async {
        state.phase = .playlists
        var order: [String] = []
        for id in operations.compactMap({ $0.playlistID?.value }) where !order.contains(id) {
            order.append(id)
        }
        state.playlistCount = order.count
        var names: [String: String] = [:]

        for operation in operations {
            if Task.isCancelled { state.cancelled = true; return }

            if let id = operation.playlistID {
                let index = (order.firstIndex(of: id.value) ?? 0) + 1
                if index != state.playlistIndex {
                    let name = await playlistName(for: operation, cache: &names)
                    state.playlistIndex = index
                    state.playlistName = name
                    state.emit(announcement: "Syncing playlist \(index) of \(state.playlistCount), \(name)")
                }
            }

            if completedKeys.contains(operation.checkpointKey) { state.skip(); continue }

            let previous = dryRun ? nil : await previousMembers(for: operation)
            let outcome = await perform(operation, dryRun: dryRun)
            await record(outcome, for: operation, previousTrackIDs: previous, dryRun: dryRun, state: &state)
            if state.cancelled { return }
        }
    }

    // MARK: - Single operation

    private enum Outcome: @unchecked Sendable {
        case success
        case failure(Error)
        case cancelled
    }

    /// One remote call with rate limiting + retry. Never throws.
    private func perform(_ operation: SyncOperation, dryRun: Bool) async -> Outcome {
        if Task.isCancelled { return .cancelled }
        if dryRun { return .success }
        let remote = self.remote
        let rateLimiter = self.rateLimiter
        do {
            try await retryPolicy.execute(
                operation: {
                    try Task.checkCancellation()
                    if remote.isRateLimited {
                        await rateLimiter.acquire()
                        try Task.checkCancellation()
                    }
                    try await remote.apply(operation)
                },
                shouldRetry: { error in
                    !(error is CancellationError) && RetryPolicy.isRetryableError(error)
                }
            )
            return .success
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failure(error)
        }
    }

    private func record(
        _ outcome: Outcome,
        for operation: SyncOperation,
        previousTrackIDs: [String]?,
        dryRun: Bool,
        state: inout RunState
    ) async {
        let key = operation.checkpointKey
        let runID = state.runID
        switch outcome {
        case .success:
            state.succeeded += 1
            Log.info("  ✅ \(dryRun ? "[DRY RUN] " : "")\(describeOperation(operation))")
            if !dryRun {
                await checkpoint { try await $0.markDone(runID: runID, key: key, previousTrackIDs: previousTrackIDs) }
                await recordPlaylistState(operation)
            }
        case .failure(let error):
            state.failed += 1
            await globalErrorHandler.record(error, context: "Sync")
            state.errors.append(SyncError(operation: describeOperation(operation), error: error.localizedDescription))
            let message = error.localizedDescription
            if !dryRun { await checkpoint { try await $0.markFailed(runID: runID, key: key, error: message) } }
        case .cancelled:
            // Not applied: no checkpoint, so a resume retries it.
            state.cancelled = true
            return
        }
        state.emit()
    }

    /// Checkpoint writes run outside the caller's task so cancellation cannot drop them.
    private func checkpoint(_ write: @escaping @Sendable (SyncCheckpointStore) async throws -> Void) async {
        guard let store = checkpointStore else { return }
        do {
            try await Task { try await write(store) }.value
        } catch {
            Log.error("Failed to write sync checkpoint", error: error)
        }
    }

    /// Remember what a playlist now contains on the target so unchanged playlists are skipped next sync.
    private func recordPlaylistState(_ operation: SyncOperation) async {
        guard let store = syncStateStore, let target = operation.playlistTarget else { return }
        let digest = SyncOperation.digest(target.members)
        do {
            try await Task { try await store.recordApplied(service: target.service, playlistID: target.id, digest: digest) }.value
        } catch {
            Log.error("Failed to record playlist sync state", error: error)
        }
    }

    // MARK: - Helpers

    private func previousMembers(for operation: SyncOperation) async -> [String]? {
        guard checkpointStore != nil else { return nil }
        switch operation {
        case .updateApplePlaylistMembers(let id, _), .updateSpotifyPlaylistMembers(let id, _):
            return (try? await playlistStore.fetch(id: id))??.trackIDs.map(\.value)
        default:
            return nil
        }
    }

    private func playlistName(for operation: SyncOperation, cache: inout [String: String]) async -> String {
        switch operation {
        case .createApplePlaylist(let playlist), .createSpotifyPlaylist(let playlist):
            cache[playlist.id.value] = playlist.name
            return playlist.name
        default:
            guard let id = operation.playlistID else { return "Untitled playlist" }
            if let cached = cache[id.value] { return cached }
            let name = (try? await playlistStore.fetch(id: id))??.name ?? "Untitled playlist"
            cache[id.value] = name
            return name
        }
    }

    static func restoreOperation(for key: String, previous: [String]) -> SyncOperation? {
        // Keys look like "<kind>:<playlistID>:<digest>"; playlist IDs may themselves contain ':'.
        guard let firstColon = key.firstIndex(of: ":"), let lastColon = key.lastIndex(of: ":"),
              firstColon < lastColon else { return nil }
        let kind = key[..<firstColon]
        let playlistID = CanonicalPlaylistID(value: String(key[key.index(after: firstColon)..<lastColon]))
        let tracks = previous.map { CanonicalTrackID(value: $0) }
        switch kind {
        case "updateApplePlaylistMembers": return .updateApplePlaylistMembers(playlistID: playlistID, trackIDs: tracks)
        case "updateSpotifyPlaylistMembers": return .updateSpotifyPlaylistMembers(playlistID: playlistID, trackIDs: tracks)
        default: return nil
        }
    }

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

// MARK: - Run state

/// Mutable counters for one run; owned by the executing task.
private struct RunState {
    let runID: String
    let total: Int
    let handler: SyncProgressHandler?
    var phase: SyncProgress.Phase = .tracks
    var succeeded = 0
    var failed = 0
    var skipped = 0
    var cancelled = false
    var errors: [SyncError] = []
    var playlistName: String?
    var playlistIndex = 0
    var playlistCount = 0

    init(runID: String, total: Int, handler: SyncProgressHandler?) {
        self.runID = runID
        self.total = total
        self.handler = handler
    }

    var completed: Int { succeeded + failed + skipped }

    mutating func skip() {
        skipped += 1
        emit()
    }

    func emit(announcement: String? = nil) {
        handler?(SyncProgress(
            runID: runID,
            phase: phase,
            completed: completed,
            total: total,
            failed: failed,
            skipped: skipped,
            playlistName: phase == .playlists ? playlistName : nil,
            playlistIndex: playlistIndex,
            playlistCount: playlistCount,
            announcement: announcement
        ))
    }
}

// SyncExecutorError is declared in SyncExecutor.swift and shared by both executors.
