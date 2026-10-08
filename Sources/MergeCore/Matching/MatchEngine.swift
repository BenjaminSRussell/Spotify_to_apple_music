import Foundation

/// Main matching engine orchestrator
/// Implements multi-stage matching pipeline with confidence scoring
public final class MatchEngine: Sendable {
    private let policy: MergePolicy
    private let scorer: ConfidenceScorer
    private let trackStore: TrackStore
    private let mappingStore: MappingStore

    public init(
        policy: MergePolicy = .default,
        trackStore: TrackStore = TrackStoreImpl(),
        mappingStore: MappingStore = MappingStoreImpl()
    ) {
        self.policy = policy
        self.scorer = ConfidenceScorer()
        self.trackStore = trackStore
        self.mappingStore = mappingStore
    }

    // MARK: - Public Matching Methods

    /// Match a Spotify track to Apple Music
    /// Implements 6-stage matching pipeline
    public func matchSpotifyTrackToApple(_ source: CanonicalTrack) async throws -> MatchDecision {
        return try await match(source: source, targetService: .appleMusic)
    }

    /// Match an Apple Music track to Spotify
    public func matchAppleTrackToSpotify(_ source: CanonicalTrack) async throws -> MatchDecision {
        return try await match(source: source, targetService: .spotify)
    }

    // MARK: - Multi-Stage Matching Pipeline

    /// Core matching pipeline
    /// Stage 0: Check manual mappings
    /// Stage 1: Check ISRC exact match
    /// Stage 2: Fuzzy metadata matching
    /// Stage 3: Confidence-based decision
    private func match(source: CanonicalTrack, targetService: MusicService) async throws -> MatchDecision {
        // Stage 0: Check for existing manual mapping
        if let manualMatch = try await checkManualMapping(source: source, targetService: targetService) {
            return .auto(candidate: manualMatch)
        }

        // Stage 1: Get candidate tracks from target service
        let candidates = try await getCandidates(for: source, targetService: targetService)

        if candidates.isEmpty {
            return .noMatch
        }

        // Stage 2: Score all candidates
        let decision = scorer.makeDecision(source: source, candidates: candidates)

        return decision
    }

    // MARK: - Stage 0: Manual Mappings

    /// Check for existing manual mapping
    private func checkManualMapping(
        source: CanonicalTrack,
        targetService: MusicService
    ) async throws -> MatchScore? {
        let sourceService: MusicService = targetService == .appleMusic ? .spotify : .appleMusic
        let sourceID: String?

        if sourceService == .spotify {
            sourceID = source.spotifyID
        } else {
            sourceID = source.appleID
        }

        guard let sourceID = sourceID else {
            return nil
        }

        if let mapping = try await mappingStore.getManualMapping(
            sourceService: sourceService,
            sourceID: sourceID
        ) {
            // Found manual mapping
            Log.info("Found manual mapping for track: \(source.title) by \(source.artist)")

            return MatchScore(
                candidateID: mapping.targetTrackID,
                score: mapping.confidenceScore ?? 1.0,
                components: MatchScoreComponents(
                    titleScore: 1.0,
                    artistScore: 1.0,
                    albumScore: 1.0,
                    durationScore: 1.0,
                    isrcBonus: 0.0
                ),
                method: .manual
            )
        }

        return nil
    }

    // MARK: - Stage 1: Candidate Retrieval

    /// Get candidate tracks from target service (single-track path)
    /// ISRC uses the indexed `TrackStore.fetchByISRC(_:availableOn:)` query. Metadata search
    /// builds a `CandidateIndex` from one `fetchAll()`. Batches should use `matchTracks`,
    /// which builds the index once for all sources.
    private func getCandidates(
        for source: CanonicalTrack,
        targetService: MusicService
    ) async throws -> [CanonicalTrack] {
        if let isrc = source.isrc, !isrc.isEmpty,
           let hit = try await trackStore.fetchByISRC(isrc, availableOn: targetService) {
            return [hit]
        }
        let index = CandidateIndex(tracks: try await trackStore.fetchAll(), targetService: targetService)
        return index.metadataCandidates(title: source.title, artist: source.artist)
    }

    /// Match using a prebuilt index (no store reads besides the manual-mapping lookup)
    private func match(
        source: CanonicalTrack,
        index: CandidateIndex
    ) async throws -> MatchDecision {
        if let manualMatch = try await checkManualMapping(source: source, targetService: index.targetService) {
            return .auto(candidate: manualMatch)
        }
        let candidates = index.candidates(for: source)
        if candidates.isEmpty {
            return .noMatch
        }
        return scorer.makeDecision(source: source, candidates: candidates)
    }

    // MARK: - Batch Matching

    /// Build a candidate index for `targetService` with a single full read of `canonical_tracks`
    public func makeCandidateIndex(targetService: MusicService) async throws -> CandidateIndex {
        CandidateIndex(tracks: try await trackStore.fetchAll(), targetService: targetService)
    }

    /// Match multiple tracks at once
    /// Reads `canonical_tracks` once (O(1) full reads for N sources) and matches with a
    /// bounded task group.
    public func matchTracks(
        sources: [CanonicalTrack],
        targetService: MusicService,
        maxConcurrency: Int = 8
    ) async throws -> [CanonicalTrackID: MatchDecision] {
        guard !sources.isEmpty else { return [:] }
        let index = try await makeCandidateIndex(targetService: targetService)
        var results: [CanonicalTrackID: MatchDecision] = [:]
        results.reserveCapacity(sources.count)

        try await withThrowingTaskGroup(of: (CanonicalTrackID, MatchDecision).self) { group in
            var iterator = sources.makeIterator()
            var running = 0
            while running < max(1, maxConcurrency), let source = iterator.next() {
                group.addTask { (source.id, try await self.match(source: source, index: index)) }
                running += 1
            }
            while let (id, decision) = try await group.next() {
                results[id] = decision
                if let source = iterator.next() {
                    group.addTask { (source.id, try await self.match(source: source, index: index)) }
                }
            }
        }

        return results
    }

    /// Get match statistics for a set of tracks
    public func getMatchStatistics(
        sources: [CanonicalTrack],
        targetService: MusicService
    ) async throws -> MatchStatistics {
        let results = try await matchTracks(sources: sources, targetService: targetService)
        return Self.statistics(from: results)
    }

    /// Statistics from already-computed results (no re-matching)
    public static func statistics(from results: [CanonicalTrackID: MatchDecision]) -> MatchStatistics {
        var autoMatches = 0
        var ambiguousMatches = 0
        var noMatches = 0

        for decision in results.values {
            switch decision {
            case .auto:
                autoMatches += 1
            case .ambiguous:
                ambiguousMatches += 1
            case .noMatch:
                noMatches += 1
            }
        }

        return MatchStatistics(
            total: results.count,
            autoMatches: autoMatches,
            ambiguousMatches: ambiguousMatches,
            noMatches: noMatches
        )
    }
}

// MARK: - Match Statistics

/// Statistics about matching results
public struct MatchStatistics: Sendable {
    public let total: Int
    public let autoMatches: Int
    public let ambiguousMatches: Int
    public let noMatches: Int

    public var autoMatchRate: Double {
        guard total > 0 else { return 0.0 }
        return Double(autoMatches) / Double(total)
    }

    public var summary: String {
        """
        Match Statistics:
        - Total tracks: \(total)
        - Auto-matched: \(autoMatches) (\(String(format: "%.1f%%", autoMatchRate * 100)))
        - Needs review: \(ambiguousMatches)
        - No match found: \(noMatches)
        """
    }
}
