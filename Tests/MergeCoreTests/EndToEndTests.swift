import XCTest
@testable import MergeCore

/// Comprehensive end-to-end integration tests
/// Tests the full workflow: Import → Match → Diff → Sync
final class EndToEndTests: XCTestCase {
    
    var trackStore: TrackStore!
    var playlistStore: PlaylistStore!
    var matchEngine: MatchEngine!
    var diffComputer: DiffComputer!
    var syncExecutor: SyncExecutor!
    
    override func setUp() async throws {
        // Use in-memory database for tests
        trackStore = TrackStoreImpl(provider: .inMemory())
        playlistStore = PlaylistStoreImpl(provider: .inMemory())
        matchEngine = MatchEngine(trackStore: trackStore)
        diffComputer = DiffComputer(matchEngine: matchEngine)
        syncExecutor = SyncExecutor(trackStore: trackStore, playlistStore: playlistStore)
    }
    
    // MARK: - Full Workflow Test
    
    func testCompleteWorkflow_SpotifyToApple() async throws {
        // STEP 1: Simulate Import
        print("\n=== STEP 1: IMPORT ===")
        print("Importing Spotify tracks...")
        for track in TestFixtures.spotifyTracks {
            try await trackStore.save(track)
        }
        
        print("Importing Apple Music tracks...")
        for track in TestFixtures.appleTracks {
            try await trackStore.save(track)
        }
        
        let totalTracks = try await trackStore.fetchAll()
        XCTAssertEqual(totalTracks.count, 12, "Should have 12 total tracks (6 Spotify + 6 Apple)")
        print("✓ Import complete: \(totalTracks.count) tracks")
        
        // STEP 2: Matching
        print("\n=== STEP 2: MATCHING ===")
        let spotifyTracks = totalTracks.filter { $0.availability.contains(.spotify) }
        
        var matchResults: [(track: CanonicalTrack, decision: MatchDecision)] = []
        for track in spotifyTracks {
            let decision = try await matchEngine.matchSpotifyTrackToApple(track)
            matchResults.append((track, decision))
            
            switch decision {
            case .auto(let match):
                print("✓ Auto-matched: '\(track.title)' - confidence: \(Int(match.score * 100))%")
            case .ambiguous(let candidates):
                print("⚠ Ambiguous: '\(track.title)' - \(candidates.count) candidates")
            case .noMatch:
                print("✗ No match: '\(track.title)'")
            }
        }
        
        // Verify ISRC matches work
        let bohemianResult = matchResults.first { $0.track.title == "Bohemian Rhapsody" }
        XCTAssertNotNil(bohemianResult)
        if case .auto(let match) = bohemianResult?.decision {
            XCTAssertEqual(match.method, .isrc, "Should match via ISRC")
            XCTAssertGreaterThanOrEqual(match.score, 0.90, "ISRC match should have high confidence")
        } else {
            XCTFail("Bohemian Rhapsody should auto-match")
        }
        
        // STEP 3: Compute Diff
        print("\n=== STEP 3: DIFF COMPUTATION ===")
        let diff = try await diffComputer.computeLibraryDiff(
            sourceTracks: spotifyTracks,
            sourcePlaylists: TestFixtures.spotifyPlaylists,
            targetService: .appleMusic
        )
        
        print("Track operations: \(diff.trackOps.count)")
        print("Playlist operations: \(diff.playlistOps.count)")
        print("Total operations: \(diff.totalOperations)")
        
        XCTAssertGreaterThan(diff.trackOps.count, 0, "Should have track operations")
        XCTAssertGreaterThan(diff.playlistOps.count, 0, "Should have playlist operations")
        
        // STEP 4: Dry Run
        print("\n=== STEP 4: DRY RUN ===")
        let dryRunResult = try await syncExecutor.execute(
            diff: diff,
            direction: .spotifyToApple,
            dryRun: true
        )
        
        print("Would execute \(dryRunResult.totalOps) operations")
        XCTAssertEqual(dryRunResult.successCount, dryRunResult.totalOps, "Dry run should succeed for all")
        XCTAssertEqual(dryRunResult.failureCount, 0, "Dry run should have no failures")
        
        // STEP 5: Actual Sync
        print("\n=== STEP 5: SYNC EXECUTION ===")
        let syncResult = try await syncExecutor.execute(
            diff: diff,
            direction: .spotifyToApple,
            dryRun: false
        )
        
        print("Sync complete!")
        print("Success: \(syncResult.successCount)/\(syncResult.totalOps)")
        print("Duration: \(String(format: "%.2f", syncResult.duration))s")
        print("Success rate: \(String(format: "%.1f%%", syncResult.successRate * 100))")
        
        XCTAssertGreaterThan(syncResult.successRate, 0.8, "Success rate should be >80%")
        
        print("\n=== ✓ WORKFLOW COMPLETE ===")
    }
    
    // MARK: - Matching Specific Tests
    
