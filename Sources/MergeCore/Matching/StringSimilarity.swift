import Foundation

/// Wrapper for fuzzy string similarity algorithms
public struct StringSimilarity: Sendable {
    public init() {}

    /// Calculate similarity between two strings (0.0 to 1.0)
    public func similarity(_ a: String, _ b: String) -> Double {
        // TODO: Implement using FuzzyMatchingSwift
        // For now, simple exact match
        return a == b ? 1.0 : 0.0
    }
}
