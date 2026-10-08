import XCTest
import GRDB
@testable import MergeCore

/// Track store double that counts full-table reads (#14)
final class CountingTrackStore: TrackStore, @unchecked Sendable {
    private let inner: TrackStoreImpl
    private let lock = NSLock()
    private var _fetchAllCalls = 0
    private var _isrcCalls = 0

    init(inner: TrackStoreImpl) { self.inner = inner }

    var fetchAllCalls: Int { lock.lock(); defer { lock.unlock() }; return _fetchAllCalls }
    var isrcCalls: Int { lock.lock(); defer { lock.unlock() }; return _isrcCalls }

    func save(_ track: CanonicalTrack) async throws { try await inner.save(track) }
    func saveAll(_ tracks: [CanonicalTrack]) async throws { try await inner.saveAll(tracks) }
    func fetch(id: CanonicalTrackID) async throws -> CanonicalTrack? { try await inner.fetch(id: id) }
    func fetchBySpotifyID(_ id: String) async throws -> CanonicalTrack? { try await inner.fetchBySpotifyID(id) }
    func fetchByAppleID(_ id: String) async throws -> CanonicalTrack? { try await inner.fetchByAppleID(id) }
    func fetchByISRC(_ isrc: String) async throws -> CanonicalTrack? { try await inner.fetchByISRC(isrc) }
    func fetchByISRC(_ isrc: String, availableOn service: MusicService) async throws -> CanonicalTrack? {
        lock.lock(); _isrcCalls += 1; lock.unlock()
        return try await inner.fetchByISRC(isrc, availableOn: service)
    }
    func fetchAll() async throws -> [CanonicalTrack] {
        lock.lock(); _fetchAllCalls += 1; lock.unlock()
        return try await inner.fetchAll()
    }
    func delete(id: CanonicalTrackID) async throws { try await inner.delete(id: id) }
}

final class MatchEngineIndexTests: XCTestCase {
    private var db: DatabaseProvider!
    private var store: CountingTrackStore!
    private var engine: MatchEngine!

    override func setUp() async throws {
        db = try DatabaseProvider.inMemory()
        store = CountingTrackStore(inner: TrackStoreImpl(dbQueue: db.dbQueue))
        engine = MatchEngine(trackStore: store, mappingStore: MappingStoreImpl(dbQueue: db.dbQueue))
    }

    private func apple(_ id: String, _ title: String, _ artist: String, isrc: String? = nil) -> CanonicalTrack {
        CanonicalTrack(id: CanonicalTrackID(value: "am-\(id)"), title: title, artist: artist,
                       durationSeconds: 200, isrc: isrc, appleID: "am-\(id)", availability: .appleMusic)
    }

    private func spotify(_ id: String, _ title: String, _ artist: String, isrc: String? = nil) -> CanonicalTrack {
        CanonicalTrack(id: CanonicalTrackID(value: "sp-\(id)"), title: title, artist: artist,
                       durationSeconds: 200, isrc: isrc, spotifyID: "sp-\(id)", availability: .spotify)
    }

    func testMatchTracksReadsCatalogOnce() async throws {
        try await store.saveAll((0..<30).map { apple("\($0)", "Song \($0)", "Band \($0)") })
        let sources = (0..<25).map { spotify("\($0)", "Song \($0)", "Band \($0)") }
        let before = store.fetchAllCalls

        let results = try await engine.matchTracks(sources: sources, targetService: .appleMusic)

        XCTAssertEqual(results.count, 25)
        XCTAssertEqual(store.fetchAllCalls - before, 1, "N sources must cost O(1) full reads, not O(N)")
        XCTAssertEqual(store.isrcCalls, 0, "batch path uses the in-memory ISRC map")
    }

    func testGenericArtistWordDoesNotHideTrueMatch() async throws {
        // 60 "Lil X" rows inserted BEFORE the true match: the old prefix(50) never scored it.
        try await store.saveAll((0..<60).map { apple("x\($0)", "Track \($0)", "Lil X") })
        let truth = apple("truth", "Song", "Lil Y")
        try await store.save(truth)

        let source = spotify("1", "Song", "Lil Y")
        let single = try await engine.matchSpotifyTrackToApple(source)
        let batch = try await engine.matchTracks(sources: [source], targetService: .appleMusic)

        for decision in [single, batch[source.id]] {
            guard case .auto(let match)? = decision else {
                return XCTFail("expected auto match on Lil Y – Song, got \(String(describing: decision))")
            }
            XCTAssertEqual(match.candidateID, truth.id.value)
        }
    }

    func testISRCLookupIsCaseInsensitiveAndServiceScoped() async throws {
        try await store.save(apple("a", "Song", "Artist", isrc: "USABC1234567"))
        let hit = try await store.fetchByISRC("usabc1234567", availableOn: .appleMusic)
        XCTAssertEqual(hit?.appleID, "am-a")
        let miss = try await store.fetchByISRC("USABC1234567", availableOn: .spotify)
        XCTAssertNil(miss, "track is not on Spotify")

        let decision = try await engine.matchSpotifyTrackToApple(spotify("s", "Different Title", "Someone", isrc: "usabc1234567"))
        guard case .auto(let match) = decision else { return XCTFail("ISRC should auto-match") }
        XCTAssertEqual(match.method, .isrc)
        XCTAssertEqual(store.fetchAllCalls, 0, "ISRC hit must not load the table")
    }

    func testISRCLookupUsesIndex() throws {
        let plan = try db.dbQueue.read { db in
            try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN " + TrackStoreImpl.isrcLookupSQL,
                             arguments: ["X", 1]).map { $0["detail"] as String }
        }.joined(separator: "\n")
        XCTAssertTrue(plan.contains("idx_tracks_isrc_nocase"), "query plan was: \(plan)")
    }

    func testCandidateIndexRanksBeforeTruncating() {
        var tracks = (0..<200).map { apple("d\($0)", "Other \($0)", "DJ Common") }
        tracks.append(apple("t", "Exact Title", "DJ Common"))
        let index = CandidateIndex(tracks: tracks, targetService: .appleMusic, maxCandidates: 5)
        let got = index.metadataCandidates(title: "Exact Title", artist: "DJ Common")
        XCTAssertEqual(got.count, 5)
        XCTAssertEqual(got.first?.id.value, "am-t")
    }

    func testStatisticsFromPrecomputedResults() async throws {
        try await store.save(apple("1", "Song", "Band"))
        let results = try await engine.matchTracks(
            sources: [spotify("1", "Song", "Band"), spotify("2", "Nothing", "Nobody")],
            targetService: .appleMusic
        )
        let reads = store.fetchAllCalls
        let stats = MatchEngine.statistics(from: results)
        XCTAssertEqual(stats.total, 2)
        XCTAssertEqual(stats.autoMatches, 1)
        XCTAssertEqual(stats.noMatches, 1)
        XCTAssertEqual(store.fetchAllCalls, reads, "statistics must not re-match")
    }
}
