import Foundation
// import Fuse  // Uncomment when implementing Fuse-swift

/// Wrapper for fuzzy string similarity algorithms
/// Uses Fuse-swift for fuzzy matching when available
public struct StringSimilarity: Sendable {
    public init() {}

    // MARK: - Fuzzy Matching

    /// Calculate fuzzy similarity between two strings (0.0 to 1.0)
    /// Uses Fuse-swift algorithm when available, fallback to Levenshtein
    public func fuzzyMatch(_ a: String, _ b: String) -> Double {
        // TODO: Implement using Fuse-swift
        //
        // let fuse = Fuse(threshold: 0.4)
        // let results = fuse.search(b, in: [a])
        //
        // if let result = results.first {
        //     return 1.0 - result.score  // Fuse returns distance, we want similarity
        // }
        //
        // return 0.0

        // Fallback to simple similarity for now
        return similarity(a, b)
    }

    /// Calculate simple similarity between two strings (0.0 to 1.0)
    /// Uses normalized Levenshtein distance
    public func similarity(_ a: String, _ b: String) -> Double {
        if a == b {
            return 1.0
        }

        if a.isEmpty || b.isEmpty {
            return 0.0
        }

        // Check for containment
        if a.contains(b) || b.contains(a) {
            let shorter = min(a.count, b.count)
            let longer = max(a.count, b.count)
            return Double(shorter) / Double(longer)
        }

        // Levenshtein distance
        let distance = levenshteinDistance(a, b)
        let maxLength = max(a.count, b.count)

        return 1.0 - (Double(distance) / Double(maxLength))
    }

    // MARK: - Distance Calculations

    /// Calculate Levenshtein distance between two strings
    private func levenshteinDistance(_ str1: String, _ str2: String) -> Int {
        let str1Array = Array(str1)
        let str2Array = Array(str2)

        let m = str1Array.count
        let n = str2Array.count

        // Create distance matrix
        var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        // Initialize first column and row
        for i in 0...m {
            matrix[i][0] = i
        }

        for j in 0...n {
            matrix[0][j] = j
        }

        // Fill in the matrix
        for i in 1...m {
            for j in 1...n {
                let cost = str1Array[i - 1] == str2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }

        return matrix[m][n]
    }

    // MARK: - Multi-field Matching

    /// Calculate weighted multi-field similarity for track matching
    /// Combines title, artist, and optional album scores
    public func trackSimilarity(
        title1: String, artist1: String, album1: String?,
        title2: String, artist2: String, album2: String?,
        weights: MatchWeights = .default
    ) -> Double {
        let titleScore = similarity(title1, title2)
        let artistScore = similarity(artist1, artist2)

        var totalScore = titleScore * weights.title + artistScore * weights.artist

        if let album1 = album1, let album2 = album2 {
            let albumScore = similarity(album1, album2)
            totalScore += albumScore * weights.album
        }

        return totalScore
    }
}

/// Weights for multi-field matching
public struct MatchWeights: Sendable {
    public let title: Double
    public let artist: Double
    public let album: Double
    public let duration: Double

    public init(title: Double, artist: Double, album: Double, duration: Double) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }

    /// Default weights for track matching
    public static let `default` = MatchWeights(
        title: 0.40,    // 40% weight on title
        artist: 0.35,   // 35% weight on artist
        album: 0.15,    // 15% weight on album
        duration: 0.10  // 10% weight on duration
    )
}
