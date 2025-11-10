import XCTest
@testable import MergeCore
import GRDB

final class PersistenceTests: XCTestCase {
    var dbProvider: DatabaseProvider!
    var trackStore: TrackStore!
    var playlistStore: PlaylistStore!
    var mappingStore: MappingStore!
    var syncRunStore: SyncRunStore!

    override func setUp() async throws {
        // Create in-memory database for testing
        dbProvider = try DatabaseProvider.inMemory()
        trackStore = TrackStoreImpl(dbQueue: dbProvider.dbQueue)
        playlistStore = PlaylistStoreImpl(dbQueue: dbProvider.dbQueue)
        mappingStore = MappingStoreImpl(dbQueue: dbProvider.dbQueue)
        syncRunStore = SyncRunStoreImpl(dbQueue: dbProvider.dbQueue)
    }

    // MARK: - Track Store Tests

    func testSaveAndFetchTrack() async throws {
        let track = CanonicalTrack(
            id: CanonicalTrackID(value: "track-1"),
            title: "Test Song",
            artist: "Test Artist",
            album: "Test Album",
            durationSeconds: 180,
            isExplicit: false,
            isrc: "USRC17607839",
            spotifyID: "spotify-123",
            appleID: "apple-456",
            availability: [.spotify, .appleMusic]
        )

        try await trackStore.save(track)

        let fetched = try await trackStore.fetch(id: track.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, "Test Song")
        XCTAssertEqual(fetched?.artist, "Test Artist")
        XCTAssertEqual(fetched?.album, "Test Album")
        XCTAssertEqual(fetched?.durationSeconds, 180)
        XCTAssertEqual(fetched?.isExplicit, false)
        XCTAssertEqual(fetched?.isrc, "USRC17607839")
        XCTAssertEqual(fetched?.spotifyID, "spotify-123")
        XCTAssertEqual(fetched?.appleID, "apple-456")
        XCTAssertTrue(fetched!.availability.contains(.spotify))
        XCTAssertTrue(fetched!.availability.contains(.appleMusic))
    }

