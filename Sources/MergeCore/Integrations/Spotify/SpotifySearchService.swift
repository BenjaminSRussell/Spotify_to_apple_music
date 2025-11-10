import Foundation

/// Protocol for Spotify search operations
public protocol SpotifySearchService: Sendable {
    func search(query: String, limit: Int) async throws -> [SpotifyTrackRef]
}

/// Default implementation (stub)
public final class SpotifySearchServiceImpl: SpotifySearchService {
    public init() {}

    public func search(query: String, limit: Int = 10) async throws -> [SpotifyTrackRef] {
        // TODO: Implement Spotify search API
        return []
    }
}
