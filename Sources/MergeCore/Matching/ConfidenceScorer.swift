import Foundation

/// Confidence scoring system for track matches
/// Combines multiple signals into a single confidence score
public struct ConfidenceScorer: Sendable {
    private let weights: MatchWeights
    private let isrcMatcher: ISRCMatcher
    private let durationMatcher: DurationMatcher
    private let similarity: StringSimilarity
    private let normalizer: TrackTextNormalizer

    public init(
        weights: MatchWeights = .default,
        durationToleranceSeconds: Int = 5
    ) {
        self.weights = weights
        self.isrcMatcher = ISRCMatcher()
        self.durationMatcher = DurationMatcher(toleranceSeconds: durationToleranceSeconds)
        self.similarity = StringSimilarity()
        self.normalizer = TrackTextNormalizer()
    }

    // MARK: - Scoring

    /// Calculate comprehensive match score for two tracks
    public func score(source: CanonicalTrack, candidate: CanonicalTrack) -> MatchScore {
        // Check for ISRC match first (highest confidence)
        let isrcBonus = isrcMatcher.matchScore(track1: source, track2: candidate)

        if isrcBonus > 0 {
            // ISRC match found - high confidence
            let components = MatchScoreComponents(
                titleScore: 1.0,
                artistScore: 1.0,
                albumScore: 1.0,
                durationScore: durationMatcher.durationScore(
                    duration1: source.durationSeconds,
                    duration2: candidate.durationSeconds
                ),
                isrcBonus: isrcBonus
            )

            return MatchScore(
                candidateID: candidate.id.value,
                score: 0.95,  // ISRC match is very high confidence
                components: components,
                method: .isrc
            )
        }

        // No ISRC match - use fuzzy matching
        return scoreFuzzyMatch(source: source, candidate: candidate)
    }

    /// Calculate fuzzy match score using metadata
    private func scoreFuzzyMatch(source: CanonicalTrack, candidate: CanonicalTrack) -> MatchScore {
        // Normalize all fields
        let sourceNorm = normalizer.makeKey(
            title: source.title,
            artist: source.artist,
            album: source.album
        )

        let candidateNorm = normalizer.makeKey(
            title: candidate.title,
            artist: candidate.artist,
            album: candidate.album
        )

        // Calculate individual component scores
        let titleScore = similarity.similarity(sourceNorm.titleKey, candidateNorm.titleKey)
        let artistScore = similarity.similarity(sourceNorm.artistKey, candidateNorm.artistKey)

        let albumScore: Double
        if let sourceAlbum = sourceNorm.albumKey, let candidateAlbum = candidateNorm.albumKey {
            albumScore = similarity.similarity(sourceAlbum, candidateAlbum)
        } else {
            albumScore = 0.5  // Neutral if album missing
        }

        let durationScore = durationMatcher.durationScore(
            duration1: source.durationSeconds,
            duration2: candidate.durationSeconds
        )

        // Calculate weighted total
        let totalScore = (
            titleScore * weights.title +
            artistScore * weights.artist +
            albumScore * weights.album +
            durationScore * weights.duration
        )

        let components = MatchScoreComponents(
            titleScore: titleScore,
            artistScore: artistScore,
            albumScore: albumScore,
            durationScore: durationScore,
            isrcBonus: 0.0
        )

        return MatchScore(
            candidateID: candidate.id.value,
            score: totalScore,
            components: components,
            method: .fuzzy
        )
    }

    // MARK: - Batch Scoring

    /// Score multiple candidates and return sorted by confidence
    public func scoreCandidates(
        source: CanonicalTrack,
        candidates: [CanonicalTrack]
    ) -> [MatchScore] {
        let scores = candidates.map { candidate in
            score(source: source, candidate: candidate)
        }

        // Sort by score descending
        return scores.sorted { $0.score > $1.score }
    }

    /// Get top N candidates by confidence score
    public func topCandidates(
        source: CanonicalTrack,
        candidates: [CanonicalTrack],
        limit: Int = 5
    ) -> [MatchScore] {
        let sorted = scoreCandidates(source: source, candidates: candidates)
        return Array(sorted.prefix(limit))
    }

    // MARK: - Decision Making

    /// Make match decision based on scores
    public func makeDecision(
        source: CanonicalTrack,
        candidates: [CanonicalTrack]
    ) -> MatchDecision {
        if candidates.isEmpty {
            return .noMatch
        }

        let scores = scoreCandidates(source: source, candidates: candidates)

        guard let topScore = scores.first else {
            return .noMatch
        }

        // Auto-match threshold: 0.85+
        if topScore.isAutoMatch {
            return .auto(candidate: topScore)
        }

        // Ambiguous range: 0.65-0.85, return top candidates
        let ambiguousCandidates = scores.filter { $0.isAmbiguous }
        if !ambiguousCandidates.isEmpty {
            return .ambiguous(candidates: Array(ambiguousCandidates.prefix(5)))
        }

        // Below threshold
        return .noMatch
    }
}
