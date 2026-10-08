import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MergeCore

private struct FixtureTransport: HTTPTransport {
    let status: Int
    let body: String
    var headers: [String: String] = [:]
    let onRequest: @Sendable (URL, [String: String]) -> Void

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        onRequest(url, request.allHTTPHeaderFields ?? [:])
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        return (Data(body.utf8), response)
    }
}

private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(URL, [String: String])] = []
    func add(_ url: URL, _ headers: [String: String]) { lock.lock(); entries.append((url, headers)); lock.unlock() }
    var last: (URL, [String: String])? { lock.lock(); defer { lock.unlock() }; return entries.last }
}

private struct StubSearch: CandidateSearch {
    let results: [CanonicalTrack]
    func candidates(for source: CanonicalTrack, on target: MusicService, limit: Int) async throws -> [CanonicalTrack] { results }
}

/// #7 / #10: durable manual mappings, skip and reject, search-backed candidates, CLI parity.
final class MatchResolutionTests: XCTestCase {
    private var db: DatabaseProvider!
    private var trackStore: TrackStoreImpl!
    private var mappings: MappingStoreImpl!
    private var exclusions: MatchExclusionStoreImpl!

    override func setUp() async throws {
        db = try DatabaseProvider.inMemory()
        trackStore = TrackStoreImpl(dbQueue: db.dbQueue)
        mappings = MappingStoreImpl(dbQueue: db.dbQueue)
        exclusions = MatchExclusionStoreImpl(dbQueue: db.dbQueue)
    }

    private func service(search: CandidateSearch? = nil) -> MatchResolutionService {
        MatchResolutionService(trackStore: trackStore, mappingStore: mappings, exclusionStore: exclusions, search: search)
    }

    private func engine() -> MatchEngine {
        MatchEngine(trackStore: trackStore, mappingStore: mappings, exclusionStore: exclusions)
    }

    // Source on Spotify, two plausible-but-imperfect Apple Music versions -> ambiguous.
    private let source = CanonicalTrack(
        id: CanonicalTrackID(value: "src"), title: "Heroes", artist: "David Bowie",
        album: "Heroes", durationSeconds: 371, spotifyID: "sp-heroes", availability: .spotify
    )
    private let live = CanonicalTrack(
        id: CanonicalTrackID(value: "am-live"), title: "Heroes (Live)", artist: "David Bowie",
        album: "Stage", durationSeconds: 380, appleID: "am-1", availability: .appleMusic
    )
    private let single = CanonicalTrack(
        id: CanonicalTrackID(value: "am-single"), title: "Heroes Live", artist: "David Bowie",
        album: "A Reality Tour", durationSeconds: 360, appleID: "am-2", availability: .appleMusic
    )

    private func seedAmbiguous() async throws {
        try await trackStore.save(source)
        try await trackStore.save(live)
        try await trackStore.save(single)
        let decision = try await engine().matchSpotifyTrackToApple(source)
        guard case .ambiguous(let candidates) = decision, !candidates.isEmpty else {
            return XCTFail("fixture should be ambiguous, got \(decision)")
        }
    }

    // MARK: Pending list (#10 picker)

    func testPendingResolutionListsCandidatesWithDetailsAndAccessibilityLabels() async throws {
        try await seedAmbiguous()
        let pending = try await service().pendingResolutions(direction: .spotifyToApple)
        let item = try XCTUnwrap(pending.first)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(item.source.id, source.id)
        XCTAssertGreaterThanOrEqual(item.candidates.count, 1)
        XCTAssertNotNil(item.candidates.first?.track, "candidate rows carry track details")
        XCTAssertEqual(item.candidates.map(\.score.score), item.candidates.map(\.score.score).sorted(by: >))
        XCTAssertTrue(item.accessibilityLabel.hasPrefix("Heroes by David Bowie"))
        let label = try XCTUnwrap(item.candidates.first?.accessibilityLabel)
        XCTAssertTrue(label.contains("by David Bowie") && label.contains("percent confidence"), label)
    }

    // MARK: Choose -> Stage 0 next run (#7 acceptance)

