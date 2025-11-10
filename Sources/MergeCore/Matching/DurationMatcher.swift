import Foundation

/// Duration-based matching and filtering
/// Compares track durations with tolerance for small differences
public struct DurationMatcher: Sendable {
    /// Default tolerance in seconds (±5 seconds)
    public static let defaultToleranceSeconds: Int = 5

    private let toleranceSeconds: Int

    public init(toleranceSeconds: Int = DurationMatcher.defaultToleranceSeconds) {
        self.toleranceSeconds = toleranceSeconds
    }

    // MARK: - Duration Matching

    /// Check if two durations match within tolerance
    public func matchesWithinTolerance(duration1: Int?, duration2: Int?) -> Bool {
        guard let d1 = duration1, let d2 = duration2 else {
            // If either duration is missing, can't filter by duration
            return true
        }

        let difference = abs(d1 - d2)
        return difference <= toleranceSeconds
    }

    /// Calculate duration match score (0.0 to 1.0)
    /// Perfect match: 1.0
    /// Within tolerance: linear decay
    /// Outside tolerance: 0.0
    public func durationScore(duration1: Int?, duration2: Int?) -> Double {
        guard let d1 = duration1, let d2 = duration2 else {
            // Missing duration: neutral score
            return 0.5
        }

        let difference = abs(d1 - d2)

        if difference == 0 {
            return 1.0
        }

        if difference <= toleranceSeconds {
            // Linear decay within tolerance
            return 1.0 - (Double(difference) / Double(toleranceSeconds))
        }

        // Outside tolerance
        return 0.0
    }

    /// Get duration difference in seconds
    public func durationDifference(duration1: Int?, duration2: Int?) -> Int? {
        guard let d1 = duration1, let d2 = duration2 else {
            return nil
        }

        return abs(d1 - d2)
    }

    /// Check if duration difference is acceptable for matching
    /// Stricter than matchesWithinTolerance for high-confidence matches
    public func isAcceptableDifference(duration1: Int?, duration2: Int?, strictMode: Bool = false) -> Bool {
        guard let d1 = duration1, let d2 = duration2 else {
            return true
        }

        let tolerance = strictMode ? (toleranceSeconds / 2) : toleranceSeconds
        let difference = abs(d1 - d2)

        return difference <= tolerance
    }
}