    func testFetchBySpotifyID() async throws {
        let track = CanonicalTrack(
            id: CanonicalTrackID(value: "track-2"),
            title: "Song 2",
            artist: "Artist 2",
            spotifyID: "spotify-456"
        )

        try await trackStore.save(track)

        let fetched = try await trackStore.fetchBySpotifyID("spotify-456")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id.value, "track-2")
        XCTAssertEqual(fetched?.title, "Song 2")
    }

    func testFetchByAppleID() async throws {
        let track = CanonicalTrack(
            id: CanonicalTrackID(value: "track-3"),
            title: "Song 3",
            artist: "Artist 3",
            appleID: "apple-789"
        )

        try await trackStore.save(track)

        let fetched = try await trackStore.fetchByAppleID("apple-789")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id.value, "track-3")
        XCTAssertEqual(fetched?.title, "Song 3")
    }

    func testSaveAllTracks() async throws {
        let tracks = [
            CanonicalTrack(
                id: CanonicalTrackID(value: "track-a"),
                title: "Song A",
                artist: "Artist A"
            ),
            CanonicalTrack(
                id: CanonicalTrackID(value: "track-b"),
                title: "Song B",
                artist: "Artist B"
            ),
            CanonicalTrack(
                id: CanonicalTrackID(value: "track-c"),
                title: "Song C",
                artist: "Artist C"
            )
        ]

        try await trackStore.saveAll(tracks)

        let all = try await trackStore.fetchAll()
        XCTAssertEqual(all.count, 3)
    }

    func testTrackUpdate() async throws {
        var track = CanonicalTrack(
            id: CanonicalTrackID(value: "track-update"),
            title: "Original Title",
            artist: "Original Artist"
        )

        try await trackStore.save(track)

        // Update track
        track.title = "Updated Title"
        track.appleID = "new-apple-id"
        try await trackStore.save(track)

        let fetched = try await trackStore.fetch(id: track.id)
        XCTAssertEqual(fetched?.title, "Updated Title")
        XCTAssertEqual(fetched?.appleID, "new-apple-id")
    }

    // MARK: - Playlist Store Tests

    func testSaveAndFetchPlaylist() async throws {
        // First, create some tracks
        let track1 = CanonicalTrack(
            id: CanonicalTrackID(value: "playlist-track-1"),
            title: "Track 1",
            artist: "Artist 1"
        )
        let track2 = CanonicalTrack(
            id: CanonicalTrackID(value: "playlist-track-2"),
            title: "Track 2",
            artist: "Artist 2"
        )

        try await trackStore.saveAll([track1, track2])

        // Create playlist with tracks
        let playlist = CanonicalPlaylist(
            id: CanonicalPlaylistID(value: "playlist-1"),
            name: "Test Playlist",
            owner: "User123",
            description: "A test playlist",
            trackIDs: [track1.id, track2.id],
            sourceSpotifyID: "spotify-playlist-1"
        )

        try await playlistStore.save(playlist)

        let fetched = try await playlistStore.fetch(id: playlist.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.name, "Test Playlist")
        XCTAssertEqual(fetched?.owner, "User123")
        XCTAssertEqual(fetched?.description, "A test playlist")
        XCTAssertEqual(fetched?.trackIDs.count, 2)
        XCTAssertEqual(fetched?.trackIDs[0].value, "playlist-track-1")
        XCTAssertEqual(fetched?.trackIDs[1].value, "playlist-track-2")
        XCTAssertEqual(fetched?.sourceSpotifyID, "spotify-playlist-1")
    }

    func testPlaylistTrackOrdering() async throws {
        // Create tracks
        let tracks = (1...5).map { i in
            CanonicalTrack(
                id: CanonicalTrackID(value: "track-\(i)"),
                title: "Track \(i)",
                artist: "Artist \(i)"
            )
        }
        try await trackStore.saveAll(tracks)

        // Create playlist with specific order
        let playlist = CanonicalPlaylist(
            id: CanonicalPlaylistID(value: "ordered-playlist"),
            name: "Ordered Playlist",
            trackIDs: tracks.map { $0.id }
        )

        try await playlistStore.save(playlist)

        let fetched = try await playlistStore.fetch(id: playlist.id)
        XCTAssertEqual(fetched?.trackIDs.count, 5)
        for (index, trackID) in fetched!.trackIDs.enumerated() {
            XCTAssertEqual(trackID.value, "track-\(index + 1)")
        }
    }

    func testPlaylistUpdate() async throws {
        let track1 = CanonicalTrack(
            id: CanonicalTrackID(value: "update-track-1"),
            title: "Track 1",
            artist: "Artist 1"
        )
        let track2 = CanonicalTrack(
            id: CanonicalTrackID(value: "update-track-2"),
            title: "Track 2",
            artist: "Artist 2"
        )
        try await trackStore.saveAll([track1, track2])

        var playlist = CanonicalPlaylist(
            id: CanonicalPlaylistID(value: "update-playlist"),
            name: "Original Name",
            trackIDs: [track1.id]
        )

        try await playlistStore.save(playlist)

        // Update playlist
        playlist.name = "Updated Name"
        playlist.trackIDs = [track2.id, track1.id]  // Reverse order
        try await playlistStore.save(playlist)

        let fetched = try await playlistStore.fetch(id: playlist.id)
        XCTAssertEqual(fetched?.name, "Updated Name")
        XCTAssertEqual(fetched?.trackIDs.count, 2)
        XCTAssertEqual(fetched?.trackIDs[0].value, "update-track-2")
        XCTAssertEqual(fetched?.trackIDs[1].value, "update-track-1")
    }

    // MARK: - Mapping Store Tests

    func testSaveAndFetchManualMapping() async throws {
        let track = CanonicalTrack(
            id: CanonicalTrackID(value: "mapping-track"),
            title: "Mapped Track",
            artist: "Mapped Artist"
        )
        try await trackStore.save(track)

        let mapping = ManualMapping(
            canonicalTrackID: track.id,
            sourceService: .spotify,
            sourceTrackID: "spotify-source-123",
            targetService: .appleMusic,
            targetTrackID: "apple-target-456",
            confidenceScore: 0.92
        )

        try await mappingStore.saveManualMapping(mapping)

        let fetched = try await mappingStore.getManualMapping(
            sourceService: .spotify,
            sourceID: "spotify-source-123"
        )

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.sourceTrackID, "spotify-source-123")
        XCTAssertEqual(fetched?.targetTrackID, "apple-target-456")
        XCTAssertEqual(fetched?.confidenceScore, 0.92)
    }

    func testFetchAllManualMappings() async throws {
        let track1 = CanonicalTrack(id: CanonicalTrackID(value: "map-track-1"), title: "Track 1", artist: "Artist 1")
        let track2 = CanonicalTrack(id: CanonicalTrackID(value: "map-track-2"), title: "Track 2", artist: "Artist 2")
        try await trackStore.saveAll([track1, track2])

        let mapping1 = ManualMapping(
            canonicalTrackID: track1.id,
            sourceService: .spotify,
            sourceTrackID: "spotify-1",
            targetService: .appleMusic,
            targetTrackID: "apple-1"
        )
        let mapping2 = ManualMapping(
            canonicalTrackID: track2.id,
            sourceService: .appleMusic,
            sourceTrackID: "apple-2",
            targetService: .spotify,
            targetTrackID: "spotify-2"
        )

        try await mappingStore.saveManualMapping(mapping1)
        try await mappingStore.saveManualMapping(mapping2)

        let all = try await mappingStore.getAllManualMappings()
        XCTAssertEqual(all.count, 2)
    }

    // MARK: - Sync Run Store Tests

    func testSaveAndFetchSyncRun() async throws {
        let run = SyncRun(
            direction: .spotifyToApple,
            operationsCount: 100,
            successCount: 95,
            failureCount: 5,
            status: .completed,
            durationSeconds: 42.5
        )

        try await syncRunStore.save(run)

        let fetched = try await syncRunStore.fetch(id: run.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.direction, .spotifyToApple)
        XCTAssertEqual(fetched?.operationsCount, 100)
        XCTAssertEqual(fetched?.successCount, 95)
        XCTAssertEqual(fetched?.failureCount, 5)
        XCTAssertEqual(fetched?.status, .completed)
        XCTAssertEqual(fetched?.durationSeconds, 42.5)
    }

    func testFetchRecentSyncRuns() async throws {
        // Create multiple sync runs
        for i in 1...5 {
            let run = SyncRun(
                startedAt: Date().addingTimeInterval(TimeInterval(-i * 3600)),  // Stagger times
                direction: .spotifyToApple,
                status: .completed
            )
            try await syncRunStore.save(run)
        }

        let recent = try await syncRunStore.fetchRecent(limit: 3)
        XCTAssertEqual(recent.count, 3)
        // Should be ordered by most recent first
    }

    func testUpdateSyncRun() async throws {
        var run = SyncRun(
            direction: .bidirectional,
            status: .running
        )

        try await syncRunStore.save(run)

        // Simulate completion
        run.status = .completed
        run.completedAt = Date()
        run.operationsCount = 50
        run.successCount = 48
        run.failureCount = 2
        run.durationSeconds = 30.0

        try await syncRunStore.save(run)

        let fetched = try await syncRunStore.fetch(id: run.id)
        XCTAssertEqual(fetched?.status, .completed)
        XCTAssertNotNil(fetched?.completedAt)
        XCTAssertEqual(fetched?.successCount, 48)
    }
}
