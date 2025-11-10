import XCTest
@testable import MergeCore

final class MatchingTests: XCTestCase {

    // MARK: - Text Normalization Tests

    func testTextNormalization() {
        let normalizer = TrackTextNormalizer()

        // Basic normalization
        XCTAssertEqual(normalizer.normalizeTitle("Test Song"), "test song")
        XCTAssertEqual(normalizer.normalizeTitle("Test Song (Explicit)"), "test song")
        XCTAssertEqual(normalizer.normalizeTitle("Test Song [Radio Edit]"), "test song")
    }

    func testArtistNormalization() {
        let normalizer = TrackTextNormalizer()

        // Extract primary artist
        XCTAssertEqual(
            normalizer.normalizeArtist("Artist A feat. Artist B", extractPrimary: true),
            "artist a"
        )

        XCTAssertEqual(
            normalizer.normalizeArtist("Artist A & Artist B", extractPrimary: true),
            "artist a  artist b"
        )
    }

    func testAlbumNormalization() {
        let normalizer = TrackTextNormalizer()

        XCTAssertEqual(
            normalizer.normalizeAlbum("Album Name (Deluxe Edition)"),
            "album name"
        )

        XCTAssertEqual(
            normalizer.normalizeAlbum("Album Name [2015 Remaster]"),
            "album name"
        )
    }

    // MARK: - ISRC Matching Tests

    func testISRCMatcher() {
        let matcher = ISRCMatcher()

        let track1 = CanonicalTrack(
            id: CanonicalTrackID(value: "1"),
            title: "Song",
            artist: "Artist",
            album: nil,
            durationSeconds: nil,
            isExplicit: false,
            isrc: "USRC12345678",
            spotifyID: "sp1",
            appleID: nil,
            availability: [.spotify]
        )

        let track2 = CanonicalTrack(
            id: CanonicalTrackID(value: "2"),
            title: "Song",
            artist: "Artist",
            album: nil,
            durationSeconds: nil,
            isExplicit: false,
            isrc: "USRC12345678",
            spotifyID: nil,
            appleID: "ap1",
            availability: [.appleMusic]
        )

        XCTAssertTrue(matcher.hasMatchingISRC(track1: track1, track2: track2))
        XCTAssertEqual(matcher.matchScore(track1: track1, track2: track2), 0.95)
    }

    func testISRCMatcher_NoMatch() {
        let matcher = ISRCMatcher()

        let track1 = CanonicalTrack(
            id: CanonicalTrackID(value: "1"),
            title: "Song",
            artist: "Artist",
            album: nil,
            durationSeconds: nil,
            isExplicit: false,
            isrc: "USRC11111111",
            spotifyID: "sp1",
            appleID: nil,
            availability: [.spotify]
        )

        let track2 = CanonicalTrack(
            id: CanonicalTrackID(value: "2"),
            title: "Song",
            artist: "Artist",
            album: nil,
            durationSeconds: nil,
            isExplicit: false,
            isrc: "USRC22222222",
            spotifyID: nil,
            appleID: "ap1",
            availability: [.appleMusic]
        )

        XCTAssertFalse(matcher.hasMatchingISRC(track1: track1, track2: track2))
        XCTAssertEqual(matcher.matchScore(track1: track1, track2: track2), 0.0)
    }

    // MARK: - Duration Matching Tests

    func testDurationMatcher_ExactMatch() {
        let matcher = DurationMatcher(toleranceSeconds: 5)

        XCTAssertTrue(matcher.matchesWithinTolerance(duration1: 180, duration2: 180))
        XCTAssertEqual(matcher.durationScore(duration1: 180, duration2: 180), 1.0)
    }

    func testDurationMatcher_WithinTolerance() {
        let matcher = DurationMatcher(toleranceSeconds: 5)

        // 3 seconds difference
        XCTAssertTrue(matcher.matchesWithinTolerance(duration1: 180, duration2: 183))

        let score = matcher.durationScore(duration1: 180, duration2: 183)
        XCTAssertGreaterThan(score, 0.0)
        XCTAssertLessThan(score, 1.0)
    }

    func testDurationMatcher_OutsideTolerance() {
        let matcher = DurationMatcher(toleranceSeconds: 5)

        // 10 seconds difference
        XCTAssertFalse(matcher.matchesWithinTolerance(duration1: 180, duration2: 190))
        XCTAssertEqual(matcher.durationScore(duration1: 180, duration2: 190), 0.0)
    }

    func testDurationMatcher_MissingDuration() {
        let matcher = DurationMatcher(toleranceSeconds: 5)

        // Missing duration should not filter out
        XCTAssertTrue(matcher.matchesWithinTolerance(duration1: nil, duration2: 180))
        XCTAssertTrue(matcher.matchesWithinTolerance(duration1: 180, duration2: nil))

        // But should get neutral score
        XCTAssertEqual(matcher.durationScore(duration1: nil, duration2: 180), 0.5)
    }

    // MARK: - String Similarity Tests

    func testStringSimilarity_ExactMatch() {
        let similarity = StringSimilarity()

        XCTAssertEqual(similarity.similarity("hello", "hello"), 1.0)
    }

    func testStringSimilarity_NoMatch() {
        let similarity = StringSimilarity()

        XCTAssertEqual(similarity.similarity("hello", "world"), 0.0, accuracy: 0.5)
    }

    func testStringSimilarity_PartialMatch() {
        let similarity = StringSimilarity()

        let score = similarity.similarity("hello world", "hello")
        XCTAssertGreaterThan(score, 0.0)
        XCTAssertLessThan(score, 1.0)
    }