    func testSavedMappingSkipsFuzzyMatchingOnNextRun() async throws {
        try await seedAmbiguous()
        let resolver = service()
        let firstPending = try await resolver.pendingResolutions(direction: .spotifyToApple)
        let item = try XCTUnwrap(firstPending.first)
        let pick = try XCTUnwrap(item.candidates.last)
        try await resolver.choose(candidateID: pick.id, for: source, targetService: .appleMusic, score: pick.score.score)

        let decision = try await engine().matchSpotifyTrackToApple(source)
        guard case .auto(let match) = decision else { return XCTFail("expected manual auto-match, got \(decision)") }
        XCTAssertEqual(match.method, .manual)
        XCTAssertEqual(match.candidateID, pick.id, "the user's pick wins even if it wasn't the top score")
        let batch = try await engine().matchTracks(sources: [source], targetService: .appleMusic)
        guard case .auto(let batchMatch)? = batch[source.id] else { return XCTFail("batch path should use mapping too") }
        XCTAssertEqual(batchMatch.method, .manual)
        let stillPending = try await resolver.pendingResolutions(direction: .spotifyToApple)
        XCTAssertTrue(stillPending.isEmpty)

        // Choosing again replaces the mapping instead of violating the unique key.
        try await resolver.choose(candidateID: item.candidates[0].id, for: source, targetService: .appleMusic)
        let all = try await mappings.getAllManualMappings()
        XCTAssertEqual(all.count, 1)
    }

    // MARK: Skip / reject (#10)

    func testSkipStopsMatchingAndAddingTheTrack() async throws {
        try await seedAmbiguous()
        try await service().skip(source, targetService: .appleMusic)

        let decision = try await engine().matchSpotifyTrackToApple(source)
        guard case .skipped = decision else { return XCTFail("expected skipped, got \(decision)") }
        let diff = try await DiffComputer(matchEngine: engine()).computeTrackDiff(sourceTracks: [source], targetService: .appleMusic)
        XCTAssertTrue(diff.isEmpty, "skipped tracks are never added")
        let pending = try await service().pendingResolutions(direction: .spotifyToApple)
        XCTAssertTrue(pending.isEmpty)

        try await service().reset(source, targetService: .appleMusic)
        let after = try await engine().matchSpotifyTrackToApple(source)
        if case .skipped = after { XCTFail("reset should undo skip") }
    }

    func testRejectedCandidateIsNeverOfferedAgain() async throws {
        try await seedAmbiguous()
        let resolver = service()
        let firstPending = try await resolver.pendingResolutions(direction: .spotifyToApple)
        let item = try XCTUnwrap(firstPending.first)
        let rejected = item.candidates[0].id
        try await resolver.reject(candidateID: rejected, for: source, targetService: .appleMusic)

        let decision = try await engine().matchSpotifyTrackToApple(source)
        switch decision {
        case .auto(let m): XCTAssertNotEqual(m.candidateID, rejected)
        case .ambiguous(let c): XCTAssertFalse(c.contains { $0.candidateID == rejected })
        case .noMatch, .skipped: break
        }
        let stored = try await exclusions.exclusions(for: source.id, targetService: .appleMusic)
        XCTAssertEqual(stored.rejectedCandidateIDs, [rejected])
        XCTAssertFalse(stored.skipped)
    }

    // MARK: Search-backed candidates (#7)

    func testCatalogSearchSuppliesCandidatesWhenNothingLocal() async throws {
        try await trackStore.save(source)
        let noLocal = try await engine().matchSpotifyTrackToApple(source)
        guard case .noMatch = noLocal else { return XCTFail("precondition: no local candidates") }

        let pending = try await service(search: StubSearch(results: [live, single])).pendingResolutions(direction: .spotifyToApple)
        let item = try XCTUnwrap(pending.first, "search hits open the resolver")
        XCTAssertGreaterThanOrEqual(item.candidates.count, 1)
        let saved = try await trackStore.fetchByAppleID("am-1")
        XCTAssertNotNil(saved, "search hits are stored as Apple Music tracks")
    }

