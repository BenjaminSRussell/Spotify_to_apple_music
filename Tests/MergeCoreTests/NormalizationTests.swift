import XCTest
@testable import MergeCore

final class NormalizationTests: XCTestCase {

    // MARK: - Canonical ID Generation Tests

    func testGenerateCanonicalTrackID_SameMetadata_SameID() {
        let id1 = Normalizer.generateCanonicalTrackID(
            title: "Bohemian Rhapsody",
            artist: "Queen",
            album: "A Night at the Opera",
            durationSeconds: 354
        )

        let id2 = Normalizer.generateCanonicalTrackID(
            title: "Bohemian Rhapsody",
            artist: "Queen",
            album: "A Night at the Opera",
            durationSeconds: 354
        )

        XCTAssertEqual(id1.value, id2.value, "Same metadata should produce same canonical ID")
    }

    func testGenerateCanonicalTrackID_CaseInsensitive() {
        let id1 = Normalizer.generateCanonicalTrackID(
            title: "test song",
            artist: "test artist",
            album: "test album",
            durationSeconds: 180
        )

        let id2 = Normalizer.generateCanonicalTrackID(
            title: "TEST SONG",
            artist: "TEST ARTIST",
            album: "TEST ALBUM",
            durationSeconds: 180
        )

        XCTAssertEqual(id1.value, id2.value, "ID generation should be case-insensitive")
    }

    func testGenerateCanonicalTrackID_DifferentMetadata_DifferentID() {
        let id1 = Normalizer.generateCanonicalTrackID(
            title: "Song A",
            artist: "Artist A",
            album: nil,
            durationSeconds: nil
        )

        let id2 = Normalizer.generateCanonicalTrackID(
            title: "Song B",
            artist: "Artist B",
            album: nil,
            durationSeconds: nil
        )

        XCTAssertNotEqual(id1.value, id2.value, "Different metadata should produce different IDs")
    }

    func testGenerateCanonicalPlaylistID() {
        let id1 = Normalizer.generateCanonicalPlaylistID(
            name: "My Playlist",
            owner: "user123"
        )

        let id2 = Normalizer.generateCanonicalPlaylistID(
            name: "My Playlist",
            owner: "user123"
        )

        XCTAssertEqual(id1.value, id2.value, "Same playlist info should produce same ID")
    }

    // MARK: - Spotify → Canonical Tests

    func testToCanonical_SpotifyTrack() {
        let spotifyTrack = SpotifyTrackRef(
            id: "spotify-123",
            name: "Test Song",
            artistNames: ["Test Artist", "Feature Artist"],
            albumName: "Test Album",
            durationMs: 180000,  // 3 minutes
            isExplicit: true,
            isrc: "USRC12345678"
        )

        let canonical = Normalizer.toCanonical(spotifyTrack: spotifyTrack)

        XCTAssertEqual(canonical.title, "Test Song")
        XCTAssertEqual(canonical.artist, "Test Artist", "Should use first artist")
        XCTAssertEqual(canonical.album, "Test Album")
        XCTAssertEqual(canonical.durationSeconds, 180)
        XCTAssertEqual(canonical.isExplicit, true)
        XCTAssertEqual(canonical.isrc, "USRC12345678")
        XCTAssertEqual(canonical.spotifyID, "spotify-123")
        XCTAssertNil(canonical.appleID, "Apple ID should be nil for Spotify tracks")
        XCTAssertTrue(canonical.availability.contains(.spotify))
        XCTAssertFalse(canonical.availability.contains(.appleMusic))
    }

    func testToCanonical_SpotifyTrackWithNoArtist() {
        let spotifyTrack = SpotifyTrackRef(
            id: "spotify-456",
            name: "Instrumental",
            artistNames: [],
            albumName: nil,
            durationMs: nil,
            isExplicit: false,
            isrc: nil
        )

        let canonical = Normalizer.toCanonical(spotifyTrack: spotifyTrack)

        XCTAssertEqual(canonical.artist, "Unknown Artist", "Should use fallback for empty artist list")
    }

    func testToCanonical_SpotifyPlaylist() {
        let track1 = SpotifyTrackRef(
            id: "track-1",
            name: "Track 1",
            artistNames: ["Artist 1"],
            albumName: "Album 1",
            durationMs: 120000,
            isExplicit: false,
            isrc: nil
        )

        let track2 = SpotifyTrackRef(
            id: "track-2",
            name: "Track 2",
            artistNames: ["Artist 2"],
            albumName: "Album 2",
            durationMs: 150000,
            isExplicit: false,
            isrc: nil
        )

        let spotifyPlaylist = SpotifyPlaylistRef(
            id: "playlist-123",
            name: "Test Playlist",
            owner: "user456",
            description: "My test playlist",
            trackRefs: [track1, track2]
        )

        let canonical = Normalizer.toCanonical(spotifyPlaylist: spotifyPlaylist)

        XCTAssertEqual(canonical.name, "Test Playlist")
        XCTAssertEqual(canonical.owner, "user456")
        XCTAssertEqual(canonical.description, "My test playlist")
        XCTAssertEqual(canonical.trackIDs.count, 2)
        XCTAssertEqual(canonical.sourceSpotifyID, "playlist-123")
        XCTAssertNil(canonical.sourceAppleID)
    }

