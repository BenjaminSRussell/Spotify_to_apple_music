import Foundation

/// Protocol for track persistence operations
public protocol TrackStore: Sendable {
    func save(_ track: CanonicalTrack) async throws
    func saveAll(_ tracks: [CanonicalTrack]) async throws
    func fetch(id: CanonicalTrackID) async throws -> CanonicalTrack?
    func fetchBySpotifyID(_ id: String) async throws -> CanonicalTrack?
    func fetchByAppleID(_ id: String) async throws -> CanonicalTrack?
    func fetchAll() async throws -> [CanonicalTrack]
}

/// Default implementation (stub)
public final class TrackStoreImpl: TrackStore {
    public init() {}

    public func save(_ track: CanonicalTrack) async throws {
        // TODO: Implement database save
    }

    public func saveAll(_ tracks: [CanonicalTrack]) async throws {
        // TODO: Implement batch save
    }

    public func fetch(id: CanonicalTrackID) async throws -> CanonicalTrack? {
        // TODO: Implement database fetch
        return nil
    }

    public func fetchBySpotifyID(_ id: String) async throws -> CanonicalTrack? {
        // TODO: Implement database fetch by Spotify ID
        return nil
    }

    public func fetchByAppleID(_ id: String) async throws -> CanonicalTrack? {
        // TODO: Implement database fetch by Apple ID
        return nil
    }

    public func fetchAll() async throws -> [CanonicalTrack] {
        // TODO: Implement fetch all
        return []
    }
}
