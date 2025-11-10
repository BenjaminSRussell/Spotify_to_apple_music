import Foundation
import GRDB

/// Protocol for track persistence operations
public protocol TrackStore: Sendable {
    func save(_ track: CanonicalTrack) async throws
    func saveAll(_ tracks: [CanonicalTrack]) async throws
    func fetch(id: CanonicalTrackID) async throws -> CanonicalTrack?
    func fetchBySpotifyID(_ id: String) async throws -> CanonicalTrack?
    func fetchByAppleID(_ id: String) async throws -> CanonicalTrack?
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
            try track.save(db)
        }
    }

    public func saveAll(_ tracks: [CanonicalTrack]) async throws {
        try await dbQueue.write { db in
            for track in tracks {
                try track.save(db)
            }
        }
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
