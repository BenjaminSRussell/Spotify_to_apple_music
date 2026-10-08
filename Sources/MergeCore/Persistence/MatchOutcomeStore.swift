import Foundation
import GRDB

/// One matching decision, persisted for threshold tuning (#9)
public struct MatchOutcome: Codable, Equatable, Sendable {
    public var runID: String?
    public var recordedAt: Date
    public var sourceService: MusicService
    public var targetService: MusicService
    public var sourceTrackID: String
    /// "auto", "ambiguous" or "no_match"
    public var decision: String
    public var method: String?
    /// Best candidate's confidence (nil for no_match)
    public var topScore: Double?
    public var candidateCount: Int

    public init(
        runID: String?,
        recordedAt: Date = Date(),
        sourceService: MusicService,
        targetService: MusicService,
        sourceTrackID: String,
        decision: String,
        method: String?,
        topScore: Double?,
        candidateCount: Int
    ) {
        self.runID = runID
        self.recordedAt = recordedAt
        self.sourceService = sourceService
        self.targetService = targetService
        self.sourceTrackID = sourceTrackID
        self.decision = decision
        self.method = method
        self.topScore = topScore
        self.candidateCount = candidateCount
    }

    /// Build from a `MatchDecision`
    public init(decision: MatchDecision, source: CanonicalTrack, targetService: MusicService, runID: String?, at date: Date = Date()) {
        let sourceService: MusicService = targetService == .appleMusic ? .spotify : .appleMusic
        switch decision {
        case .auto(let m):
            self.init(runID: runID, recordedAt: date, sourceService: sourceService, targetService: targetService,
                      sourceTrackID: source.id.value, decision: "auto", method: m.method.rawValue,
                      topScore: m.score, candidateCount: 1)
        case .ambiguous(let cands):
            let best = cands.max { $0.score < $1.score }
            self.init(runID: runID, recordedAt: date, sourceService: sourceService, targetService: targetService,
                      sourceTrackID: source.id.value, decision: "ambiguous", method: best?.method.rawValue,
                      topScore: best?.score, candidateCount: cands.count)
        case .noMatch:
            self.init(runID: runID, recordedAt: date, sourceService: sourceService, targetService: targetService,
                      sourceTrackID: source.id.value, decision: "no_match", method: nil, topScore: nil, candidateCount: 0)
        case .skipped:
            self.init(runID: runID, recordedAt: date, sourceService: sourceService, targetService: targetService,
                      sourceTrackID: source.id.value, decision: "skipped", method: nil, topScore: nil, candidateCount: 0)
        }
    }
}

extension MatchOutcome: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "match_outcomes" }

    public init(row: Row) {
        self.runID = row["run_id"]
        self.recordedAt = row["recorded_at"]
        self.sourceService = MusicService(rawValue: row["source_service"]) ?? .spotify
        self.targetService = MusicService(rawValue: row["target_service"]) ?? .appleMusic
        self.sourceTrackID = row["source_track_id"]
        self.decision = row["decision"]
        self.method = row["method"]
        self.topScore = row["top_score"]
        self.candidateCount = row["candidate_count"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["run_id"] = runID
        container["recorded_at"] = recordedAt
        container["source_service"] = sourceService.rawValue
        container["target_service"] = targetService.rawValue
        container["source_track_id"] = sourceTrackID
        container["decision"] = decision
        container["method"] = method
        container["top_score"] = topScore
        container["candidate_count"] = candidateCount
    }
}

public protocol MatchOutcomeStore: Sendable {
    func record(_ outcomes: [MatchOutcome]) async throws
    func fetchAll() async throws -> [MatchOutcome]
}

public final class MatchOutcomeStoreImpl: MatchOutcomeStore {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue = DatabaseProvider.shared.dbQueue) {
        self.dbQueue = dbQueue
    }

    public func record(_ outcomes: [MatchOutcome]) async throws {
        guard !outcomes.isEmpty else { return }
        try await dbQueue.write { db in
            for outcome in outcomes { try outcome.insert(db) }
        }
    }

    public func fetchAll() async throws -> [MatchOutcome] {
        try await dbQueue.read { db in
            try MatchOutcome.order(Column("recorded_at")).fetchAll(db)
        }
    }
}
