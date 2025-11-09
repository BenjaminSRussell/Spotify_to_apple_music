import Foundation

/// Protocol for Apple Music authentication
public protocol AppleAuthService: Sendable {
    func requestAuthorization() async throws
    var isAuthorized: Bool { get async }
}

/// Default implementation (stub)
public final class AppleAuthServiceImpl: AppleAuthService {
    public init() {}

    public func requestAuthorization() async throws {
        // TODO: Implement MusicKit authorization
    }

    public var isAuthorized: Bool {
        get async {
            // TODO: Check MusicKit authorization status
            return false
        }
    }
}
