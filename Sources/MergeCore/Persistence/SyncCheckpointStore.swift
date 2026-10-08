import Foundation
import GRDB

/// One applied (or failed) operation within a sync run (#8, #12).
public struct SyncCheckpoint: Sendable, Equatable {
    public enum Status: String, Sendable {
        case done
        case failed
    }

    public let runID: String
    public let key: String
    public let status: Status
    /// Playlist membership before a member update was applied (rollback metadata).
    public let previousTrackIDs: [String]?
    public let error: String?
}

/// Persists which operations of a run already happened, so a cancelled or failed run
/// can resume without repeating API calls and playlist edits can be rolled back.
public protocol SyncCheckpointStore: Sendable {
    func completedKeys(runID: String) async throws -> Set<String>
    func markDone(runID: String, key: String, previousTrackIDs: [String]?) async throws
    func markFailed(runID: String, key: String, error: String) async throws
    func checkpoints(runID: String) async throws -> [SyncCheckpoint]
}

public final class SyncCheckpointStoreImpl: SyncCheckpointStore {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue = DatabaseProvider.shared.dbQueue) {
        self.dbQueue = dbQueue
    }

    public func completedKeys(runID: String) async throws -> Set<String> {
        try await dbQueue.read { db in
            Set(try String.fetchAll(
                db,
                sql: "SELECT op_key FROM sync_checkpoints WHERE run_id = ? AND status = 'done'",
                arguments: [runID]
            ))
        }
    }

    public func markDone(runID: String, key: String, previousTrackIDs: [String]?) async throws {
        let previous = try previousTrackIDs.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }
        try await upsert(runID: runID, key: key, status: .done, previous: previous, error: nil)
    }

    public func markFailed(runID: String, key: String, error: String) async throws {
        try await upsert(runID: runID, key: key, status: .failed, previous: nil, error: error)
    }

    public func checkpoints(runID: String) async throws -> [SyncCheckpoint] {
        try await dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT op_key, status, previous_track_ids, error FROM sync_checkpoints
                    WHERE run_id = ? ORDER BY updated_at, rowid
                    """,
                arguments: [runID]
            ).map { row in
                let previousJSON: String? = row["previous_track_ids"]
                let previous = previousJSON.flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) }
                return SyncCheckpoint(
                    runID: runID,
                    key: row["op_key"],
                    status: SyncCheckpoint.Status(rawValue: row["status"]) ?? .failed,
                    previousTrackIDs: previous,
                    error: row["error"]
                )
            }
        }
    }

    private func upsert(runID: String, key: String, status: SyncCheckpoint.Status, previous: String?, error: String?) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO sync_checkpoints (run_id, op_key, status, previous_track_ids, error, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(run_id, op_key) DO UPDATE SET
                        status = excluded.status,
                        previous_track_ids = COALESCE(excluded.previous_track_ids, sync_checkpoints.previous_track_ids),
                        error = excluded.error,
                        updated_at = excluded.updated_at
                    """,
                arguments: [runID, key, status.rawValue, previous, error, Date()]
            )
        }
    }
}

/// Non-persistent store for tests and previews.
public actor InMemorySyncCheckpointStore: SyncCheckpointStore {
    private var rows: [String: [SyncCheckpoint]] = [:]

    public init() {}

    public func completedKeys(runID: String) -> Set<String> {
        Set((rows[runID] ?? []).filter { $0.status == .done }.map(\.key))
    }

    public func markDone(runID: String, key: String, previousTrackIDs: [String]?) {
        replace(SyncCheckpoint(runID: runID, key: key, status: .done, previousTrackIDs: previousTrackIDs, error: nil))
    }

    public func markFailed(runID: String, key: String, error: String) {
        replace(SyncCheckpoint(runID: runID, key: key, status: .failed, previousTrackIDs: nil, error: error))
    }

    public func checkpoints(runID: String) -> [SyncCheckpoint] {
        rows[runID] ?? []
    }

    private func replace(_ checkpoint: SyncCheckpoint) {
        var list = rows[checkpoint.runID] ?? []
        list.removeAll { $0.key == checkpoint.key }
        list.append(checkpoint)
        rows[checkpoint.runID] = list
    }
}