    func testSpotifySearchParsesFixtureAndSendsBearerToken() async throws {
        let fixture = """
        {"tracks":{"items":[{"id":"4u7EnebtmKWzUH433cf5Qv","name":"Bohemian Rhapsody - Remastered 2011",
          "artists":[{"name":"Queen"}],"album":{"name":"A Night At The Opera"},"duration_ms":354320,
          "explicit":false,"external_ids":{"isrc":"GBUM71029604"}}]}}
        """
        let log = RequestLog()
        let client = SpotifySearchServiceImpl(
            transport: FixtureTransport(status: 200, body: fixture) { log.add($0, $1) },
            token: { "test-token" }
        )
        let results = try await client.search(query: "Bohemian Rhapsody Queen", limit: 5)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].artistNames, ["Queen"])
        XCTAssertEqual(results[0].isrc, "GBUM71029604")
        XCTAssertEqual(results[0].durationMs, 354320)
        let request = try XCTUnwrap(log.last)
        XCTAssertEqual(request.1["Authorization"], "Bearer test-token")
        let query = URLComponents(url: request.0, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(query.contains(URLQueryItem(name: "type", value: "track")))
        XCTAssertTrue(query.contains(URLQueryItem(name: "limit", value: "5")))
    }

    func testAppleSearchParsesFixture() async throws {
        let fixture = """
        {"results":{"songs":{"data":[{"id":"1440806041","attributes":{"name":"Bohemian Rhapsody",
          "artistName":"Queen","albumName":"A Night at the Opera","durationInMillis":354947,
          "contentRating":"clean","isrc":"GBUM71029604"}}]}}}
        """
        let log = RequestLog()
        let client = AppleSearchServiceImpl(
            transport: FixtureTransport(status: 200, body: fixture) { log.add($0, $1) },
            developerToken: { "dev" },
            storefront: "gb"
        )
        let results = try await client.search(query: "Bohemian Rhapsody Queen", limit: 3)
        XCTAssertEqual(results.first?.id, "1440806041")
        XCTAssertEqual(results.first?.isExplicit, false)
        XCTAssertTrue(log.last?.0.path.hasSuffix("/catalog/gb/search") ?? false)
    }

    func testSearch429SurfacesRetryAfterForBackoff() async throws {
        let client = SpotifySearchServiceImpl(
            transport: FixtureTransport(status: 429, body: "{}", headers: ["Retry-After": "7"]) { _, _ in },
            token: { "t" }
        )
        do {
            _ = try await client.search(query: "x", limit: 1)
            XCTFail("expected HTTPError")
        } catch let error as HTTPError {
            XCTAssertEqual(error.statusCode, 429)
            XCTAssertEqual(error.retryAfter, 7)
            XCTAssertTrue(RetryPolicy.isRetryableError(error))
        }
    }

    func testSearchWithoutCredentialsReturnsNothing() async throws {
        let spotify = try await SpotifySearchServiceImpl().search(query: "x", limit: 1)
        let apple = try await AppleSearchServiceImpl().search(query: "x", limit: 1)
        XCTAssertTrue(spotify.isEmpty)
        XCTAssertTrue(apple.isEmpty)
        XCTAssertEqual(SearchQuery.plain(title: "Heroes (Live) [2017 Remaster]", artist: "David Bowie"), "Heroes David Bowie")
    }

    // MARK: CLI parity (#7)

    func testResolverInputParsingMirrorsUIActions() {
        let ids = ["a", "b", "c"]
        XCTAssertEqual(MatchResolver.parseChoice("2", candidateIDs: ids), .choose(candidateID: "b"))
        XCTAssertEqual(MatchResolver.parseChoice(" x3 ", candidateIDs: ids), .reject(candidateID: "c"))
        XCTAssertEqual(MatchResolver.parseChoice("s", candidateIDs: ids), .skip)
        XCTAssertEqual(MatchResolver.parseChoice("", candidateIDs: ids), .later)
        XCTAssertEqual(MatchResolver.parseChoice("Q", candidateIDs: ids), .quit)
        XCTAssertNil(MatchResolver.parseChoice("4", candidateIDs: ids))
        XCTAssertNil(MatchResolver.parseChoice("x0", candidateIDs: ids))
        XCTAssertNil(MatchResolver.parseChoice("maybe", candidateIDs: ids))
    }

    func testRenderListsNumberedCandidates() {
        let pending = PendingResolution(source: source, targetService: .appleMusic, candidates: [
            ResolutionCandidate(score: MatchScore(candidateID: "am-live", score: 0.78,
                components: MatchScoreComponents(titleScore: 0.8, artistScore: 1, albumScore: 0.2, durationScore: 0.5, isrcBonus: 0),
                method: .fuzzy), track: live)
        ])
        let text = MatchResolver.render(pending, position: 1, total: 4)
        XCTAssertTrue(text.contains("[1/4] Heroes — David Bowie"))
        XCTAssertTrue(text.contains(" 1.  78%  Heroes (Live) — David Bowie (Stage)"), text)
        XCTAssertTrue(text.contains("xN reject"))
    }
}