    func testStringSimilarity_CaseInsensitive() {
        let similarity = StringSimilarity()

        // After normalization, should be similar
        let score1 = similarity.similarity("Hello", "hello")
        let score2 = similarity.similarity("HELLO", "hello")

        XCTAssertGreaterThan(score1, 0.8)
        XCTAssertGreaterThan(score2, 0.8)
    }

    // MARK: - Confidence Scoring Tests

    func testConfidenceScorer_PerfectMatch() {
        let scorer = ConfidenceScorer()

        let source = CanonicalTrack(
            id: CanonicalTrackID(value: "1"),
            title: "Bohemian Rhapsody",
            artist: "Queen",
            album: "A Night at the Opera",
            durationSeconds: 354,
            isExplicit: false,
            isrc: "GBUM71029604",
            spotifyID: "sp1",
            appleID: nil,
            availability: [.spotify]
        )

        let candidate = CanonicalTrack(
            id: CanonicalTrackID(value: "2"),
            title: "Bohemian Rhapsody",
            artist: "Queen",
            album: "A Night at the Opera",
            durationSeconds: 354,
            isExplicit: false,
            isrc: "GBUM71029604",
            spotifyID: nil,
            appleID: "ap1",
            availability: [.appleMusic]
        )

        let score = scorer.score(source: source, candidate: candidate)

        XCTAssertEqual(score.method, .isrc)
        XCTAssertEqual(score.score, 0.95)
    }

    func testConfidenceScorer_FuzzyMatch() {
        let scorer = ConfidenceScorer()

        let source = CanonicalTrack(
            id: CanonicalTrackID(value: "1"),
            title: "Test Song",
            artist: "Test Artist",
            album: "Test Album",
            durationSeconds: 180,
            isExplicit: false,
            isrc: nil,
            spotifyID: "sp1",
            appleID: nil,
            availability: [.spotify]
        )

        let candidate = CanonicalTrack(
            id: CanonicalTrackID(value: "2"),
            title: "Test Song",
            artist: "Test Artist",
            album: "Test Album",
            durationSeconds: 180,
            isExplicit: false,
            isrc: nil,
            spotifyID: nil,
            appleID: "ap1",
            availability: [.appleMusic]
        )

        let score = scorer.score(source: source, candidate: candidate)

        XCTAssertEqual(score.method, .fuzzy)
        XCTAssertGreaterThan(score.score, 0.8)
    }

    func testConfidenceScorer_AutoMatchThreshold() {
        let scorer = ConfidenceScorer()

        let source = CanonicalTrack(
            id: CanonicalTrackID(value: "1"),
            title: "Song",
            artist: "Artist",
            album: nil,
            durationSeconds: nil,
            isExplicit: false,
            isrc: nil,
            spotifyID: "sp1",
            appleID: nil,
            availability: [.spotify]
        )

        let highMatch = CanonicalTrack(
            id: CanonicalTrackID(value: "2"),
            title: "Song",
            artist: "Artist",
            album: nil,
            durationSeconds: nil,
            isExplicit: false,
            isrc: nil,
            spotifyID: nil,
            appleID: "ap1",
            availability: [.appleMusic]
        )

        let decision = scorer.makeDecision(source: source, candidates: [highMatch])

        switch decision {
        case .auto(let candidate):
            XCTAssertGreaterThanOrEqual(candidate.score, 0.85)
        case .ambiguous:
            XCTFail("Should be auto-match")
        case .noMatch:
            XCTFail("Should find match")
        }
    }

    func testConfidenceScorer_NoCandidates() {
        let scorer = ConfidenceScorer()

        let source = CanonicalTrack(
            id: CanonicalTrackID(value: "1"),
            title: "Song",
            artist: "Artist",
            album: nil,
            durationSeconds: nil,
            isExplicit: false,
            isrc: nil,
            spotifyID: "sp1",
            appleID: nil,
            availability: [.spotify]
        )

        let decision = scorer.makeDecision(source: source, candidates: [])

        if case .noMatch = decision {
            // Expected
        } else {
            XCTFail("Should be no match")
        }
    }

    // MARK: - Match Score Tests

    func testMatchScore_IsAutoMatch() {
        let score = MatchScore(
            candidateID: "1",
            score: 0.90,
            components: MatchScoreComponents(
                titleScore: 1.0,
                artistScore: 1.0,
                albumScore: 1.0,
                durationScore: 1.0,
                isrcBonus: 0.0
            ),
            method: .fuzzy
        )

        XCTAssertTrue(score.isAutoMatch)
        XCTAssertFalse(score.isAmbiguous)
    }

    func testMatchScore_IsAmbiguous() {
        let score = MatchScore(
            candidateID: "1",
            score: 0.75,
            components: MatchScoreComponents(
                titleScore: 0.8,
                artistScore: 0.8,
                albumScore: 0.7,
                durationScore: 0.9,
                isrcBonus: 0.0
            ),
            method: .fuzzy
        )

        XCTAssertFalse(score.isAutoMatch)
        XCTAssertTrue(score.isAmbiguous)
    }

    // MARK: - Integration Tests

    func testMatchWeights() {
        let weights = MatchWeights.default

        // Verify default weights sum to ~1.0
        let total = weights.title + weights.artist + weights.album + weights.duration
        XCTAssertEqual(total, 1.0, accuracy: 0.01)

        // Title and artist should have highest weight
        XCTAssertGreaterThan(weights.title, weights.album)
        XCTAssertGreaterThan(weights.artist, weights.album)
    }
}
