import Foundation

/// A candidate shown in the resolver, with the track details needed to choose (#7, #10).
public struct ResolutionCandidate: Sendable, Identifiable {
    public let score: MatchScore
    public let track: CanonicalTrack?

    public var id: String { score.candidateID }

    public init(score: MatchScore, track: CanonicalTrack?) {
        self.score = score
        self.track = track
    }

    /// VoiceOver label for a candidate row.
    public var accessibilityLabel: String {
        var parts: [String] = []
        if let track {
            parts.append("\(track.title) by \(track.artist)")
            if let album = track.album { parts.append("album \(album)") }
            if let seconds = track.durationSeconds { parts.append("\(seconds / 60) minutes \(seconds % 60) seconds") }
        } else {
            parts.append("Unknown track \(score.candidateID)")
        }
        parts.append("\(Int((score.score * 100).rounded())) percent confidence")
        return parts.joined(separator: ", ")
    }
}

/// An ambiguous source track waiting for a human decision.
public struct PendingResolution: Sendable, Identifiable {
    public let source: CanonicalTrack
    public let targetService: MusicService
    public let candidates: [ResolutionCandidate]

    public init(source: CanonicalTrack, targetService: MusicService, candidates: [ResolutionCandidate]) {
        self.source = source
        self.targetService = targetService
        self.candidates = candidates
    }

    public var id: String { "\(source.id.value)|\(targetService.rawValue)" }

    public var accessibilityLabel: String {
        "\(source.title) by \(source.artist), \(candidates.count) possible \(candidates.count == 1 ? "match" : "matches")"
    }
}

/// Looks up remote catalog candidates for a source track (search services, #7).
public protocol CandidateSearch: Sendable {
    func candidates(for source: CanonicalTrack, on target: MusicService, limit: Int) async throws -> [CanonicalTrack]
}

/// `CandidateSearch` backed by the Spotify / Apple Music search APIs.
public struct SearchServiceCandidateSearch: CandidateSearch {
    private let spotify: SpotifySearchService
    private let apple: AppleSearchService

    public init(spotify: SpotifySearchService, apple: AppleSearchService) {
        self.spotify = spotify
        self.apple = apple
    }

    public func candidates(for source: CanonicalTrack, on target: MusicService, limit: Int) async throws -> [CanonicalTrack] {
        let query = SearchQuery.plain(title: source.title, artist: source.artist)
        switch target {
        case .spotify:
            return Normalizer.toCanonical(spotifyTracks: try await spotify.search(query: query, limit: limit))
        case .appleMusic:
            return Normalizer.toCanonical(appleTracks: try await apple.search(query: query, limit: limit))
        }
    }
}

/// Shared backend for the CLI `resolve` command and the app's resolver screen (#7, #10).
///
/// Choices are durable: *choose* saves a `ManualMapping` (Stage 0, so the next run skips fuzzy
/// matching), *skip* stops the track from being matched or added, *reject* blacklists one
/// candidate for that track.
public final class MatchResolutionService: Sendable {
    private let trackStore: TrackStore
    private let mappingStore: MappingStore
    private let exclusionStore: MatchExclusionStore
    private let matchEngine: MatchEngine
    private let search: CandidateSearch?

    public init(
        trackStore: TrackStore = TrackStoreImpl(),
        mappingStore: MappingStore = MappingStoreImpl(),
        exclusionStore: MatchExclusionStore = MatchExclusionStoreImpl(),
        search: CandidateSearch? = nil
    ) {
        self.trackStore = trackStore
        self.mappingStore = mappingStore
        self.exclusionStore = exclusionStore
        self.search = search
        self.matchEngine = MatchEngine(trackStore: trackStore, mappingStore: mappingStore, exclusionStore: exclusionStore)
    }

    /// Ambiguous tracks for a direction, with candidate details.
    ///
    /// When a search backend is configured, tracks with no local candidates are looked up in
    /// the target catalog first. Results are saved as target-service tracks, so they can be
    /// offered and mapped like local ones.
    public func pendingResolutions(direction: MergeDirection) async throws -> [PendingResolution] {
        var pending: [PendingResolution] = []
        for target in Self.targets(for: direction) {
            pending += try await pendingResolutions(targetService: target)
        }
        return pending
    }

