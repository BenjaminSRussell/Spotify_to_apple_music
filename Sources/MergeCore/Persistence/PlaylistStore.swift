import Foundation
import GRDB

/// Protocol for playlist persistence operations
public protocol PlaylistStore: Sendable {
    func save(_ playlist: CanonicalPlaylist) async throws
    func saveAll(_ playlists: [CanonicalPlaylist]) async throws
    func fetch(id: CanonicalPlaylistID) async throws -> CanonicalPlaylist?
    func fetchAll() async throws -> [CanonicalPlaylist]
    func delete(id: CanonicalPlaylistID) async throws
}

/// GRDB-based playlist store implementation
public final class PlaylistStoreImpl: PlaylistStore {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue = DatabaseProvider.shared.dbQueue) {
        self.dbQueue = dbQueue
    }

    public func save(_ playlist: CanonicalPlaylist) async throws {
        try await dbQueue.write { db in
            // Save playlist metadata
            try playlist.save(db)

            // Delete existing track associations
            try db.execute(
                sql: "DELETE FROM playlist_tracks WHERE playlist_id = ?",
                arguments: [playlist.id.value]
            )

            // Insert track associations with positions
            for (index, trackID) in playlist.trackIDs.enumerated() {
                try db.execute(
                    sql: "INSERT INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)",
                    arguments: [playlist.id.value, trackID.value, index]
                )
            }
        }
    }

    public func saveAll(_ playlists: [CanonicalPlaylist]) async throws {
        for playlist in playlists {
            try await save(playlist)
        }
    }

    public func fetch(id: CanonicalPlaylistID) async throws -> CanonicalPlaylist? {
        try await dbQueue.read { db in
            // Fetch playlist metadata
            guard var playlist = try CanonicalPlaylist
                .filter(Column("id") == id.value)
                .fetchOne(db) else {
                return nil
            }

            // Fetch track IDs in order
            let trackIDs = try Row
                .fetchAll(
                    db,
                    sql: "SELECT track_id FROM playlist_tracks WHERE playlist_id = ? ORDER BY position",
                    arguments: [id.value]
                )
                .map { CanonicalTrackID(value: $0["track_id"]) }

            playlist.trackIDs = trackIDs
            return playlist
        }
    }

    public func fetchAll() async throws -> [CanonicalPlaylist] {
        try await dbQueue.read { db in
            let playlists = try CanonicalPlaylist.fetchAll(db)

            // Load track IDs for each playlist
            return try playlists.map { playlist in
                var mutablePlaylist = playlist
                let trackIDs = try Row
                    .fetchAll(
                        db,
                        sql: "SELECT track_id FROM playlist_tracks WHERE playlist_id = ? ORDER BY position",
                        arguments: [playlist.id.value]
                    )
                    .map { CanonicalTrackID(value: $0["track_id"]) }

                mutablePlaylist.trackIDs = trackIDs
                return mutablePlaylist
            }
        }
    }

    public func delete(id: CanonicalPlaylistID) async throws {
        try await dbQueue.write { db in
            // Delete playlist metadata (CASCADE will delete playlist_tracks)
            try CanonicalPlaylist
                .filter(Column("id") == id.value)
                .deleteAll(db)
        }
    }
}
