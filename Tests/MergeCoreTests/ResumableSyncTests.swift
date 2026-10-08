import XCTest
@testable import MergeCore

// MARK: - Test doubles

/// Records every remote call (one entry per attempt).
private actor CallLog {
    private(set) var calls: [String] = []

    /// Appends the call and returns how many times this key has been attempted.
    func add(_ key: String) -> Int {
        calls.append(key)
        return calls.filter { $0 == key }.count
    }

    var count: Int { calls.count }
    var distinct: Set<String> { Set(calls) }
}

/// Remote whose behaviour is scripted per call; `wrapped` optionally applies the op for real.
private struct ScriptedRemote: SyncRemote {
    let log: CallLog
    var wrapped: SyncRemote?
    let behavior: @Sendable (SyncOperation, _ attempt: Int, _ totalCalls: Int) async throws -> Void

    func apply(_ operation: SyncOperation) async throws {
        let attempt = await log.add(operation.checkpointKey)
        let total = await log.count
        try await behavior(operation, attempt, total)
        try await wrapped?.apply(operation)
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [SyncProgress] = []

    var handler: SyncProgressHandler {
        { [self] progress in lock.lock(); events.append(progress); lock.unlock() }
    }

    var all: [SyncProgress] {
        lock.lock(); defer { lock.unlock() }
        return events
    }
}

private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _task: Task<SyncResult, Error>?
    var task: Task<SyncResult, Error>? {
        get { lock.lock(); defer { lock.unlock() }; return _task }
        set { lock.lock(); _task = newValue; lock.unlock() }
    }
}

// MARK: - Tests

/// #8: retry/backoff, rate limiting, checkpoints, incremental sync, rollback.
/// #12: cooperative cancel, resume from checkpoint, playlist-level progress.
final class ResumableSyncTests: XCTestCase {
    private var db: DatabaseProvider!
    private var trackStore: TrackStoreImpl!
    private var playlistStore: PlaylistStoreImpl!
    private var runStore: SyncRunStoreImpl!
    private var checkpoints: SyncCheckpointStoreImpl!

    override func setUp() async throws {
        db = try DatabaseProvider.inMemory()
        trackStore = TrackStoreImpl(dbQueue: db.dbQueue)
        playlistStore = PlaylistStoreImpl(dbQueue: db.dbQueue)
        runStore = SyncRunStoreImpl(dbQueue: db.dbQueue)
        checkpoints = SyncCheckpointStoreImpl(dbQueue: db.dbQueue)
    }

    private func executor(remote: SyncRemote, parallelism: Int = 1) -> EnhancedSyncExecutor {
        EnhancedSyncExecutor(
            trackStore: trackStore,
            playlistStore: playlistStore,
            syncRunStore: runStore,
            checkpointStore: checkpoints,
            remote: remote,
            retryPolicy: RetryPolicy(maxAttempts: 4, baseDelay: 0.001, maxDelay: 0.01, jitterFactor: 0),
            rateLimiter: RateLimiter(requestsPerSecond: 1_000),
            maxParallelism: parallelism
        )
    }

    private func trackOps(_ count: Int) -> [SyncOperation] {
        (0..<count).map { .addTrackToApple(canonicalTrackID: CanonicalTrackID(value: "t\($0)")) }
    }

    private func track(_ id: String, _ availability: AvailabilityFlags) -> CanonicalTrack {
        CanonicalTrack(
            id: CanonicalTrackID(value: id),
            title: "Unique Song \(id)",
            artist: "Artist \(id)",
            spotifyID: availability.contains(.spotify) ? "sp-\(id)" : nil,
            appleID: availability.contains(.appleMusic) ? "am-\(id)" : nil,
            availability: availability
        )
    }

    private func coordinator(remote: SyncRemote) -> SyncCoordinator {
        SyncCoordinator(
            trackStore: trackStore,
            playlistStore: playlistStore,
            outcomeStore: nil,
            syncRunStore: runStore,
            checkpointStore: checkpoints,
            syncStateStore: PlaylistSyncStateStoreImpl(dbQueue: db.dbQueue),
            mappingStore: MappingStoreImpl(dbQueue: db.dbQueue),
            remote: remote
        )
    }

    // MARK: Retry / rate limit (#8)

