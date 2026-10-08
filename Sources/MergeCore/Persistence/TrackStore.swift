import Foundation
import GRDB

/// Protocol for track persistence operations
public protocol TrackStore: Sendable {
    func save(_ track: CanonicalTrack) async throws
    func saveAll(_ tracks: [CanonicalTrack]) async throws
    func fetch(id: CanonicalTrackID) async throws -> CanonicalTrack?
    func fetchBySpotifyID(_ id: String) async throws -> CanonicalTrack?
    func fetchByAppleID(_ id: String) async throws -> CanonicalTrack?
    func fetchByISRC(_ isrc: String) async throws -> CanonicalTrack?
    /// Indexed, case-insensitive ISRC lookup restricted to tracks available on `service` (#14)
    func fetchByISRC(_ isrc: String, availableOn service: MusicService) async throws -> CanonicalTrack?
    func fetchAll() async throws -> [CanonicalTrack]
    func delete(id: CanonicalTrackID) async throws
}

/// GRDB-based track store implementation
public final class TrackStoreImpl: TrackStore {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue = DatabaseProvider.shared.dbQueue) {
        self.dbQueue = dbQueue
    }

    public func save(_ track: CanonicalTrack) async throws {
        try await dbQueue.write { db in
            try Self.upsertMerge(track, db: db)
        }
    }

    public func saveAll(_ tracks: [CanonicalTrack]) async throws {
        try await dbQueue.write { db in
            for track in tracks {
                try Self.upsertMerge(track, db: db)
            }
        }
    }

    /// Look up by service id / ISRC / metadata id, then merge service fields (#13).
    private static func upsertMerge(_ incoming: CanonicalTrack, db: Database) throws {
        var existing: CanonicalTrack?
        if let sid = incoming.spotifyID,
           let row = try CanonicalTrack.filter(CanonicalTrack.Columns.spotifyID == sid).fetchOne(db) {
            existing = row
        } else if let aid = incoming.appleID,
                  let row = try CanonicalTrack.filter(CanonicalTrack.Columns.appleID == aid).fetchOne(db) {
            existing = row
        } else if let isrc = incoming.isrc, !isrc.isEmpty,
                  let row = try CanonicalTrack.filter(CanonicalTrack.Columns.isrc == isrc).fetchOne(db) {
            existing = row
        } else if let row = try CanonicalTrack.filter(Column("id") == incoming.id.value).fetchOne(db) {
            existing = row
        }

        guard var base = existing else {
            try incoming.save(db)
            return
        }

        // Keep stable primary key; merge service IDs and availability without nulling the other side.
        if let sid = incoming.spotifyID { base.spotifyID = sid }
        if let aid = incoming.appleID { base.appleID = aid }
        base.availability.formUnion(incoming.availability)
        if base.isrc == nil || base.isrc?.isEmpty == true { base.isrc = incoming.isrc }
        if base.isExplicit == nil { base.isExplicit = incoming.isExplicit }
        if (base.album == nil || base.album?.isEmpty == true), let album = incoming.album {
            base.album = album
        }
        if base.durationSeconds == nil { base.durationSeconds = incoming.durationSeconds }
        // Prefer non-empty titles/artists from incoming only if somehow empty (should not happen)
        if !incoming.title.isEmpty { base.title = incoming.title }
        if !incoming.artist.isEmpty { base.artist = incoming.artist }

        try base.save(db)
    }

    public func fetch(id: CanonicalTrackID) async throws -> CanonicalTrack? {
        try await dbQueue.read { db in
            try CanonicalTrack
                .filter(Column("id") == id.value)
                .fetchOne(db)
        }
    }

    public func fetchBySpotifyID(_ id: String) async throws -> CanonicalTrack? {
        try await dbQueue.read { db in
            try CanonicalTrack
                .filter(CanonicalTrack.Columns.spotifyID == id)
                .fetchOne(db)
        }
    }

    public func fetchByAppleID(_ id: String) async throws -> CanonicalTrack? {
        try await dbQueue.read { db in
            try CanonicalTrack
                .filter(CanonicalTrack.Columns.appleID == id)
                .fetchOne(db)
        }
    }

    public func fetchByISRC(_ isrc: String) async throws -> CanonicalTrack? {
        try await dbQueue.read { db in
            try CanonicalTrack
                .filter(CanonicalTrack.Columns.isrc == isrc)
                .fetchOne(db)
        }
    }

    /// Uses `idx_tracks_isrc_nocase` (migration v3); see `PersistenceTests.testISRCLookupUsesIndex`.
    static let isrcLookupSQL = """
        SELECT * FROM canonical_tracks
        WHERE isrc = ? COLLATE NOCASE AND (availability & ?) != 0
        LIMIT 1
        """

    public func fetchByISRC(_ isrc: String, availableOn service: MusicService) async throws -> CanonicalTrack? {
        guard !isrc.isEmpty else { return nil }
        let flag = AvailabilityFlags(service).rawValue
        return try await dbQueue.read { db in
            try CanonicalTrack.fetchOne(db, sql: Self.isrcLookupSQL, arguments: [isrc, flag])
        }
    }

    public func fetchAll() async throws -> [CanonicalTrack] {
        try await dbQueue.read { db in
            try CanonicalTrack.fetchAll(db)
        }
    }

    public func delete(id: CanonicalTrackID) async throws {
        try await dbQueue.write { db in
            try CanonicalTrack
                .filter(Column("id") == id.value)
                .deleteAll(db)
        }
    }
}
