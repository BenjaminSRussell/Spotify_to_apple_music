import Foundation
import CryptoKit

/// Utilities for normalizing and converting service-specific models to canonical models
public struct Normalizer {

    // MARK: - Canonical ID Generation

    /// Generate a stable canonical track ID from normalized metadata
    public static func generateCanonicalTrackID(
        title: String,
        artist: String,
        album: String?,
        durationSeconds: Int?
    ) -> CanonicalTrackID {
        // Normalize inputs
        let normalizedTitle = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedArtist = artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAlbum = album?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Create stable string for hashing
        let hashInput = "\(normalizedArtist)|\(normalizedTitle)|\(normalizedAlbum)|\(durationSeconds ?? 0)"

        // Generate SHA256 hash
        let hash = SHA256.hash(data: Data(hashInput.utf8))
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        return CanonicalTrackID(value: String(hashString.prefix(32)))
    }

    /// Generate a stable canonical playlist ID
    public static func generateCanonicalPlaylistID(
        name: String,
        owner: String?
    ) -> CanonicalPlaylistID {
        let normalizedName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOwner = owner?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let hashInput = "\(normalizedOwner)|\(normalizedName)"
        let hash = SHA256.hash(data: Data(hashInput.utf8))
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        return CanonicalPlaylistID(value: String(hashString.prefix(32)))
    }

    // MARK: - Spotify → Canonical

    /// Convert Spotify track reference to canonical track
    public static func toCanonical(spotifyTrack: SpotifyTrackRef) -> CanonicalTrack {
        let id = generateCanonicalTrackID(
            title: spotifyTrack.name,
            artist: spotifyTrack.artistNames.first ?? "Unknown Artist",
            album: spotifyTrack.albumName,
            durationSeconds: spotifyTrack.durationMs.map { $0 / 1000 }
        )

        return CanonicalTrack(
            id: id,
            title: spotifyTrack.name,
            artist: spotifyTrack.artistNames.first ?? "Unknown Artist",
            album: spotifyTrack.albumName,
            durationSeconds: spotifyTrack.durationMs.map { $0 / 1000 },
            isExplicit: spotifyTrack.isExplicit,
            isrc: spotifyTrack.isrc,
            spotifyID: spotifyTrack.id,
            appleID: nil,
            availability: [.spotify]
        )
    }

    /// Convert Spotify playlist reference to canonical playlist
    public static func toCanonical(spotifyPlaylist: SpotifyPlaylistRef) -> CanonicalPlaylist {
        let id = generateCanonicalPlaylistID(
            name: spotifyPlaylist.name,
            owner: spotifyPlaylist.owner
        )

        // Convert track refs to canonical tracks and extract IDs
        let canonicalTracks = spotifyPlaylist.trackRefs.map { toCanonical(spotifyTrack: $0) }

        return CanonicalPlaylist(
            id: id,
            name: spotifyPlaylist.name,
            owner: spotifyPlaylist.owner,
            description: spotifyPlaylist.description,
            trackIDs: canonicalTracks.map { $0.id },
            sourceSpotifyID: spotifyPlaylist.id,
            sourceAppleID: nil
        )
    }

    // MARK: - Apple Music → Canonical

    /// Convert Apple Music track reference to canonical track
    public static func toCanonical(appleTrack: AppleTrackRef) -> CanonicalTrack {
        let id = generateCanonicalTrackID(
            title: appleTrack.name,
            artist: appleTrack.artistName,
            album: appleTrack.albumName,
            durationSeconds: appleTrack.durationMs.map { $0 / 1000 }
        )

        return CanonicalTrack(
            id: id,
            title: appleTrack.name,
            artist: appleTrack.artistName,
            album: appleTrack.albumName,
            durationSeconds: appleTrack.durationMs.map { $0 / 1000 },
            isExplicit: appleTrack.isExplicit,
            isrc: appleTrack.isrc,
            spotifyID: nil,
            appleID: appleTrack.id,
            availability: [.appleMusic]
        )
    }

    /// Convert Apple Music playlist reference to canonical playlist
    public static func toCanonical(applePlaylist: ApplePlaylistRef) -> CanonicalPlaylist {
        let id = generateCanonicalPlaylistID(
            name: applePlaylist.name,
            owner: nil  // Apple Music doesn't always provide playlist owner
        )

        // Convert track refs to canonical tracks and extract IDs
        let canonicalTracks = applePlaylist.trackRefs.map { toCanonical(appleTrack: $0) }

        return CanonicalPlaylist(
            id: id,
            name: applePlaylist.name,
            owner: nil,
            description: applePlaylist.description,
            trackIDs: canonicalTracks.map { $0.id },
            sourceSpotifyID: nil,
            sourceAppleID: applePlaylist.id
        )
    }

    // MARK: - Batch Conversions

    /// Convert array of Spotify tracks and return both canonical tracks and playlist tracks separately
    public static func toCanonical(spotifyTracks: [SpotifyTrackRef]) -> [CanonicalTrack] {
        return spotifyTracks.map { toCanonical(spotifyTrack: $0) }
    }

    /// Convert array of Apple tracks
    public static func toCanonical(appleTracks: [AppleTrackRef]) -> [CanonicalTrack] {
        return appleTracks.map { toCanonical(appleTrack: $0) }
    }

    /// Extract all unique tracks from a Spotify playlist (including tracks from trackRefs)
    public static func extractTracksFromPlaylist(spotifyPlaylist: SpotifyPlaylistRef) -> [CanonicalTrack] {
        return spotifyPlaylist.trackRefs.map { toCanonical(spotifyTrack: $0) }
    }

    /// Extract all unique tracks from an Apple Music playlist
    public static func extractTracksFromPlaylist(applePlaylist: ApplePlaylistRef) -> [CanonicalTrack] {
        return applePlaylist.trackRefs.map { toCanonical(appleTrack: $0) }
    }
}
