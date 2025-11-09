import Foundation

/// Protocol for Apple Music library operations
public protocol AppleLibraryService: Sendable {
    func fetchLibrarySongs() async throws -> [AppleTrackRef]
    func fetchPlaylists() async throws -> [ApplePlaylistRef]
}

/// Default implementation (stub)
public final class AppleLibraryServiceImpl: AppleLibraryService {
    public init() {}

    public func fetchLibrarySongs() async throws -> [AppleTrackRef] {
        // TODO: Implement MusicKit library fetch
        return []
    }

    public func fetchPlaylists() async throws -> [ApplePlaylistRef] {
        // TODO: Implement MusicKit playlist fetch
        return []
    }
}
