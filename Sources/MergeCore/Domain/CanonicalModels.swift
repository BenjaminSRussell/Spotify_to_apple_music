import Foundation
import GRDB

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

// MARK: - GRDB Conformance

extension CanonicalTrack: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "canonical_tracks" }

    public enum Columns {
        static let id = Column("id")
        static let title = Column("title")
        static let artist = Column("artist")
        static let album = Column("album")
        static let durationSeconds = Column("duration_seconds")
        static let isExplicit = Column("is_explicit")
        static let isrc = Column("isrc")
        static let spotifyID = Column("spotify_id")
        static let appleID = Column("apple_id")
        static let availability = Column("availability")
    }

    public init(row: Row) {
        self.id = CanonicalTrackID(value: row[Columns.id])
        self.title = row[Columns.title]
        self.artist = row[Columns.artist]
        self.album = row[Columns.album]
        self.durationSeconds = row[Columns.durationSeconds]
        self.isExplicit = row[Columns.isExplicit]
        self.isrc = row[Columns.isrc]
        self.spotifyID = row[Columns.spotifyID]
        self.appleID = row[Columns.appleID]
        self.availability = AvailabilityFlags(rawValue: row[Columns.availability])
    }

    public func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id.value
        container[Columns.title] = title
        container[Columns.artist] = artist
        container[Columns.album] = album
        container[Columns.durationSeconds] = durationSeconds
        container[Columns.isExplicit] = isExplicit
        container[Columns.isrc] = isrc
        container[Columns.spotifyID] = spotifyID
        container[Columns.appleID] = appleID
        container[Columns.availability] = availability.rawValue
    }
}

extension CanonicalPlaylist: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "canonical_playlists" }

    public enum Columns {
        static let id = Column("id")
        static let name = Column("name")
        static let owner = Column("owner")
        static let description = Column("description")
        static let sourceSpotifyID = Column("source_spotify_id")
        static let sourceAppleID = Column("source_apple_id")
    }

    public init(row: Row) {
        self.id = CanonicalPlaylistID(value: row[Columns.id])
        self.name = row[Columns.name]
        self.owner = row[Columns.owner]
        self.description = row[Columns.description]
        self.trackIDs = []  // Will be loaded separately from playlist_tracks table
        self.sourceSpotifyID = row[Columns.sourceSpotifyID]
        self.sourceAppleID = row[Columns.sourceAppleID]
    }

    public func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id.value
        container[Columns.name] = name
        container[Columns.owner] = owner
        container[Columns.description] = description
        container[Columns.sourceSpotifyID] = sourceSpotifyID
        container[Columns.sourceAppleID] = sourceAppleID
        // trackIDs are stored separately in playlist_tracks table
    }
}
