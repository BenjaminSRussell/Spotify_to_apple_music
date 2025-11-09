import Foundation

/// Main matching engine orchestrator
public final class MatchEngine: Sendable {
    private let policy: MergePolicy

    public init(policy: MergePolicy = .default) {
        self.policy = policy
    }

    /// Match a Spotify track to Apple Music
    public func matchSpotifyTrackToApple(_ source: CanonicalTrack) async throws -> MatchDecision {
        // TODO: Implement 6-stage matching pipeline
        // Stage 0: Check existing mappings
        // Stage 1: Strong match (ISRC)
        // Stage 2-4: Fuzzy matching
        // Stage 5: Decision logic
        return .noMatch
    }

    /// Match an Apple Music track to Spotify
    public func matchAppleTrackToSpotify(_ source: CanonicalTrack) async throws -> MatchDecision {
        // TODO: Implement matching pipeline
        return .noMatch
    }
}
