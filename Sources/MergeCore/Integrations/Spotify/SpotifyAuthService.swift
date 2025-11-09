import Foundation

/// Protocol for Spotify authentication
public protocol SpotifyAuthService: Sendable {
    func authorize() async throws
    func refreshTokenIfNeeded() async throws
    var isAuthorized: Bool { get async }
}

/// Default implementation (stub)
public final class SpotifyAuthServiceImpl: SpotifyAuthService {
    public init() {}

    public func authorize() async throws {
        // TODO: Implement OAuth flow
    }

    public func refreshTokenIfNeeded() async throws {
        // TODO: Implement token refresh
    }

    public var isAuthorized: Bool {
        get async {
            // TODO: Check token validity
            return false
        }
    }
}