    // MARK: - Apple Music → Canonical Tests

    func testToCanonical_AppleTrack() {
        let appleTrack = AppleTrackRef(
            id: "apple-789",
            name: "Apple Song",
            artistName: "Apple Artist",
            albumName: "Apple Album",
            durationMs: 200000,
            isExplicit: false,
            isrc: "USRC98765432"
        )

        let canonical = Normalizer.toCanonical(appleTrack: appleTrack)

        XCTAssertEqual(canonical.title, "Apple Song")
        XCTAssertEqual(canonical.artist, "Apple Artist")
        XCTAssertEqual(canonical.album, "Apple Album")
        XCTAssertEqual(canonical.durationSeconds, 200)
        XCTAssertEqual(canonical.isExplicit, false)
        XCTAssertEqual(canonical.isrc, "USRC98765432")
        XCTAssertNil(canonical.spotifyID, "Spotify ID should be nil for Apple tracks")
        XCTAssertEqual(canonical.appleID, "apple-789")
        XCTAssertTrue(canonical.availability.contains(.appleMusic))
        XCTAssertFalse(canonical.availability.contains(.spotify))
    }

    func testToCanonical_ApplePlaylist() {
        let track1 = AppleTrackRef(
            id: "apple-track-1",
            name: "Apple Track 1",
            artistName: "Apple Artist 1",
            albumName: "Apple Album 1",
            durationMs: 180000,
            isExplicit: false,
            isrc: nil
        )

        let applePlaylist = ApplePlaylistRef(
            id: "apple-playlist-456",
            name: "Apple Playlist",
            description: "My Apple playlist",
            trackRefs: [track1]
        )

        let canonical = Normalizer.toCanonical(applePlaylist: applePlaylist)

        XCTAssertEqual(canonical.name, "Apple Playlist")
        XCTAssertNil(canonical.owner, "Apple playlists may not have owner info")
        XCTAssertEqual(canonical.description, "My Apple playlist")
        XCTAssertEqual(canonical.trackIDs.count, 1)
        XCTAssertNil(canonical.sourceSpotifyID)
        XCTAssertEqual(canonical.sourceAppleID, "apple-playlist-456")
    }

    // MARK: - Batch Conversion Tests

    func testToCanonical_SpotifyTrackArray() {
        let tracks = [
            SpotifyTrackRef(id: "1", name: "Song 1", artistNames: ["Artist 1"], albumName: nil, durationMs: nil, isExplicit: false, isrc: nil),
            SpotifyTrackRef(id: "2", name: "Song 2", artistNames: ["Artist 2"], albumName: nil, durationMs: nil, isExplicit: false, isrc: nil),
            SpotifyTrackRef(id: "3", name: "Song 3", artistNames: ["Artist 3"], albumName: nil, durationMs: nil, isExplicit: false, isrc: nil)
        ]

        let canonical = Normalizer.toCanonical(spotifyTracks: tracks)

        XCTAssertEqual(canonical.count, 3)
        XCTAssertEqual(canonical[0].title, "Song 1")
        XCTAssertEqual(canonical[1].title, "Song 2")
        XCTAssertEqual(canonical[2].title, "Song 3")
    }

    func testExtractTracksFromPlaylist_Spotify() {
        let track1 = SpotifyTrackRef(id: "t1", name: "Track 1", artistNames: ["Artist 1"], albumName: nil, durationMs: nil, isExplicit: false, isrc: nil)
        let track2 = SpotifyTrackRef(id: "t2", name: "Track 2", artistNames: ["Artist 2"], albumName: nil, durationMs: nil, isExplicit: false, isrc: nil)

        let playlist = SpotifyPlaylistRef(
            id: "p1",
            name: "Playlist",
            owner: nil,
            description: nil,
            trackRefs: [track1, track2]
        )

        let tracks = Normalizer.extractTracksFromPlaylist(spotifyPlaylist: playlist)

        XCTAssertEqual(tracks.count, 2)
        XCTAssertEqual(tracks[0].title, "Track 1")
        XCTAssertEqual(tracks[1].title, "Track 2")
    }

    // MARK: - ID Stability Tests

    func testCanonicalID_Stable_AcrossServices() {
        // Same track from different services should get the same canonical ID
        let spotifyTrack = SpotifyTrackRef(
            id: "spotify-abc",
            name: "Stable Song",
            artistNames: ["Stable Artist"],
            albumName: "Stable Album",
            durationMs: 240000,
            isExplicit: false,
            isrc: "USRC11111111"
        )

        let appleTrack = AppleTrackRef(
            id: "apple-xyz",
            name: "Stable Song",
            artistName: "Stable Artist",
            albumName: "Stable Album",
            durationMs: 240000,
            isExplicit: false,
            isrc: "USRC11111111"
        )

        let canonicalFromSpotify = Normalizer.toCanonical(spotifyTrack: spotifyTrack)
        let canonicalFromApple = Normalizer.toCanonical(appleTrack: appleTrack)

        XCTAssertEqual(
            canonicalFromSpotify.id.value,
            canonicalFromApple.id.value,
            "Same track from different services should have same canonical ID"
        )
    }
}
