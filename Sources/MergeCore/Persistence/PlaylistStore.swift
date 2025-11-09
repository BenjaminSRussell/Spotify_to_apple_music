import Foundation

/// Protocol for playlist persistence operations
public protocol PlaylistStore: Sendable {
    func save(_ playlist: CanonicalPlaylist) async throws
    func saveAll(_ playlists: [CanonicalPlaylist]) async throws
    func fetch(id: CanonicalPlaylistID) async throws -> CanonicalPlaylist?
    func fetchAll() async throws -> [CanonicalPlaylist]
}

/// Default implementation (stub)
public final class PlaylistStoreImpl: PlaylistStore {
    public init() {}

    public func save(_ playlist: CanonicalPlaylist) async throws {
        // TODO: Implement database save
    }

    public func saveAll(_ playlists: [CanonicalPlaylist]) async throws {
        // TODO: Implement batch save
    }

    public func fetch(id: CanonicalPlaylistID) async throws -> CanonicalPlaylist? {
        // TODO: Implement database fetch
        return nil
    }

    public func fetchAll() async throws -> [CanonicalPlaylist] {
        // TODO: Implement fetch all
        return []
    }
}
