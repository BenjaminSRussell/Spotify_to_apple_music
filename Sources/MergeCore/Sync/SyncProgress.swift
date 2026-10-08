import Foundation

/// Snapshot of a running sync, emitted after every operation (#12).
public struct SyncProgress: Sendable, Equatable {
    public enum Phase: String, Sendable {
        case tracks
        case playlists
        case finished
        case cancelled
    }

    public var runID: String
    public var phase: Phase
    /// Operations handled so far, including ones skipped because a checkpoint showed them done.
    public var completed: Int
    public var total: Int
    public var failed: Int
    public var skipped: Int
    /// Playlist currently being applied (playlist phase only).
    public var playlistName: String?
    /// 1-based index of the current playlist and the number of playlists in this run.
    public var playlistIndex: Int
    public var playlistCount: Int
    /// Set when VoiceOver should announce something (new playlist, finish, cancel).
    public var announcement: String?

    public init(
        runID: String,
        phase: Phase,
        completed: Int,
        total: Int,
        failed: Int = 0,
        skipped: Int = 0,
        playlistName: String? = nil,
        playlistIndex: Int = 0,
        playlistCount: Int = 0,
        announcement: String? = nil
    ) {
        self.runID = runID
        self.phase = phase
        self.completed = completed
        self.total = total
        self.failed = failed
        self.skipped = skipped
        self.playlistName = playlistName
        self.playlistIndex = playlistIndex
        self.playlistCount = playlistCount
        self.announcement = announcement
    }

    public var fraction: Double {
        guard total > 0 else { return phase == .finished ? 1 : 0 }
        return min(1, Double(completed) / Double(total))
    }

    /// One-line status, e.g. "Playlist 3 of 12: Road Trip · 140 of 900 operations".
    public var statusLine: String {
        let counts = "\(completed) of \(total) operations"
        switch phase {
        case .tracks:
            return "Library tracks · \(counts)"
        case .playlists:
            let name = playlistName ?? "Untitled playlist"
            return "Playlist \(playlistIndex) of \(playlistCount): \(name) · \(counts)"
        case .finished:
            return failed == 0 ? "Sync finished · \(counts)" : "Sync finished with \(failed) failed · \(counts)"
        case .cancelled:
            return "Sync cancelled · \(counts). Resume to continue."
        }
    }
}

public typealias SyncProgressHandler = @Sendable (SyncProgress) -> Void
