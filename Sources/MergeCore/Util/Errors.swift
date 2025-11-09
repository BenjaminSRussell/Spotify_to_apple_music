import Foundation

/// Application-specific errors
public enum MergeError: Error, LocalizedError {
    case authRequired(service: MusicService)
    case authFailed(service: MusicService, reason: String)
    case rateLimited(service: MusicService, retryAfter: TimeInterval)
    case networkError(service: MusicService, underlying: Error)
    case trackNotFound(CanonicalTrackID)
    case playlistNotFound(CanonicalPlaylistID)
    case mappingConflict(trackID: CanonicalTrackID)
    case databaseError(underlying: Error)
    case invalidConfiguration(reason: String)

    public var errorDescription: String? {
        switch self {
        case .authRequired(let service):
            return "Authorization required for \(service.rawValue)"
        case .authFailed(let service, let reason):
            return "Authentication failed for \(service.rawValue): \(reason)"
        case .rateLimited(let service, let retryAfter):
            return "Rate limited by \(service.rawValue). Retry after \(retryAfter)s"
        case .networkError(let service, let underlying):
            return "Network error for \(service.rawValue): \(underlying.localizedDescription)"
        case .trackNotFound(let id):
            return "Track not found: \(id.value)"
        case .playlistNotFound(let id):
            return "Playlist not found: \(id.value)"
        case .mappingConflict(let trackID):
            return "Mapping conflict for track: \(trackID.value)"
        case .databaseError(let underlying):
            return "Database error: \(underlying.localizedDescription)"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        }
    }
}