    func test429IsRetriedWithBackoffThenSucceeds() async throws {
        let log = CallLog()
        let remote = ScriptedRemote(log: log) { _, attempt, _ in
            if attempt <= 2 { throw HTTPError(statusCode: 429, message: "Too Many Requests", retryAfter: 0.01) }
        }
        let result = try await executor(remote: remote).execute(
            diff: LibraryDiff(trackOps: trackOps(1), playlistOps: []),
            direction: .spotifyToApple,
            useParallel: false
        )
        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.failureCount, 0)
        let calls = await log.count
        XCTAssertEqual(calls, 3, "two 429s then success")
    }

    func testRetryAfterHeaderIsHonouredAndCapped() {
        XCTAssertEqual(RetryPolicy.honoringRetryAfter(HTTPError(statusCode: 429, retryAfter: 2), backoff: 0.5), 2)
        XCTAssertEqual(RetryPolicy.honoringRetryAfter(HTTPError(statusCode: 429, retryAfter: 0.1), backoff: 0.5), 0.5)
        XCTAssertEqual(RetryPolicy.honoringRetryAfter(HTTPError(statusCode: 429, retryAfter: 9_999), backoff: 1), 300)
        XCTAssertEqual(RetryPolicy.honoringRetryAfter(HTTPError(statusCode: 500), backoff: 1.5), 1.5)
    }

    func testNonRetryableErrorFailsOnceAndIsCheckpointedAsFailed() async throws {
        let log = CallLog()
        let remote = ScriptedRemote(log: log) { _, _, _ in throw HTTPError(statusCode: 404) }
        let result = try await executor(remote: remote).execute(
            diff: LibraryDiff(trackOps: trackOps(1), playlistOps: []),
            direction: .spotifyToApple,
            useParallel: false,
            runID: "run-404"
        )
        XCTAssertEqual(result.failureCount, 1)
        let calls = await log.count
        XCTAssertEqual(calls, 1, "404 is not retried")
        let rows = try await checkpoints.checkpoints(runID: "run-404")
        XCTAssertEqual(rows.map(\.status), [.failed])
        let status = try await runStore.fetch(id: "run-404")?.status
        XCTAssertEqual(status, .failed)
    }

    // MARK: Cancel + resume (#12)

    func testCancelStopsFurtherCallsAndResumeSkipsCheckpointedOperations() async throws {
        let log = CallLog()
        let cancelling = ScriptedRemote(log: log) { _, _, total in
            if total == 3 { withUnsafeCurrentTask { $0?.cancel() } }
        }
        let recorder = ProgressRecorder()
        let diff = LibraryDiff(trackOps: trackOps(6), playlistOps: [])

        let first = try await Task {
            try await self.executor(remote: cancelling).execute(
                diff: diff, direction: .spotifyToApple, useParallel: false,
                runID: "run-cancel", progress: recorder.handler
            )
        }.value

        XCTAssertTrue(first.cancelled)
        XCTAssertEqual(first.successCount, 3)
        var calls = await log.count
        XCTAssertEqual(calls, 3, "no API calls after cancel")
        let cancelledStatus = try await runStore.fetch(id: "run-cancel")?.status
        XCTAssertEqual(cancelledStatus, .cancelled)
        XCTAssertEqual(recorder.all.last?.phase, .cancelled)
        XCTAssertNotNil(recorder.all.last?.announcement)

        let plain = ScriptedRemote(log: log) { _, _, _ in }
        let resumed = try await executor(remote: plain).execute(
            diff: diff, direction: .spotifyToApple, useParallel: false, runID: "run-cancel"
        )
        XCTAssertFalse(resumed.cancelled)
        XCTAssertEqual(resumed.skippedCount, 3)
        XCTAssertEqual(resumed.successCount, 6)
        calls = await log.count
        let distinct = await log.distinct
        XCTAssertEqual(calls, 6, "each operation hit the API exactly once across both runs")
        XCTAssertEqual(distinct.count, 6)
        let doneStatus = try await runStore.fetch(id: "run-cancel")?.status
        XCTAssertEqual(doneStatus, .completed)
    }

    func testCancelDuringParallelSyncStopsSchedulingNewCalls() async throws {
        let log = CallLog()
        let box = TaskBox()
        let remote = ScriptedRemote(log: log) { _, _, total in
            while box.task == nil { await Task.yield() }
            if total == 3 { box.task?.cancel() }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        let exec = executor(remote: remote, parallelism: 2)
        let diff = LibraryDiff(trackOps: trackOps(40), playlistOps: [])
        box.task = Task { try await exec.execute(diff: diff, direction: .spotifyToApple, runID: "run-par") }
        let result = try await box.task!.value

        XCTAssertTrue(result.cancelled)
        let calls = await log.count
        XCTAssertLessThanOrEqual(calls, 3 + 2, "only in-flight calls finish after cancel")
        let done = try await checkpoints.completedKeys(runID: "run-par")
        XCTAssertEqual(done.count, result.successCount)
    }

    // MARK: Progress (#12)

    func testProgressReportsPlaylistNameIndexAndCounts() async throws {
        let log = CallLog()
        let remote = ScriptedRemote(log: log) { _, _, _ in }
        let recorder = ProgressRecorder()
        let road = CanonicalPlaylist(id: CanonicalPlaylistID(value: "p1"), name: "Road Trip", trackIDs: [])
        let focus = CanonicalPlaylist(id: CanonicalPlaylistID(value: "p2"), name: "Focus", trackIDs: [])
        let diff = LibraryDiff(
            trackOps: trackOps(2),
            playlistOps: [.createApplePlaylist(playlist: road), .createApplePlaylist(playlist: focus)]
        )
        _ = try await executor(remote: remote).execute(
            diff: diff, direction: .spotifyToApple, useParallel: false, progress: recorder.handler
        )

        let events = recorder.all
        let roadEvent = try XCTUnwrap(events.first { $0.playlistName == "Road Trip" })
        XCTAssertEqual(roadEvent.playlistIndex, 1)
        XCTAssertEqual(roadEvent.playlistCount, 2)
        XCTAssertEqual(roadEvent.statusLine, "Playlist 1 of 2: Road Trip · 2 of 4 operations")
        XCTAssertEqual(roadEvent.announcement, "Syncing playlist 1 of 2, Road Trip")
        XCTAssertTrue(events.contains { $0.playlistName == "Focus" && $0.playlistIndex == 2 })
        XCTAssertEqual(events.last?.phase, .finished)
        XCTAssertEqual(events.last?.fraction, 1)
        XCTAssertEqual(events.map(\.completed), events.map(\.completed).sorted(), "progress never goes backwards")
    }

    // MARK: Incremental sync (#8)

    func testSecondSyncOfUnchangedLibraryPerformsNoWrites() async throws {
        try await trackStore.save(track("a", .spotify))
        try await trackStore.save(track("b", .spotify))
        var playlist = CanonicalPlaylist(
            id: CanonicalPlaylistID(value: "pl"),
            name: "Mix",
            trackIDs: [CanonicalTrackID(value: "a"), CanonicalTrackID(value: "b")],
            sourceSpotifyID: "sp-pl"
        )
        try await playlistStore.save(playlist)

        let log = CallLog()
        let remote = ScriptedRemote(
            log: log,
            wrapped: LocalStoreSyncRemote(trackStore: trackStore, playlistStore: playlistStore)
        ) { _, _, _ in }
        let sync = coordinator(remote: remote)

        let first = try await sync.performSync(direction: .spotifyToApple)
        XCTAssertEqual(first.successCount, 3, "2 tracks + 1 playlist")
        let afterFirst = await log.count

        let second = try await sync.performSync(direction: .spotifyToApple)
        XCTAssertEqual(second.totalOps, 0)
        let afterSecond = await log.count
        XCTAssertEqual(afterSecond, afterFirst, "unchanged library: zero writes")

        // A real change produces exactly one member update, not a re-create.
        playlist.trackIDs = [CanonicalTrackID(value: "b")]
        try await playlistStore.save(playlist)
        let diff = try await sync.computeDiff(direction: .spotifyToApple)
        XCTAssertEqual(diff.totalOperations, 1)
        guard case .updateApplePlaylistMembers(_, let members)? = diff.playlistOps.first else {
            return XCTFail("expected a member update, got \(diff.playlistOps)")
        }
        XCTAssertEqual(members.map(\.value), ["b"])
    }

    // MARK: Partial failure, resume, rollback (#8)

    func testFailedPlaylistApplyIsResumableAndRollbackRestoresMembers() async throws {
        try await trackStore.save(track("a", [.spotify, .appleMusic]))
        try await trackStore.save(track("b", [.spotify, .appleMusic]))
        let ok = CanonicalPlaylist(id: CanonicalPlaylistID(value: "ok"), name: "Works", sourceSpotifyID: "sp-ok")
        let flaky = CanonicalPlaylist(id: CanonicalPlaylistID(value: "flaky"), name: "Flaky", sourceSpotifyID: "sp-flaky")
        try await playlistStore.save(ok)
        try await playlistStore.save(flaky)

        let log = CallLog()
        let local = LocalStoreSyncRemote(trackStore: trackStore, playlistStore: playlistStore)
        let failFlakyOnce = ScriptedRemote(log: log, wrapped: local) { operation, attempt, _ in
            if operation.playlistID?.value == "flaky", attempt == 1 { throw HTTPError(statusCode: 400) }
        }
        let sync = coordinator(remote: failFlakyOnce)

        let first = try await sync.performSync(direction: .spotifyToApple)
        XCTAssertEqual(first.failureCount, 1)
        let runID = try XCTUnwrap(first.runID)
        let failedStatus = try await runStore.fetch(id: runID)?.status
        XCTAssertEqual(failedStatus, .failed)
        let resumable = try await runStore.fetchLatestResumable()
        XCTAssertEqual(resumable?.id, runID)

        let resumed = try await sync.resumeSync()
        XCTAssertEqual(resumed.runID, runID)
        XCTAssertEqual(resumed.failureCount, 0)
        let flakyCalls = await log.calls.filter { $0.contains("flaky") }.count
        let okCalls = await log.calls.filter { $0.contains(":ok") }.count
        XCTAssertEqual(flakyCalls, 2, "failed playlist retried on resume")
        XCTAssertEqual(okCalls, 1, "applied playlist not repeated")
        let completedStatus = try await runStore.fetch(id: runID)?.status
        XCTAssertEqual(completedStatus, .completed)
        do {
            _ = try await sync.resumeSync(runID: runID)
            XCTFail("completed runs are not resumable")
        } catch let error as SyncCoordinatorError {
            XCTAssertEqual(error, .alreadyCompleted(runID))
        }

        // Member update with rollback metadata.
        var apple = ok
        apple.sourceAppleID = "am-ok"
        apple.trackIDs = [CanonicalTrackID(value: "a")]
        try await playlistStore.save(apple)
        let exec = executor(remote: local)
        let update = LibraryDiff(trackOps: [], playlistOps: [
            .updateApplePlaylistMembers(playlistID: ok.id, trackIDs: [CanonicalTrackID(value: "a"), CanonicalTrackID(value: "b")])
        ])
        _ = try await exec.execute(diff: update, direction: .spotifyToApple, useParallel: false, runID: "run-upd")
        var stored = try await playlistStore.fetch(id: ok.id)
        XCTAssertEqual(stored?.trackIDs.map(\.value), ["a", "b"])

        let restored = try await exec.rollbackPlaylists(runID: "run-upd")
        XCTAssertEqual(restored, 1)
        stored = try await playlistStore.fetch(id: ok.id)
        XCTAssertEqual(stored?.trackIDs.map(\.value), ["a"])
    }

    // MARK: Units

    func testCheckpointKeysAndRestoreParsing() {
        let a = SyncOperation.updateSpotifyPlaylistMembers(playlistID: CanonicalPlaylistID(value: "x:y"), trackIDs: [CanonicalTrackID(value: "1")])
        let b = SyncOperation.updateSpotifyPlaylistMembers(playlistID: CanonicalPlaylistID(value: "x:y"), trackIDs: [CanonicalTrackID(value: "2")])
        XCTAssertNotEqual(a.checkpointKey, b.checkpointKey, "different target members, different key")
        XCTAssertEqual(a.checkpointKey, a.checkpointKey)

        guard case .updateSpotifyPlaylistMembers(let id, let tracks)? =
            EnhancedSyncExecutor.restoreOperation(for: a.checkpointKey, previous: ["9"]) else {
            return XCTFail("could not parse key")
        }
        XCTAssertEqual(id.value, "x:y")
        XCTAssertEqual(tracks.map(\.value), ["9"])
        XCTAssertNil(EnhancedSyncExecutor.restoreOperation(for: "addTrackToApple:t1", previous: []))
    }

    func testStatusLineForEachPhase() {
        XCTAssertEqual(SyncProgress(runID: "r", phase: .tracks, completed: 5, total: 10).statusLine,
                       "Library tracks · 5 of 10 operations")
        XCTAssertEqual(SyncProgress(runID: "r", phase: .cancelled, completed: 5, total: 10).statusLine,
                       "Sync cancelled · 5 of 10 operations. Resume to continue.")
        XCTAssertEqual(SyncProgress(runID: "r", phase: .finished, completed: 10, total: 10, failed: 2).statusLine,
                       "Sync finished with 2 failed · 10 of 10 operations")
        XCTAssertEqual(SyncProgress(runID: "r", phase: .tracks, completed: 0, total: 0).fraction, 0)
    }
}
