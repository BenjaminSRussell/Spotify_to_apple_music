import Foundation

/// Text normalization utilities for track matching
public struct TrackTextNormalizer: Sendable {
    public init() {}

    /// Normalize a track title for matching
    public func normalizeTitle(_ text: String) -> String {
        // TODO: Implement full normalization pipeline
        // - Lowercase
        // - Unicode normalization
        // - Remove (feat. X), (Remastered), (Live), (Explicit), etc.
        // - Strip punctuation
        // - Normalize whitespace
        return text.lowercased()
    }

    /// Normalize an artist name for matching
    public func normalizeArtist(_ text: String) -> String {
        // TODO: Implement artist normalization
        return text.lowercased()
    }

    /// Normalize an album name for matching
    public func normalizeAlbum(_ text: String) -> String {
        // TODO: Implement album normalization
        return text.lowercased()
    }

    /// Create a normalized key from track metadata
    public func makeKey(title: String, artist: String, album: String?) -> NormalizedTrackKey {
        return NormalizedTrackKey(
            titleKey: normalizeTitle(title),
            artistKey: normalizeArtist(artist),
            albumKey: album.map { normalizeAlbum($0) }
        )
    }
}
