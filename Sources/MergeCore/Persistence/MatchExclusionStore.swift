import Foundation
import GRDB

/// User decisions that remove tracks or candidates from matching (#7, #10).
///
/// - **skip**: never match or add this source track on the target service.
/// - **reject** (blacklist): never offer this specific candidate for this source track again.
public struct MatchExclusions: Sendable, Equatable {
    public var skipped: Bool
    public var rejectedCandidateIDs: Set<String>

    public init(skipped: Bool = false, rejectedCandidateIDs: Set<String> = []) {
        self.skipped = skipped
        self.rejectedCandidateIDs = rejectedCandidateIDs
    }
}

public protocol MatchExclusionStore: Sendable {
    func exclusions(for source: CanonicalTrackID, targetService: MusicService) async throws -> MatchExclusions
    func skip(_ source: CanonicalTrackID, targetService: MusicService) async throws
    func reject(candidateID: String, for source: CanonicalTrackID, targetService: MusicService) async throws
    /// Remove every skip/reject for the source on the target (undo).
    func clear(_ source: CanonicalTrackID, targetService: MusicService) async throws
}

public final class MatchExclusionStoreImpl: MatchExclusionStore {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue = DatabaseProvider.shared.dbQueue) {
        self.dbQueue = dbQueue
    }

    public func exclusions(for source: CanonicalTrackID, targetService: MusicService) async throws -> MatchExclusions {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT kind, candidate_id FROM match_exclusions WHERE canonical_track_id = ? AND target_service = ?",
                arguments: [source.value, targetService.rawValue]
            )
            var result = MatchExclusions()
            for row in rows {
                let kind: String = row["kind"]
                if kind == "skip" {
                    result.skipped = true
                } else {
                    result.rejectedCandidateIDs.insert(row["candidate_id"])
                }
            }
            return result
        }
    }

    public func skip(_ source: CanonicalTrackID, targetService: MusicService) async throws {
        try await insert(source: source, targetService: targetService, kind: "skip", candidateID: "")
    }

    public func reject(candidateID: String, for source: CanonicalTrackID, targetService: MusicService) async throws {
        try await insert(source: source, targetService: targetService, kind: "reject", candidateID: candidateID)
    }

    public func clear(_ source: CanonicalTrackID, targetService: MusicService) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM match_exclusions WHERE canonical_track_id = ? AND target_service = ?",
                arguments: [source.value, targetService.rawValue]
            )
        }
    }

    private func insert(source: CanonicalTrackID, targetService: MusicService, kind: String, candidateID: String) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO match_exclusions (canonical_track_id, target_service, kind, candidate_id, created_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [source.value, targetService.rawValue, kind, candidateID, Date()]
            )
        }
    }
}

public actor InMemoryMatchExclusionStore: MatchExclusionStore {
    private var entries: [String: MatchExclusions] = [:]

    public init() {}

    private func key(_ source: CanonicalTrackID, _ target: MusicService) -> String { "\(source.value)|\(target.rawValue)" }

    public func exclusions(for source: CanonicalTrackID, targetService: MusicService) -> MatchExclusions {
        entries[key(source, targetService)] ?? MatchExclusions()
    }

    public func skip(_ source: CanonicalTrackID, targetService: MusicService) {
        entries[key(source, targetService), default: MatchExclusions()].skipped = true
    }

    public func reject(candidateID: String, for source: CanonicalTrackID, targetService: MusicService) {
        entries[key(source, targetService), default: MatchExclusions()].rejectedCandidateIDs.insert(candidateID)
    }

    public func clear(_ source: CanonicalTrackID, targetService: MusicService) {
        entries[key(source, targetService)] = nil
    }
}
