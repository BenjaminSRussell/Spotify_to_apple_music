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

// MARK: - Durable resolution prompt (#7, #10)

/// What the user decided for one pending track.
public enum ResolverChoice: Equatable, Sendable {
    case choose(candidateID: String)
    case reject(candidateID: String)
    case skip
    case later
    case quit
}

extension MatchResolver {
    /// Parse one line of resolver input: `N` choose, `xN` reject candidate N, `s` skip forever,
    /// `n`/empty decide later, `q` quit. Returns nil for invalid input.
    public static func parseChoice(_ input: String, candidateIDs: [String]) -> ResolverChoice? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch text {
        case "", "n", "next": return .later
        case "s", "skip": return .skip
        case "q", "quit": return .quit
        default: break
        }
        let reject = text.hasPrefix("x")
        guard let index = Int(reject ? String(text.dropFirst()) : text),
              index >= 1, index <= candidateIDs.count else { return nil }
        let id = candidateIDs[index - 1]
        return reject ? .reject(candidateID: id) : .choose(candidateID: id)
    }

    /// Text shown for one pending resolution (mirrors the app's resolver screen).
    public static func render(_ pending: PendingResolution, position: Int, total: Int) -> String {
        var lines = [
            String(repeating: "=", count: 70),
            "[\(position)/\(total)] \(pending.source.title) — \(pending.source.artist)"
                + (pending.source.album.map { "  (\($0))" } ?? "")
                + "  → \(pending.targetService == .appleMusic ? "Apple Music" : "Spotify")",
            String(repeating: "-", count: 70)
        ]
        for (index, candidate) in pending.candidates.enumerated() {
            let track = candidate.track
            let title = track.map { "\($0.title) — \($0.artist)" } ?? candidate.id
            let album = track?.album.map { " (\($0))" } ?? ""
            lines.append(String(format: "  %2d. %3.0f%%  ", index + 1, candidate.score.score * 100) + title + album)
        }
        lines.append("Choose 1-\(pending.candidates.count), xN reject candidate N, s skip track, Enter later, q quit")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Errors

public enum MatchResolutionError: Error {
    case userQuit
    case invalidInput
}
