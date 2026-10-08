import Foundation
import GRDB

/// Last membership applied to each playlist on each service (#8 incremental sync).
///
/// Acts like an ETag: when the source playlist's member digest matches what was last
/// written to the target, the diff drops the create/update and the second sync of an
/// unchanged library performs no playlist writes.
public protocol PlaylistSyncStateStore: Sendable {
    func lastAppliedDigest(service: MusicService, playlistID: CanonicalPlaylistID) async throws -> String?
    func recordApplied(service: MusicService, playlistID: CanonicalPlaylistID, digest: String) async throws
}

public final class PlaylistSyncStateStoreImpl: PlaylistSyncStateStore {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue = DatabaseProvider.shared.dbQueue) {
        self.dbQueue = dbQueue
    }

    public func lastAppliedDigest(service: MusicService, playlistID: CanonicalPlaylistID) async throws -> String? {
        try await dbQueue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT members_digest FROM playlist_sync_state WHERE service = ? AND playlist_id = ?",
                arguments: [service.rawValue, playlistID.value]
            )
        }
    }

    public func recordApplied(service: MusicService, playlistID: CanonicalPlaylistID, digest: String) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO playlist_sync_state (service, playlist_id, members_digest, synced_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(service, playlist_id) DO UPDATE SET
                        members_digest = excluded.members_digest, synced_at = excluded.synced_at
                    """,
                arguments: [service.rawValue, playlistID.value, digest, Date()]
            )
        }
    }
}

public actor InMemoryPlaylistSyncStateStore: PlaylistSyncStateStore {
    private var digests: [String: String] = [:]

    public init() {}

    public func lastAppliedDigest(service: MusicService, playlistID: CanonicalPlaylistID) -> String? {
        digests["\(service.rawValue)|\(playlistID.value)"]
    }

    public func recordApplied(service: MusicService, playlistID: CanonicalPlaylistID, digest: String) {
        digests["\(service.rawValue)|\(playlistID.value)"] = digest
    }
}

// MARK: - Playlist operation helpers

extension SyncOperation {
    /// Target service and desired members for playlist operations.
    var playlistTarget: (service: MusicService, id: CanonicalPlaylistID, members: [CanonicalTrackID])? {
        switch self {
        case .createApplePlaylist(let p): return (.appleMusic, p.id, p.trackIDs)
        case .createSpotifyPlaylist(let p): return (.spotify, p.id, p.trackIDs)
        case .updateApplePlaylistMembers(let id, let tracks): return (.appleMusic, id, tracks)
        case .updateSpotifyPlaylistMembers(let id, let tracks): return (.spotify, id, tracks)
        default: return nil
        }
    }
}

extension LibraryDiff {
    /// Drop playlist operations whose members already match what was last applied to the
    /// target; turn creates for playlists that were already created into member updates.
    public func incremental(using store: PlaylistSyncStateStore) async throws -> LibraryDiff {
        var kept: [SyncOperation] = []
        for operation in playlistOps {
            guard let target = operation.playlistTarget,
                  let applied = try await store.lastAppliedDigest(service: target.service, playlistID: target.id) else {
                kept.append(operation)
                continue
            }
            if applied == SyncOperation.digest(target.members) { continue }
            switch operation {
            case .createApplePlaylist(let p):
                kept.append(.updateApplePlaylistMembers(playlistID: p.id, trackIDs: p.trackIDs))
            case .createSpotifyPlaylist(let p):
                kept.append(.updateSpotifyPlaylistMembers(playlistID: p.id, trackIDs: p.trackIDs))
            default:
                kept.append(operation)
            }
        }
        return LibraryDiff(trackOps: trackOps, playlistOps: kept)
    }
}
