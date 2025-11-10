import Foundation

/// ISRC-based exact matching for tracks
/// ISRC (International Standard Recording Code) is a unique identifier for recordings
public struct ISRCMatcher: Sendable {
    public init() {}

    /// Check if two tracks have matching ISRCs
    /// Returns true if both have ISRCs and they match
    public func hasMatchingISRC(track1: CanonicalTrack, track2: CanonicalTrack) -> Bool {
        guard let isrc1 = track1.isrc, !isrc1.isEmpty else {
            return false
        }

        guard let isrc2 = track2.isrc, !isrc2.isEmpty else {
            return false
        }

        // ISRCs should match exactly (case-insensitive)
        return isrc1.lowercased() == isrc2.lowercased()
    }

    /// Get ISRC match score
    /// Returns 0.95 for ISRC match, 0.0 otherwise
    /// ISRC is not 1.0 because metadata might still differ (e.g., different versions)
    public func matchScore(track1: CanonicalTrack, track2: CanonicalTrack) -> Double {
        return hasMatchingISRC(track1: track1, track2: track2) ? 0.95 : 0.0
    }

    /// Check if an ISRC is valid format
    /// Format: CC-XXX-YY-NNNNN (12 characters)
    public func isValidISRC(_ isrc: String) -> Bool {
        let cleaned = isrc.replacingOccurrences(of: "-", with: "")
        return cleaned.count == 12 && cleaned.allSatisfy { $0.isUppercase || $0.isNumber }
    }
}