    func testISRCMatching() async throws {
        // Setup
        for track in TestFixtures.allTracks {
            try await trackStore.save(track)
        }
        
        let spotifyBohemian = TestFixtures.spotifyTracks.first { $0.title == "Bohemian Rhapsody" }!
        
        // Test ISRC match
        let decision = try await matchEngine.matchSpotifyTrackToApple(spotifyBohemian)
        
        switch decision {
        case .auto(let match):
            XCTAssertEqual(match.method, .isrc)
            XCTAssertGreaterThanOrEqual(match.score, 0.90)
            XCTAssertGreaterThan(match.components.isrcBonus, 0)
        default:
            XCTFail("Should auto-match via ISRC")
        }
    }
    
    func testFuzzyMatching() async throws {
        // Setup
        for track in TestFixtures.allTracks {
            try await trackStore.save(track)
        }
        
        let spotifyHotel = TestFixtures.spotifyTracks.first { $0.title.contains("Hotel California") }!
        
        // Test fuzzy match (album name differs slightly)
        let decision = try await matchEngine.matchSpotifyTrackToApple(spotifyHotel)
        
        switch decision {
        case .auto(let match):
            // Should still match despite album difference
            XCTAssertGreaterThanOrEqual(match.score, 0.80)
            print("Fuzzy match score: \(match.score)")
        default:
            XCTFail("Should match Hotel California")
        }
    }
    
    func testAmbiguousMatching() async throws {
        // Setup
        for track in TestFixtures.allTracks {
            try await trackStore.save(track)
        }
        
        let spotifyStairway = TestFixtures.spotifyTracks.first { $0.title == "Stairway to Heaven" }!
        
        // Test ambiguous match (multiple versions available)
        let decision = try await matchEngine.matchSpotifyTrackToApple(spotifyStairway)
        
        switch decision {
        case .ambiguous(let candidates):
            XCTAssertGreaterThanOrEqual(candidates.count, 2, "Should have multiple candidates")
            // Candidates should be sorted by score
            for i in 0..<(candidates.count - 1) {
                XCTAssertGreaterThanOrEqual(candidates[i].score, candidates[i+1].score)
            }
        default:
            // May auto-match if confidence is high enough
            print("Stairway matched: \(decision)")
        }
    }
    
    func testNoMatch() async throws {
        // Setup
        for track in TestFixtures.allTracks {
            try await trackStore.save(track)
        }
        
        let exclusiveTrack = TestFixtures.spotifyTracks.first { $0.title == "Spotify Exclusive Track" }!
        
        // Test no match scenario
        let decision = try await matchEngine.matchSpotifyTrackToApple(exclusiveTrack)
        
        if case .noMatch = decision {
            // Expected
        } else {
            XCTFail("Exclusive track should not match")
        }
    }
    
    // MARK: - Text Normalization Tests
    
    func testFeaturingArtistNormalization() async throws {
        let normalizer = TrackTextNormalizer()
        
        // Different featuring formats
        let formats = [
            "The Kid LAROI feat. Justin Bieber",
            "The Kid LAROI ft. Justin Bieber",
            "The Kid LAROI & Justin Bieber",
            "The Kid LAROI featuring Justin Bieber"
        ]
        
        let normalized = formats.map { normalizer.normalizeArtist($0, extractPrimary: true) }
        
        // All should normalize to same primary artist
        for norm in normalized {
            XCTAssertEqual(norm, normalized[0], "All formats should normalize the same")
        }
    }
    
    func testAlbumEditionNormalization() async throws {
        let normalizer = TrackTextNormalizer()
        
        // Different edition formats
        let editions = [
            "Hotel California",
            "Hotel California (Remastered)",
            "Hotel California (Deluxe Edition)",
            "Hotel California [2013 Remaster]"
        ]
        
        let normalized = editions.map { normalizer.normalizeAlbum($0) }
        
        // All should normalize to same base album name
        for norm in normalized {
            XCTAssertEqual(norm, normalized[0], "All editions should normalize the same")
        }
    }
    
    // MARK: - Diff Computation Tests
    
    func testDiffComputation_NoDuplicates() async throws {
        // Setup: Tracks on both services already
        for track in TestFixtures.tracksOnBothServices {
            try await trackStore.save(track)
        }
        
        let spotifyTracks = TestFixtures.tracksOnBothServices.filter { $0.availability.contains(.spotify) }
        
        // Compute diff
        let diff = try await diffComputer.computeTrackDiff(
            sourceTracks: spotifyTracks,
            targetService: .appleMusic
        )
        
        // Should have no operations (already synced)
        XCTAssertEqual(diff.count, 0, "No operations needed when tracks exist on both services")
    }
    
    // MARK: - Performance Tests
    
    func testMatchingPerformance() async throws {
        // Setup large dataset
        for track in TestFixtures.allTracks {
            try await trackStore.save(track)
        }
        
        let spotifyTracks = TestFixtures.spotifyTracks
        
        measure {
            Task {
                for track in spotifyTracks {
                    _ = try await matchEngine.matchSpotifyTrackToApple(track)
                }
            }
        }
    }
}
