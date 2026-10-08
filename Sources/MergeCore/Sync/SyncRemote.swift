import Foundation

/// Applies one sync operation to a music service (#8).
///
/// `EnhancedSyncExecutor` routes every operation through a `SyncRemote`, wrapped in the
/// rate limiter and retry policy, so live API clients and test doubles share one code path.
public protocol SyncRemote: Sendable {
    /// Whether calls hit a network API and must go through the rate limiter.
    var isRateLimited: Bool { get }
    func apply(_ operation: SyncOperation) async throws
}

extension SyncRemote {
    public var isRateLimited: Bool { true }
}

/// Default remote: records the operation in the local canonical stores.
/// Live Spotify / Apple Music clients plug in here once their write APIs land.
public struct LocalStoreSyncRemote: SyncRemote {
    private let trackStore: TrackStore
    private let playlistStore: PlaylistStore

    public init(trackStore: TrackStore, playlistStore: PlaylistStore) {
        self.trackStore = trackStore
        self.playlistStore = playlistStore
    }

    /// Local writes need no throttling.
    public var isRateLimited: Bool { false }

    public func apply(_ operation: SyncOperation) async throws {
        switch operation {
        case .addTrackToApple(let id):
            try await updateAvailability(id) { $0.insert(.appleMusic) }
        case .addTrackToSpotify(let id):
            try await updateAvailability(id) { $0.insert(.spotify) }
        case .removeTrackFromApple(let id):
            try await updateAvailability(id) { $0.remove(.appleMusic) }
        case .removeTrackFromSpotify(let id):
            try await updateAvailability(id) { $0.remove(.spotify) }
        case .createApplePlaylist(let playlist), .createSpotifyPlaylist(let playlist):
            try await playlistStore.save(playlist)
        case .updateApplePlaylistMembers(let id, let trackIDs),
             .updateSpotifyPlaylistMembers(let id, let trackIDs):
            guard var playlist = try await playlistStore.fetch(id: id) else {
                throw SyncExecutorError.playlistNotFound(id.value)
            }
            playlist.trackIDs = trackIDs
            try await playlistStore.save(playlist)
        }
    }

    private func updateAvailability(
        _ id: CanonicalTrackID,
        _ change: (inout AvailabilityFlags) -> Void
    ) async throws {
        guard var track = try await trackStore.fetch(id: id) else {
            throw SyncExecutorError.trackNotFound(id.value)
        }
        change(&track.availability)
        try await trackStore.save(track)
    }
}

// MARK: - Operation identity

extension SyncOperation {
    /// Stable key used for checkpoints. Member updates include a digest of the target
    /// track list, so a resumed run re-applies a playlist whose desired contents changed.
    public var checkpointKey: String {
        switch self {
        case .addTrackToApple(let id): return "addTrackToApple:\(id.value)"
        case .addTrackToSpotify(let id): return "addTrackToSpotify:\(id.value)"
        case .removeTrackFromApple(let id): return "removeTrackFromApple:\(id.value)"
        case .removeTrackFromSpotify(let id): return "removeTrackFromSpotify:\(id.value)"
        case .createApplePlaylist(let p): return "createApplePlaylist:\(p.id.value)"
        case .createSpotifyPlaylist(let p): return "createSpotifyPlaylist:\(p.id.value)"
        case .updateApplePlaylistMembers(let id, let tracks):
            return "updateApplePlaylistMembers:\(id.value):\(Self.digest(tracks))"
        case .updateSpotifyPlaylistMembers(let id, let tracks):
            return "updateSpotifyPlaylistMembers:\(id.value):\(Self.digest(tracks))"
        }
    }

    /// Playlist this operation targets, if any.
    public var playlistID: CanonicalPlaylistID? {
        switch self {
        case .createApplePlaylist(let p), .createSpotifyPlaylist(let p): return p.id
        case .updateApplePlaylistMembers(let id, _), .updateSpotifyPlaylistMembers(let id, _): return id
        default: return nil
        }
    }

    /// FNV-1a over the ordered track IDs (deterministic across launches, unlike `hashValue`).
    static func digest(_ tracks: [CanonicalTrackID]) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in tracks.map(\.value).joined(separator: "\u{1F}").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
