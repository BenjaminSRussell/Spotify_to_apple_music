import XCTest
@testable import MergeCore

final class DomainTests: XCTestCase {
    func testCanonicalTrackID() {
        let id = CanonicalTrackID(value: "test-id")
        XCTAssertEqual(id.value, "test-id")
    }

    func testCanonicalTrackCreation() {
        let track = CanonicalTrack(
            id: CanonicalTrackID(value: "test-id"),
            title: "Test Song",
            artist: "Test Artist",
            album: "Test Album"
        )

        XCTAssertEqual(track.title, "Test Song")
        XCTAssertEqual(track.artist, "Test Artist")
        XCTAssertEqual(track.album, "Test Album")
    }

    func testAvailabilityFlags() {
        var flags = AvailabilityFlags.spotify
        XCTAssertTrue(flags.contains(.spotify))
        XCTAssertFalse(flags.contains(.appleMusic))

        flags.insert(.appleMusic)
        XCTAssertTrue(flags.contains(.spotify))
        XCTAssertTrue(flags.contains(.appleMusic))
    }

    func testMergePolicy() {
        let policy = MergePolicy.default
        XCTAssertEqual(policy.direction, .spotifyToApple)
        XCTAssertEqual(policy.autoResolveThreshold, 0.85)
        XCTAssertEqual(policy.ambiguousThreshold, 0.65)
    }
}
