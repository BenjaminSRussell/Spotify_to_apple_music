import Foundation

// MARK: - Music Service

/// Music streaming service identifier
public enum MusicService: String, Codable, Sendable {
    case spotify
    case appleMusic
}

// MARK: - Spotify Models

/// Raw reference to a Spotify track (before normalization)
public struct SpotifyTrackRef: Sendable {
    public let id: String
    public let name: String
    public let artistNames: [String]
    public let albumName: String?
    public let durationMs: Int?
    public let isExplicit: Bool?
    public let isrc: String?

    public init(
        id: String,
        name: String,
        artistNames: [String],
        albumName: String? = nil,
        durationMs: Int? = nil,
        isExplicit: Bool? = nil,
        isrc: String? = nil
    ) {
        self.id = id
        self.name = name
        self.artistNames = artistNames
        self.albumName = albumName
        self.durationMs = durationMs
        self.isExplicit = isExplicit
        self.isrc = isrc
    }
}

/// Raw reference to a Spotify playlist
public struct SpotifyPlaylistRef: Sendable {
    public let id: String
    public let name: String
    public let owner: String?
    public let description: String?
    public let trackRefs: [SpotifyTrackRef]

    public init(
        id: String,
        name: String,
        owner: String? = nil,
        description: String? = nil,
        trackRefs: [SpotifyTrackRef] = []
    ) {
        self.id = id
        self.name = name
        self.owner = owner
        self.description = description
        self.trackRefs = trackRefs
    }
}

// MARK: - Apple Music Models

/// Raw reference to an Apple Music track (before normalization)
public struct AppleTrackRef: Sendable {
    public let id: String
    public let name: String
    public let artistName: String
    public let albumName: String?
    public let durationMs: Int?
    public let isExplicit: Bool?
    public let isrc: String?

    public init(
        id: String,
        name: String,
        artistName: String,
        albumName: String? = nil,
        durationMs: Int? = nil,
        isExplicit: Bool? = nil,
        isrc: String? = nil
    ) {
        self.id = id
        self.name = name
        self.artistName = artistName
        self.albumName = albumName
        self.durationMs = durationMs
        self.isExplicit = isExplicit
        self.isrc = isrc
    }
}

/// Raw reference to an Apple Music playlist
public struct ApplePlaylistRef: Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let trackRefs: [AppleTrackRef]

    public init(
        id: String,
        name: String,
        description: String? = nil,
        trackRefs: [AppleTrackRef] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.trackRefs = trackRefs
    }
}
