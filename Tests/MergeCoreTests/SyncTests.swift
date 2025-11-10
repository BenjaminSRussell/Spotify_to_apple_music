import XCTest
@testable import MergeCore

final class SyncTests: XCTestCase {

    // MARK: - Library Diff Tests

    func testLibraryDiff_TotalOperations() {
        let trackOps: [SyncOperation] = [
            .addTrackToApple(canonicalTrackID: CanonicalTrackID(value: "1")),
            .addTrackToApple(canonicalTrackID: CanonicalTrackID(value: "2"))
        ]

        let playlistOps: [SyncOperation] = [
            .createApplePlaylist(playlist: makeTestPlaylist())
        ]

        let diff = LibraryDiff(trackOps: trackOps, playlistOps: playlistOps)

        XCTAssertEqual(diff.totalOperations, 3)
        XCTAssertEqual(diff.trackOps.count, 2)
        XCTAssertEqual(diff.playlistOps.count, 1)
    }

    // MARK: - Sync Result Tests

    func testSyncResult_SuccessRate() {
        let result = SyncResult(
            totalOps: 100,
            successCount: 85,
            failureCount: 15,
            duration: 10.5
        )

        XCTAssertEqual(result.successRate, 0.85)
    }

    func testSyncResult_AllSuccess() {
        let result = SyncResult(
            totalOps: 50,
            successCount: 50,
            failureCount: 0,
            duration: 5.0
        )

        XCTAssertEqual(result.successRate, 1.0)
    }

    func testSyncResult_AllFailure() {
        let result = SyncResult(
            totalOps: 20,
            successCount: 0,
            failureCount: 20,
            duration: 2.0
        )

        XCTAssertEqual(result.successRate, 0.0)
    }

    func testSyncResult_ZeroOps() {
        let result = SyncResult(
            totalOps: 0,
            successCount: 0,
            failureCount: 0,
            duration: 0.0
        )

        XCTAssertEqual(result.successRate, 0.0)
    }

    // MARK: - Dry Run Report Tests

    func testDryRunReport_Summary() {
        let report = DryRunReport(
            trackCount: 50,
            playlistCount: 5,
            totalOperations: 55,
            direction: .spotifyToApple
        )

        let summary = report.asTextSummary()

        XCTAssertTrue(summary.contains("50"))
        XCTAssertTrue(summary.contains("5"))
        XCTAssertTrue(summary.contains("55"))
    }

    // MARK: - Sync Error Tests

    func testSyncError_Creation() {
        let error = SyncError(
            operation: "Add track to Apple Music",
            error: "Network timeout"
        )

        XCTAssertEqual(error.operation, "Add track to Apple Music")
        XCTAssertEqual(error.error, "Network timeout")
        XCTAssertNotNil(error.timestamp)
    }

    // MARK: - Sync Operation Tests

    func testSyncOperation_AddTrack() {
        let trackID = CanonicalTrackID(value: "test-track-123")

        let opApple: SyncOperation = .addTrackToApple(canonicalTrackID: trackID)
        let opSpotify: SyncOperation = .addTrackToSpotify(canonicalTrackID: trackID)

        // Verify operations can be created
        switch opApple {
        case .addTrackToApple(let id):
            XCTAssertEqual(id.value, "test-track-123")
        default:
            XCTFail("Wrong operation type")
        }

        switch opSpotify {
        case .addTrackToSpotify(let id):
            XCTAssertEqual(id.value, "test-track-123")
        default:
            XCTFail("Wrong operation type")
        }
    }

    func testSyncOperation_CreatePlaylist() {
        let playlist = makeTestPlaylist()

        let opApple: SyncOperation = .createApplePlaylist(playlist: playlist)
        let opSpotify: SyncOperation = .createSpotifyPlaylist(playlist: playlist)

        // Verify operations can be created
        switch opApple {
        case .createApplePlaylist(let p):
            XCTAssertEqual(p.name, "Test Playlist")
        default:
            XCTFail("Wrong operation type")
        }

        switch opSpotify {
        case .createSpotifyPlaylist(let p):
            XCTAssertEqual(p.name, "Test Playlist")
        default:
            XCTFail("Wrong operation type")
        }
    }

    func testSyncOperation_UpdatePlaylistMembers() {
        let playlistID = CanonicalPlaylistID(value: "playlist-123")
        let trackIDs = [
            CanonicalTrackID(value: "track-1"),
            CanonicalTrackID(value: "track-2")
        ]

        let opApple: SyncOperation = .updateApplePlaylistMembers(
            playlistID: playlistID,
            trackIDs: trackIDs
        )

        let opSpotify: SyncOperation = .updateSpotifyPlaylistMembers(
            playlistID: playlistID,
            trackIDs: trackIDs
        )

        // Verify operations can be created
        switch opApple {
        case .updateApplePlaylistMembers(let id, let tracks):
            XCTAssertEqual(id.value, "playlist-123")
            XCTAssertEqual(tracks.count, 2)
        default:
            XCTFail("Wrong operation type")
        }

        switch opSpotify {
        case .updateSpotifyPlaylistMembers(let id, let tracks):
            XCTAssertEqual(id.value, "playlist-123")
            XCTAssertEqual(tracks.count, 2)
        default:
            XCTFail("Wrong operation type")
        }
    }

    // MARK: - Helper Methods

    private func makeTestPlaylist() -> CanonicalPlaylist {
        return CanonicalPlaylist(
            id: CanonicalPlaylistID(value: "test-playlist-123"),
            name: "Test Playlist",
            owner: "testuser",
            description: "Test Description",
            trackIDs: [
                CanonicalTrackID(value: "track-1"),
                CanonicalTrackID(value: "track-2")
            ],
            sourceSpotifyID: "spotify-playlist-123",
            sourceAppleID: nil
        )
    }

    private func makeTestTrack(
        id: String,
        title: String,
        artist: String,
        availability: Set<MusicService>
    ) -> CanonicalTrack {
        return CanonicalTrack(
            id: CanonicalTrackID(value: id),
            title: title,
            artist: artist,
            album: nil,
            durationSeconds: nil,
            isExplicit: false,
            isrc: nil,
            spotifyID: availability.contains(.spotify) ? "sp-\(id)" : nil,
            appleID: availability.contains(.appleMusic) ? "am-\(id)" : nil,
            availability: availability
        )
    }
}
