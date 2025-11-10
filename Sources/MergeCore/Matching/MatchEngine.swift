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

    /// Get candidate tracks from target service
    /// Uses multiple search strategies to find potential matches
    private func getCandidates(
        for source: CanonicalTrack,
        targetService: MusicService
    ) async throws -> [CanonicalTrack] {
        // Strategy 1: ISRC exact match
        if let isrc = source.isrc, !isrc.isEmpty {
            if let isrcMatch = try await findByISRC(isrc: isrc, service: targetService) {
                return [isrcMatch]
            }
        }

        // Strategy 2: Search by metadata
        let metadataCandidates = try await searchByMetadata(
            title: source.title,
            artist: source.artist,
            album: source.album,
            targetService: targetService
        )

        return metadataCandidates
    }

    /// Find track by ISRC in target service
    private func findByISRC(isrc: String, service: MusicService) async throws -> CanonicalTrack? {
        let tracks = try await trackStore.fetchAll()

        return tracks.first { track in
            guard track.availability.contains(service) else {
                return false
            }

            return track.isrc?.lowercased() == isrc.lowercased()
        }
    }

    /// Search for tracks by metadata
    private func searchByMetadata(
        title: String,
        artist: String,
        album: String?,
        targetService: MusicService
    ) async throws -> [CanonicalTrack] {
        // Get all tracks for target service
        let allTracks = try await trackStore.fetchAll()

        let candidates = allTracks.filter { track in
            // Must be available on target service
            guard track.availability.contains(targetService) else {
                return false
            }

            // Basic filtering: artist name should have some similarity
            let normalizer = TrackTextNormalizer()
            let sourceArtist = normalizer.normalizeArtist(artist)
            let candidateArtist = normalizer.normalizeArtist(track.artist)

            // Quick filter: artist names should share at least one word
            let sourceWords = Set(sourceArtist.split(separator: " "))
            let candidateWords = Set(candidateArtist.split(separator: " "))

            return !sourceWords.isDisjoint(with: candidateWords)
        }

        // Limit to reasonable number of candidates
        return Array(candidates.prefix(50))
    }

    // MARK: - Batch Matching

    /// Match multiple tracks at once
    public func matchTracks(
        sources: [CanonicalTrack],
        targetService: MusicService
    ) async throws -> [CanonicalTrack: MatchDecision] {
        var results: [CanonicalTrack: MatchDecision] = [:]

        for source in sources {
            let decision = try await match(source: source, targetService: targetService)
            results[source] = decision
        }

        return results
    }

    /// Get match statistics for a set of tracks
    public func getMatchStatistics(
        sources: [CanonicalTrack],
        targetService: MusicService
    ) async throws -> MatchStatistics {
        let results = try await matchTracks(sources: sources, targetService: targetService)

        var autoMatches = 0
        var ambiguousMatches = 0
        var noMatches = 0

        for (_, decision) in results {
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
            total: sources.count,
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
