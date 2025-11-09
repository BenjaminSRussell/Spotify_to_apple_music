import Foundation

/// Protocol for Spotify library operations
public protocol SpotifyLibraryService: Sendable {
    func fetchSavedTracks() async throws -> [SpotifyTrackRef]
    func fetchPlaylists() async throws -> [SpotifyPlaylistRef]
    func fetchPlaylistTracks(playlistID: String) async throws -> [SpotifyTrackRef]
}

/// Default implementation (stub)
public final class SpotifyLibraryServiceImpl: SpotifyLibraryService {
    public init() {}

    public func fetchSavedTracks() async throws -> [SpotifyTrackRef] {
        // TODO: Implement Spotify API call
        return []
    }

    public func fetchPlaylists() async throws -> [SpotifyPlaylistRef] {
        // TODO: Implement Spotify API call
        return []
    }

    public func fetchPlaylistTracks(playlistID: String) async throws -> [SpotifyTrackRef] {
        // TODO: Implement Spotify API call
        return []
    }
}
