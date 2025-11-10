import Foundation

// MARK: - Sync Operations

/// Individual sync operation to apply
public enum SyncOperation: Sendable {
    case addTrackToApple(canonicalTrackID: CanonicalTrackID)
    case addTrackToSpotify(canonicalTrackID: CanonicalTrackID)
    case removeTrackFromApple(canonicalTrackID: CanonicalTrackID)
    case removeTrackFromSpotify(canonicalTrackID: CanonicalTrackID)

    case createApplePlaylist(playlist: CanonicalPlaylist)
    case createSpotifyPlaylist(playlist: CanonicalPlaylist)
    case updateApplePlaylistMembers(playlistID: CanonicalPlaylistID, trackIDs: [CanonicalTrackID])
    case updateSpotifyPlaylistMembers(playlistID: CanonicalPlaylistID, trackIDs: [CanonicalTrackID])
}

// MARK: - Library Diff

/// Result of comparing two library states
public struct LibraryDiff: Sendable {
    public let trackOps: [SyncOperation]
    public let playlistOps: [SyncOperation]

    public init(trackOps: [SyncOperation], playlistOps: [SyncOperation]) {
        self.trackOps = trackOps
        self.playlistOps = playlistOps
    }

    /// Total number of operations
    public var totalOperations: Int {
        trackOps.count + playlistOps.count
    }
}

// MARK: - Sync Result

/// Result of executing sync operations
public struct SyncResult: Sendable {
    public let totalOps: Int
    public let successCount: Int
    public let failureCount: Int
    public let duration: TimeInterval
    public let errors: [SyncError]

    public init(
        totalOps: Int,
        successCount: Int,
        failureCount: Int,
        duration: TimeInterval,
        errors: [SyncError] = []
    ) {
        self.totalOps = totalOps
        self.successCount = successCount
        self.failureCount = failureCount
        self.duration = duration
        self.errors = errors
    }

    /// Success rate as percentage
    public var successRate: Double {
        guard totalOps > 0 else { return 0 }
        return Double(successCount) / Double(totalOps)
    }
}

/// Error that occurred during sync
public struct SyncError: Sendable {
    public let operation: String
    public let error: String
    public let timestamp: Date

    public init(operation: String, error: String, timestamp: Date = Date()) {
        self.operation = operation
        self.error = error
        self.timestamp = timestamp
    }
}

// MARK: - Dry Run Report

/// Report from a dry-run (no actual changes)
public struct DryRunReport: Sendable {
    public let trackCount: Int
    public let playlistCount: Int
    public let totalOperations: Int
    public let direction: MergeDirection

    public init(
        trackCount: Int,
        playlistCount: Int,
        totalOperations: Int,
        direction: MergeDirection
    ) {
        self.trackCount = trackCount
        self.playlistCount = playlistCount
        self.totalOperations = totalOperations
        self.direction = direction
    }

    public func asTextSummary() -> String {
        """
        📊 Dry Run Report
        ─────────────────
        Direction: \(direction)
        Tracks to sync: \(trackCount)
        Playlists to sync: \(playlistCount)
        Total operations: \(totalOperations)

        ✅ Ready to sync. Run without --dry-run to proceed.
        """
    }
}
