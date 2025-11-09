import Foundation

// MARK: - Merge Direction

/// Direction of sync operation
public enum MergeDirection: String, Codable, Sendable {
    case spotifyToApple      // One-way: Spotify → Apple Music
    case appleToSpotify      // One-way: Apple Music → Spotify
    case bidirectional       // Two-way: sync both directions
}

// MARK: - Merge Policy

/// User-configurable sync policy
public struct MergePolicy: Sendable {
    public let direction: MergeDirection
    public let preferExplicit: Bool
    public let autoResolveThreshold: Double   // Default: 0.85
    public let ambiguousThreshold: Double     // Default: 0.65

    public init(
        direction: MergeDirection,
        preferExplicit: Bool = false,
        autoResolveThreshold: Double = 0.85,
        ambiguousThreshold: Double = 0.65
    ) {
        self.direction = direction
        self.preferExplicit = preferExplicit
        self.autoResolveThreshold = autoResolveThreshold
        self.ambiguousThreshold = ambiguousThreshold
    }

    /// Default policy: Spotify → Apple Music, moderate thresholds
    public static let `default` = MergePolicy(
        direction: .spotifyToApple,
        preferExplicit: false,
        autoResolveThreshold: 0.85,
        ambiguousThreshold: 0.65
    )
}

// MARK: - Match Thresholds

/// Configurable thresholds for match classification
public struct MatchThresholds: Sendable {
    public let autoMatchMinScore: Double
    public let autoMatchMinMargin: Double
    public let ambiguousMinScore: Double

    public init(
        autoMatchMinScore: Double = 0.85,
        autoMatchMinMargin: Double = 0.10,
        ambiguousMinScore: Double = 0.65
    ) {
        self.autoMatchMinScore = autoMatchMinScore
        self.autoMatchMinMargin = autoMatchMinMargin
        self.ambiguousMinScore = ambiguousMinScore
    }

    /// Default thresholds
    public static let `default` = MatchThresholds()
}