    public func pendingResolutions(targetService target: MusicService) async throws -> [PendingResolution] {
        let sourceService: MusicService = target == .appleMusic ? .spotify : .appleMusic
        var sources = try await trackStore.fetchAll()
            .filter { $0.availability.contains(sourceService) && !$0.availability.contains(target) }
            .sorted { ($0.artist, $0.title) < ($1.artist, $1.title) }
        var decisions = try await matchEngine.matchTracks(sources: sources, targetService: target)

        if let search {
            let unmatched = sources.filter { if case .noMatch? = decisions[$0.id] { return true } else { return false } }
            var fetchedAny = false
            for source in unmatched {
                do {
                    let found = try await search.candidates(for: source, on: target, limit: 5)
                    for track in found where !track.availability.contains(sourceService) {
                        try await trackStore.save(track)
                        fetchedAny = true
                    }
                } catch {
                    Log.error("Catalog search failed for \(source.title)", error: error)
                }
            }
            if fetchedAny {
                // Saved search hits may have merged into existing rows (shared ISRC), so re-read.
                sources = try await trackStore.fetchAll()
                    .filter { $0.availability.contains(sourceService) && !$0.availability.contains(target) }
                    .sorted { ($0.artist, $0.title) < ($1.artist, $1.title) }
                decisions = try await matchEngine.matchTracks(sources: sources, targetService: target)
            }
        }

        var result: [PendingResolution] = []
        for source in sources {
            guard case .ambiguous(let scores)? = decisions[source.id] else { continue }
            var candidates: [ResolutionCandidate] = []
            for score in scores.sorted(by: { $0.score > $1.score }) {
                let track = try await trackStore.fetch(id: CanonicalTrackID(value: score.candidateID))
                candidates.append(ResolutionCandidate(score: score, track: track))
            }
            result.append(PendingResolution(source: source, targetService: target, candidates: candidates))
        }
        return result
    }

    /// Save the user's pick as a manual mapping; the next match returns it at Stage 0.
    public func choose(candidateID: String, for source: CanonicalTrack, targetService: MusicService, score: Double? = nil) async throws {
        let sourceService: MusicService = targetService == .appleMusic ? .spotify : .appleMusic
        let sourceID = (sourceService == .spotify ? source.spotifyID : source.appleID) ?? source.id.value
        let existing = try await mappingStore.getManualMapping(sourceService: sourceService, sourceID: sourceID)
        try await mappingStore.saveManualMapping(ManualMapping(
            id: existing?.id ?? UUID().uuidString,
            canonicalTrackID: source.id,
            sourceService: sourceService,
            sourceTrackID: sourceID,
            targetService: targetService,
            targetTrackID: candidateID,
            confidenceScore: score.map { max($0, 0.99) } ?? 1.0
        ))
        try await exclusionStore.clear(source.id, targetService: targetService)
    }

    /// Never match or add this track on the target service.
    public func skip(_ source: CanonicalTrack, targetService: MusicService) async throws {
        try await exclusionStore.skip(source.id, targetService: targetService)
    }

    /// Never offer this candidate for this track again.
    public func reject(candidateID: String, for source: CanonicalTrack, targetService: MusicService) async throws {
        try await exclusionStore.reject(candidateID: candidateID, for: source.id, targetService: targetService)
    }

    /// Undo every decision (mapping, skip, rejects) for the track on the target.
    public func reset(_ source: CanonicalTrack, targetService: MusicService) async throws {
        let sourceService: MusicService = targetService == .appleMusic ? .spotify : .appleMusic
        let sourceID = (sourceService == .spotify ? source.spotifyID : source.appleID) ?? source.id.value
        if let mapping = try await mappingStore.getManualMapping(sourceService: sourceService, sourceID: sourceID) {
            try await mappingStore.deleteManualMapping(id: mapping.id)
        }
        try await exclusionStore.clear(source.id, targetService: targetService)
    }

    static func targets(for direction: MergeDirection) -> [MusicService] {
        switch direction {
        case .spotifyToApple: return [.appleMusic]
        case .appleToSpotify: return [.spotify]
        case .bidirectional: return [.appleMusic, .spotify]
        }
    }
}
