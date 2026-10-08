import XCTest
@testable import MergeCore

/// #16: the diff entrypoint must report real differences and nothing for identical libraries.
final class DiffComputerTests: XCTestCase {
    private var diffComputer: DiffComputer!

    override func setUp() async throws {
        // Empty in-memory catalog: tracks missing on the target find no candidates -> add ops.
        let db = try DatabaseProvider.inMemory()
        let engine = MatchEngine(
            trackStore: TrackStoreImpl(dbQueue: db.dbQueue),
            mappingStore: MappingStoreImpl(dbQueue: db.dbQueue)
        )
        diffComputer = DiffComputer(matchEngine: engine)
    }

    // MARK: - Fixtures

    private func track(_ id: String, _ availability: AvailabilityFlags) -> CanonicalTrack {
        CanonicalTrack(
            id: CanonicalTrackID(value: id),
            title: "Song \(id)",
            artist: "Artist \(id)",
            spotifyID: availability.contains(.spotify) ? "sp-\(id)" : nil,
            appleID: availability.contains(.appleMusic) ? "am-\(id)" : nil,
            availability: availability
        )
    }

    private func playlist(
        _ id: String,
        _ trackIDs: [String],
        spotify: String? = nil,
        apple: String? = nil
    ) -> CanonicalPlaylist {
        CanonicalPlaylist(
            id: CanonicalPlaylistID(value: id),
            name: "Playlist \(id)",
            trackIDs: trackIDs.map { CanonicalTrackID(value: $0) },
            sourceSpotifyID: spotify,
            sourceAppleID: apple
        )
    }

    private func ids(_ ops: [SyncOperation]) -> [String] {
        ops.map { op in
            switch op {
            case .addTrackToApple(let id): return "addApple:\(id.value)"
            case .addTrackToSpotify(let id): return "addSpotify:\(id.value)"
            case .removeTrackFromApple(let id): return "removeApple:\(id.value)"
            case .removeTrackFromSpotify(let id): return "removeSpotify:\(id.value)"
            case .createApplePlaylist(let p): return "createApple:\(p.id.value)"
            case .createSpotifyPlaylist(let p): return "createSpotify:\(p.id.value)"
            case .updateApplePlaylistMembers(let id, let t): return "updateApple:\(id.value):\(t.count)"
            case .updateSpotifyPlaylistMembers(let id, let t): return "updateSpotify:\(id.value):\(t.count)"
            }
        }
    }

    // MARK: - Tests

    func testIdenticalLibrariesProduceNoOps() async throws {
        let tracks = [track("t1", [.spotify, .appleMusic]), track("t2", [.spotify, .appleMusic])]
        let both = playlist("p1", ["t1", "t2"], spotify: "sp-p1", apple: "am-p1")

        let diff = try await diffComputer.computeLibraryDiff(
            sourceTracks: tracks,
            sourcePlaylists: [both],
            targetPlaylists: [both],
            targetService: .appleMusic
        )

        XCTAssertEqual(diff.trackOps.count, 0)
        XCTAssertEqual(diff.playlistOps.count, 0)
        XCTAssertEqual(diff.totalOperations, 0)
    }

    func testDifferingLibrariesProduceExpectedOps() async throws {
        let tracks = [
            track("t1", [.spotify, .appleMusic]),  // already on Apple -> nothing
            track("t2", [.spotify]),               // missing on Apple -> add
            track("t3", [.spotify])                // missing on Apple -> add
        ]
        let source = [
            playlist("p-new", ["t2"], spotify: "sp-new"),                         // not on Apple -> create
            playlist("p-same", ["t1"], spotify: "sp-same", apple: "am-same"),     // identical -> nothing
            playlist("p-diff", ["t1", "t2", "t3"], spotify: "sp-d", apple: "am-d") // members differ -> update
        ]
        // Target state as last read from Apple Music. p-diff is matched by Apple ID, not canonical ID.
        let target = [
            playlist("p-same", ["t1"], spotify: "sp-same", apple: "am-same"),
            playlist("apple-copy-of-p-diff", ["t1"], apple: "am-d")
        ]

        let diff = try await diffComputer.computeLibraryDiff(
            sourceTracks: tracks,
            sourcePlaylists: source,
            targetPlaylists: target,
            targetService: .appleMusic
        )

        XCTAssertEqual(ids(diff.trackOps), ["addApple:t2", "addApple:t3"])
        XCTAssertEqual(ids(diff.playlistOps), ["createApple:p-new", "updateApple:p-diff:3"])
        XCTAssertEqual(diff.totalOperations, 4)
    }

    func testReorderedPlaylistIsAnUpdate() async throws {
        let source = playlist("p", ["a", "b"], spotify: "sp", apple: "am")
        let target = playlist("p", ["b", "a"], spotify: "sp", apple: "am")
        let ops = try await diffComputer.computePlaylistDiff(
            sourcePlaylists: [source], targetPlaylists: [target], targetService: .appleMusic
        )
        XCTAssertEqual(ids(ops), ["updateApple:p:2"])
    }

    func testUnknownTargetContentsStillUpdate() async throws {
        // Exists on Spotify but its current members were not provided -> conservative update.
        let source = playlist("p", ["a"], spotify: "sp", apple: "am")
        let ops = try await diffComputer.computePlaylistDiff(
            sourcePlaylists: [source], targetService: .spotify
        )
        XCTAssertEqual(ids(ops), ["updateSpotify:p:1"])
    }

    func testAppleToSpotifyDirection() async throws {
        let diff = try await diffComputer.computeLibraryDiff(
            sourceTracks: [track("t9", [.appleMusic])],
            sourcePlaylists: [playlist("pa", ["t9"], apple: "am-pa")],
            targetService: .spotify
        )
        XCTAssertEqual(ids(diff.trackOps), ["addSpotify:t9"])
        XCTAssertEqual(ids(diff.playlistOps), ["createSpotify:pa"])
        XCTAssertTrue(diffComputer.generateDiffSummary(diff, direction: .appleToSpotify).contains("Add to Spotify: 1"))
    }
}
