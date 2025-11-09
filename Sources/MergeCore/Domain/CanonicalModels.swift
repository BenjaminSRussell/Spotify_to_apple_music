import Foundation

// MARK: - Canonical Track Models

/// Stable identifier for a canonical track, derived from normalized metadata
public struct CanonicalTrackID: Hashable, Codable, Sendable {
    public let value: String

    public init(value: String) {
        self.value = value
    }
}

/// Service-agnostic representation of a music track
public struct CanonicalTrack: Codable, Sendable {
    public let id: CanonicalTrackID

    // Metadata
    public var title: String
    public var artist: String
    public var album: String?
    public var durationSeconds: Int?
    public var isExplicit: Bool?
    public var isrc: String?

    // Service mappings
    public var spotifyID: String?
    public var appleID: String?

    // Availability tracking
    public var availability: AvailabilityFlags

    public init(
        id: CanonicalTrackID,
        title: String,
        artist: String,
        album: String? = nil,
        durationSeconds: Int? = nil,
        isExplicit: Bool? = nil,
        isrc: String? = nil,
        spotifyID: String? = nil,
        appleID: String? = nil,
        availability: AvailabilityFlags = []
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.isExplicit = isExplicit
        self.isrc = isrc
        self.spotifyID = spotifyID
        self.appleID = appleID
        self.availability = availability
    }
}

/// Flags indicating which services have this track
public struct AvailabilityFlags: OptionSet, Codable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let spotify    = AvailabilityFlags(rawValue: 1 << 0)
    public static let appleMusic = AvailabilityFlags(rawValue: 1 << 1)
}

// MARK: - Canonical Playlist Models

/// Stable identifier for a canonical playlist
public struct CanonicalPlaylistID: Hashable, Codable, Sendable {
    public let value: String

    public init(value: String) {
        self.value = value
    }
}

/// Service-agnostic representation of a playlist
public struct CanonicalPlaylist: Codable, Sendable {
    public let id: CanonicalPlaylistID

    // Metadata
    public var name: String
    public var owner: String?
    public var description: String?

    // Contents (ordered)
    public var trackIDs: [CanonicalTrackID]

    // Service mappings
    public var sourceSpotifyID: String?
    public var sourceAppleID: String?

    public init(
        id: CanonicalPlaylistID,
        name: String,
        owner: String? = nil,
        description: String? = nil,
        trackIDs: [CanonicalTrackID] = [],
        sourceSpotifyID: String? = nil,
        sourceAppleID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.owner = owner
        self.description = description
        self.trackIDs = trackIDs
        self.sourceSpotifyID = sourceSpotifyID
        self.sourceAppleID = sourceAppleID
    }
}
