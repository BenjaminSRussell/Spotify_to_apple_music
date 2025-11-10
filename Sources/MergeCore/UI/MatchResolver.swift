import Foundation

/// Interactive match resolver for ambiguous matches
/// Presents candidates to user and gets their selection
public struct MatchResolver: Sendable {
    public init() {}

    // MARK: - Resolution

    /// Resolve ambiguous match interactively (CLI-based for now)
    /// Returns the selected candidate or nil if user skips
    public func resolve(
        source: CanonicalTrack,
        candidates: [MatchScore]
    ) async throws -> MatchScore? {
        guard !candidates.isEmpty else {
            return nil
        }

        // Print source track info
        print("\n" + String(repeating: "=", count: 70))
        print("🎵 Ambiguous Match - Manual Selection Required")
        print(String(repeating: "=", count: 70))
        print("\nSource Track:")
        printTrackInfo(source)

        print("\n📋 Found \(candidates.count) potential matches:")
        print(String(repeating: "-", count: 70))

        // Print each candidate with index
        for (index, candidate) in candidates.enumerated() {
            print("\n[\(index + 1)] Confidence: \(String(format: "%.1f%%", candidate.score * 100))")
            print("    Method: \(candidate.method.rawValue)")
            print("    Score Breakdown:")
            print("      Title:    \(String(format: "%.2f", candidate.components.titleScore))")
            print("      Artist:   \(String(format: "%.2f", candidate.components.artistScore))")
            print("      Album:    \(String(format: "%.2f", candidate.components.albumScore))")
            print("      Duration: \(String(format: "%.2f", candidate.components.durationScore))")
            if candidate.components.isrcBonus > 0 {
                print("      ISRC:     ✓ Matched")
            }
        }

        print("\n" + String(repeating: "-", count: 70))
        print("Options:")
        print("  1-\(candidates.count): Select match")
        print("  s: Skip (don't match)")
        print("  q: Quit resolution")
        print(String(repeating: "=", count: 70))

        // Get user input
        print("\nYour choice: ", terminator: "")

        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return nil
        }

        // Handle input
        switch input {
        case "s", "skip":
            print("⏭️  Skipped")
            return nil

        case "q", "quit":
            print("❌ Quitting resolution")
            throw MatchResolutionError.userQuit

        default:
            // Try to parse as number
            if let index = Int(input), index >= 1 && index <= candidates.count {
                let selected = candidates[index - 1]
                print("✅ Selected match #\(index)")
                return selected
            } else {
                print("❌ Invalid selection")
                return nil
            }
        }
    }

    /// Batch resolve multiple ambiguous matches
    /// Returns dictionary of source track ID to selected candidate
    public func resolveBatch(
        ambiguousMatches: [(source: CanonicalTrack, candidates: [MatchScore])]
    ) async throws -> [String: MatchScore] {
        var results: [String: MatchScore] = [:]

        print("\n🔍 Resolving \(ambiguousMatches.count) ambiguous matches...")

        for (index, match) in ambiguousMatches.enumerated() {
            print("\n[\(index + 1)/\(ambiguousMatches.count)]")

            if let selected = try await resolve(source: match.source, candidates: match.candidates) {
                results[match.source.id.value] = selected
            }
        }

        print("\n✅ Resolution complete: \(results.count)/\(ambiguousMatches.count) matched")

        return results
    }

    // MARK: - Helper Methods

    private func printTrackInfo(_ track: CanonicalTrack) {
        print("  Title:    \(track.title)")
        print("  Artist:   \(track.artist)")
        if let album = track.album {
            print("  Album:    \(album)")
        }
        if let duration = track.durationSeconds {
            let minutes = duration / 60
            let seconds = duration % 60
            print("  Duration: \(minutes):\(String(format: "%02d", seconds))")
        }
        if let isrc = track.isrc {
            print("  ISRC:     \(isrc)")
        }
    }
}

// MARK: - Errors

public enum MatchResolutionError: Error {
    case userQuit
    case invalidInput
}
