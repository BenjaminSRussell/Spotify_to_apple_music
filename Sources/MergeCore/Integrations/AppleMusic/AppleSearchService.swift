import Foundation

/// Protocol for Apple Music search operations
public protocol AppleSearchService: Sendable {
    func search(query: String, limit: Int) async throws -> [AppleTrackRef]
}

/// Default implementation (stub)
public final class AppleSearchServiceImpl: AppleSearchService {
    public init() {}

    public func search(query: String, limit: Int = 10) async throws -> [AppleTrackRef] {
        // TODO: Implement MusicKit search
        return []
    }
}
