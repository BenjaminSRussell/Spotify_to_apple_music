import Foundation

/// In-memory blocking index over the tracks available on one target service (#14).
///
/// Built once per batch from a single `fetchAll()`, then used for every source track.
/// - ISRC lookups are O(1) (keys uppercased).
/// - Metadata candidates come from normalized artist-word postings. The **rarest** words are
///   used first, and very common words ("the", "lil", "dj", "artist") are only used when nothing
///   rarer matched. The result does not depend on table order.
/// - Candidates are **ranked** with a cheap title/artist pre-score before truncation, so the true
///   match is never cut off just because it was inserted late.
public struct CandidateIndex: Sendable {
    public let targetService: MusicService
    private let tracks: [CanonicalTrack]
    private let normalizedTitles: [String]
    private let normalizedArtists: [String]
    private let byISRC: [String: Int]
    private let postings: [String: [Int]]
    private let normalizer = TrackTextNormalizer()
    private let similarity = StringSimilarity()

    /// Postings longer than this are treated as "common" words and skipped when a rarer word matched.
    public let commonWordThreshold: Int
    /// Maximum candidates handed to the full `ConfidenceScorer` after pre-ranking.
    public let maxCandidates: Int

    public init(
        tracks allTracks: [CanonicalTrack],
        targetService: MusicService,
        commonWordThreshold: Int = 500,
        maxCandidates: Int = 50
    ) {
        self.targetService = targetService
        self.commonWordThreshold = commonWordThreshold
        self.maxCandidates = maxCandidates

        let normalizer = TrackTextNormalizer()
        let available = allTracks.filter { $0.availability.contains(targetService) }
        var titles: [String] = []
        var artists: [String] = []
        var isrc: [String: Int] = [:]
        var postings: [String: [Int]] = [:]
        titles.reserveCapacity(available.count)
        artists.reserveCapacity(available.count)

        for (i, track) in available.enumerated() {
            titles.append(normalizer.normalizeTitle(track.title))
            let artist = normalizer.normalizeArtist(track.artist)
            artists.append(artist)
            if let code = track.isrc, !code.isEmpty, isrc[code.uppercased()] == nil {
                isrc[code.uppercased()] = i
            }
            for word in Set(artist.split(separator: " ").map(String.init)) {
                postings[word, default: []].append(i)
            }
        }

        self.tracks = available
        self.normalizedTitles = titles
        self.normalizedArtists = artists
        self.byISRC = isrc
        self.postings = postings
    }

    /// Number of indexed tracks (available on the target service)
    public var count: Int { tracks.count }

    /// Exact ISRC hit on the target service (case-insensitive)
    public func track(forISRC isrc: String) -> CanonicalTrack? {
        guard !isrc.isEmpty, let i = byISRC[isrc.uppercased()] else { return nil }
        return tracks[i]
    }

    /// Candidates for `source`: an ISRC hit alone if there is one, else ranked metadata candidates.
    public func candidates(for source: CanonicalTrack) -> [CanonicalTrack] {
        if let code = source.isrc, let hit = track(forISRC: code) {
            return [hit]
        }
        return metadataCandidates(title: source.title, artist: source.artist)
    }

    /// Ranked metadata candidates (at most `maxCandidates`)
    public func metadataCandidates(title: String, artist: String) -> [CanonicalTrack] {
        let sourceArtist = normalizer.normalizeArtist(artist)
        let words = Set(sourceArtist.split(separator: " ").map(String.init))
        let lists = words.compactMap { postings[$0] }.sorted { $0.count < $1.count }
        guard !lists.isEmpty else { return [] }

        var picked = Set<Int>()
        for list in lists {
            if list.count > commonWordThreshold && !picked.isEmpty { break }
            picked.formUnion(list)
        }

        let sourceTitle = normalizer.normalizeTitle(title)
        let ranked = picked.map { i -> (Int, Double) in
            let titleScore = similarity.similarity(sourceTitle, normalizedTitles[i])
            let artistScore = similarity.similarity(sourceArtist, normalizedArtists[i])
            return (i, titleScore * 0.6 + artistScore * 0.4)
        }
        // Deterministic: score desc, then index (insertion order) as the tie-break.
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }

        return ranked.prefix(maxCandidates).map { tracks[$0.0] }
    }
}
