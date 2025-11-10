import Foundation
import GRDB

// MARK: - Normalized Keys

/// Normalized track metadata for matching
public struct NormalizedTrackKey: Hashable, Sendable {
    public let titleKey: String
    public let artistKey: String
    public let albumKey: String?

    public init(titleKey: String, artistKey: String, albumKey: String? = nil) {
        self.titleKey = titleKey
        self.artistKey = artistKey
        self.albumKey = albumKey
    }
}

// MARK: - Match Scoring

/// Individual component scores for a match
public struct MatchScoreComponents: Sendable {
    public let titleScore: Double       // 0.0-1.0
    public let artistScore: Double      // 0.0-1.0
    public let albumScore: Double       // 0.0-1.0
    public let durationScore: Double    // 0.0-1.0
    public let isrcBonus: Double        // 0.0 or 0.2

    public init(
        titleScore: Double,
        artistScore: Double,
        albumScore: Double,
        durationScore: Double,
        isrcBonus: Double
    ) {
        self.titleScore = titleScore
        self.artistScore = artistScore
        self.albumScore = albumScore
        self.durationScore = durationScore
        self.isrcBonus = isrcBonus
    }

    /// Human-readable breakdown for debugging
    public var breakdown: String {
        """
        Title: \(String(format: "%.2f", titleScore))
        Artist: \(String(format: "%.2f", artistScore))
        Album: \(String(format: "%.2f", albumScore))
        Duration: \(String(format: "%.2f", durationScore))
        ISRC Bonus: \(String(format: "%.2f", isrcBonus))
        """
    }
}

/// Complete match score for a candidate track
public struct MatchScore: Sendable {
    public let candidateID: String
    public let score: Double              // Combined score 0.0-1.0
    public let components: MatchScoreComponents
    public let method: MatchMethod

    public init(
        candidateID: String,
        score: Double,
        components: MatchScoreComponents,
        method: MatchMethod
    ) {
        self.candidateID = candidateID
        self.score = score
        self.components = components
        self.method = method
    }

    /// Whether this score qualifies as an auto-match
    public var isAutoMatch: Bool {
        score >= 0.85
    }

    /// Whether this score is in the ambiguous range
    public var isAmbiguous: Bool {
        score >= 0.65 && score < 0.85
    }
}

/// Method used to determine a match
public enum MatchMethod: String, Codable, Sendable {
    case isrc           // ISRC-based match
    case exactMetadata  // Exact metadata match
    case fuzzy          // Fuzzy string matching
    case manual         // User-selected manual match
    case fingerprint    // Audio fingerprint match
}

// MARK: - Match Decision

/// Decision result from matching engine
public enum MatchDecision: Sendable {
    case auto(candidate: MatchScore)
    case ambiguous(candidates: [MatchScore])
    case noMatch
}

// MARK: - Manual Mapping

/// User-provided manual track mapping
public struct ManualMapping: Codable, Sendable {
    public let id: String
    public let canonicalTrackID: CanonicalTrackID
    public let sourceService: MusicService
    public let sourceTrackID: String
    public let targetService: MusicService
    public let targetTrackID: String
    public let confidenceScore: Double?
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        canonicalTrackID: CanonicalTrackID,
        sourceService: MusicService,
        sourceTrackID: String,
        targetService: MusicService,
        targetTrackID: String,
        confidenceScore: Double? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.canonicalTrackID = canonicalTrackID
        self.sourceService = sourceService
        self.sourceTrackID = sourceTrackID
        self.targetService = targetService
        self.targetTrackID = targetTrackID
        self.confidenceScore = confidenceScore
        self.createdAt = createdAt
    }
}

// MARK: - GRDB Conformance

extension ManualMapping: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "manual_mappings" }

    public enum Columns {
        static let id = Column("id")
        static let canonicalTrackID = Column("canonical_track_id")
        static let sourceService = Column("source_service")
        static let sourceTrackID = Column("source_track_id")
        static let targetService = Column("target_service")
        static let targetTrackID = Column("target_track_id")
        static let confidenceScore = Column("confidence_score")
        static let createdAt = Column("created_at")
    }

    public init(row: Row) {
        self.id = row[Columns.id]
        self.canonicalTrackID = CanonicalTrackID(value: row[Columns.canonicalTrackID])
        self.sourceService = MusicService(rawValue: row[Columns.sourceService])!
        self.sourceTrackID = row[Columns.sourceTrackID]
        self.targetService = MusicService(rawValue: row[Columns.targetService])!
        self.targetTrackID = row[Columns.targetTrackID]
        self.confidenceScore = row[Columns.confidenceScore]
        self.createdAt = row[Columns.createdAt]
    }

    public func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.canonicalTrackID] = canonicalTrackID.value
        container[Columns.sourceService] = sourceService.rawValue
        container[Columns.sourceTrackID] = sourceTrackID
        container[Columns.targetService] = targetService.rawValue
        container[Columns.targetTrackID] = targetTrackID
        container[Columns.confidenceScore] = confidenceScore
        container[Columns.createdAt] = createdAt
    }
}
