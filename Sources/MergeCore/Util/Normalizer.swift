import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Utilities for normalizing and converting service-specific models to canonical models
public struct Normalizer {

    // MARK: - Canonical ID Generation

    /// Round millisecond durations to nearest second so 215999 vs 216000 do not split (#13).
    public static func roundedDurationSeconds(durationMs: Int?) -> Int? {
        guard let ms = durationMs else { return nil }
        return (ms + 500) / 1000
    }

    /// Generate a stable canonical track ID from normalized metadata.
    /// Prefer ISRC when present (`isrc:<CODE>`); otherwise hash metadata with rounded duration.
    public static func generateCanonicalTrackID(
        title: String,
        artist: String,
        album: String?,
        durationSeconds: Int?,
        isrc: String? = nil
    ) -> CanonicalTrackID {
        if let isrc = isrc?.trimmingCharacters(in: .whitespacesAndNewlines), !isrc.isEmpty {
            let normalizedISRC = isrc.uppercased()
            return CanonicalTrackID(value: "isrc:\(normalizedISRC)")
        }

        let normalizedTitle = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedArtist = artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAlbum = album?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let hashInput = "\(normalizedArtist)|\(normalizedTitle)|\(normalizedAlbum)|\(durationSeconds ?? 0)"
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
        let duration = roundedDurationSeconds(durationMs: spotifyTrack.durationMs)
        let id = generateCanonicalTrackID(
            title: spotifyTrack.name,
            artist: spotifyTrack.artistNames.first ?? "Unknown Artist",
            album: spotifyTrack.albumName,
            durationSeconds: duration,
            isrc: spotifyTrack.isrc
        )

        return CanonicalTrack(
            id: id,
            title: spotifyTrack.name,
            artist: spotifyTrack.artistNames.first ?? "Unknown Artist",
            album: spotifyTrack.albumName,
            durationSeconds: duration,
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
        let duration = roundedDurationSeconds(durationMs: appleTrack.durationMs)
        let id = generateCanonicalTrackID(
            title: appleTrack.name,
            artist: appleTrack.artistName,
            album: appleTrack.albumName,
            durationSeconds: duration,
            isrc: appleTrack.isrc
        )

        return CanonicalTrack(
            id: id,
            title: appleTrack.name,
            artist: appleTrack.artistName,
            album: appleTrack.albumName,
            durationSeconds: duration,
            isExplicit: appleTrack.isExplicit,
            isrc: appleTrack.isrc,
            spotifyID: nil,
            appleID: appleTrack.id,
            availability: [.appleMusic]
        )
    }

    /// Convert Apple Music playlist reference to canonical playlist
    public static func toCanonical(applePlaylist: ApplePlaylistRef) -> CanonicalPlaylist {
        // Prefer stable Apple library playlist ID so same-name playlists do not collide (#13).
        let id: CanonicalPlaylistID
        if !applePlaylist.id.isEmpty {
            id = CanonicalPlaylistID(value: "apple:\(applePlaylist.id)")
        } else {
            id = generateCanonicalPlaylistID(
                name: applePlaylist.name,
                owner: nil
            )
        }

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
