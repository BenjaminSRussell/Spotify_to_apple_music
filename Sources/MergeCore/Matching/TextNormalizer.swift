import Foundation

/// Advanced text normalization utilities for track matching
public struct TrackTextNormalizer: Sendable {
    public init() {}

    // MARK: - Core Normalization

    /// Normalize text with comprehensive cleaning
    /// - Lowercases
    /// - Removes diacritics (é -> e)
    /// - Removes special characters
    /// - Normalizes whitespace
    private func normalize(_ text: String) -> String {
        var normalized = text.lowercased()

        // Remove diacritics (é -> e, ñ -> n)
        normalized = normalized.folding(options: .diacriticInsensitive, locale: .current)

        // Remove common punctuation and special characters
        normalized = normalized.replacingOccurrences(of: "[^a-z0-9\\s]", with: "", options: .regularExpression)

        // Collapse multiple spaces into one
        normalized = normalized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        // Trim leading/trailing whitespace
        normalized = normalized.trimmingCharacters(in: .whitespaces)

        return normalized
    }

    // MARK: - Track Title Normalization

    /// Normalize a track title for matching
    /// Removes version markers, featured artists, parentheticals
    public func normalizeTitle(_ text: String) -> String {
        var normalized = normalize(text)

        // Remove common version markers
        let versionPatterns = [
            "radio edit",
            "explicit version",
            "explicit",
            "clean version",
            "clean",
            "album version",
            "single version",
            "acoustic version",
            "acoustic",
            "live version",
            "live",
            "remix",
            "remaster",
            "remastered",
            "instrumental"
        ]

        for pattern in versionPatterns {
            normalized = normalized.replacingOccurrences(of: pattern, with: "")
        }

        // Remove featured artists from title (they should be in artist field)
        let featuringPatterns = ["feat ", "ft ", "featuring ", "with "]
        for pattern in featuringPatterns {
            if let range = normalized.range(of: pattern) {
                normalized = String(normalized[..<range.lowerBound])
                break
            }
        }

        // Remove parentheticals and brackets
        normalized = normalized.replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)

        // Clean up resulting spaces
        normalized = normalized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        normalized = normalized.trimmingCharacters(in: .whitespaces)

        return normalized
    }

    // MARK: - Artist Name Normalization

    /// Normalize an artist name for matching
    /// Handles "feat.", "ft.", "&", "and" variations
    /// Extracts primary artist by default
    public func normalizeArtist(_ text: String, extractPrimary: Bool = true) -> String {
        var normalized = normalize(text)

        if extractPrimary {
            // Patterns that indicate featured artists
            let featuringPatterns = [
                "feat ",
                "ft ",
                "featuring ",
                "with ",
                "vs ",
                "x "
            ]

            // Extract only the primary artist (before featuring)
            for pattern in featuringPatterns {
                if let range = normalized.range(of: pattern) {
                    normalized = String(normalized[..<range.lowerBound])
                    break
                }
            }
        }

        // Normalize separators
        normalized = normalized.replacingOccurrences(of: " and ", with: " ")
        normalized = normalized.replacingOccurrences(of: " & ", with: " ")
        normalized = normalized.replacingOccurrences(of: ",", with: "")

        // Clean up any resulting extra spaces
        normalized = normalized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        normalized = normalized.trimmingCharacters(in: .whitespaces)

        return normalized
    }

    // MARK: - Album Name Normalization

    /// Normalize an album name for matching
    /// Removes edition markers (Deluxe, Remaster, etc.)
    public func normalizeAlbum(_ text: String) -> String {
        var normalized = normalize(text)

        // Remove common edition markers
        let editionPatterns = [
            "deluxe edition",
            "deluxe",
            "expanded edition",
            "remastered",
            "remaster",
            "anniversary edition",
            "special edition",
            "limited edition",
            "bonus track edition",
            "explicit version",
            "clean version"
        ]

        for pattern in editionPatterns {
            normalized = normalized.replacingOccurrences(of: pattern, with: "")
        }

        // Remove parentheticals and brackets (often contain edition info)
        normalized = normalized.replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)

        // Remove standalone years (e.g., "2015")
        normalized = normalized.replacingOccurrences(of: "\\b\\d{4}\\b", with: "", options: .regularExpression)

        // Clean up resulting spaces
        normalized = normalized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        normalized = normalized.trimmingCharacters(in: .whitespaces)

        return normalized
    }

    // MARK: - Composite Key Generation

    /// Create a normalized key from track metadata
    public func makeKey(title: String, artist: String, album: String?) -> NormalizedTrackKey {
        return NormalizedTrackKey(
            titleKey: normalizeTitle(title),
            artistKey: normalizeArtist(artist),
            albumKey: album.map { normalizeAlbum($0) }
        )
    }
}
