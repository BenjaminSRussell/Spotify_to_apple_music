import Foundation
@testable import MergeCore

/// Test fixtures with realistic music data for end-to-end testing
struct TestFixtures {
    
    // MARK: - Spotify Tracks
    
    static let spotifyTracks: [CanonicalTrack] = [
        // Perfect match - same track on both services with ISRC
        CanonicalTrack(
            id: CanonicalTrackID(value: "track_bohemian_rhapsody"),
            title: "Bohemian Rhapsody",
            artist: "Queen",
            album: "A Night at the Opera",
            durationSeconds: 354,
            isExplicit: false,
            isrc: "GBUM71029604",
            spotifyID: "sp_bohemian",
            appleID: nil,
            availability: [.spotify]
        ),
        
        // Good fuzzy match - slight variation in title
        CanonicalTrack(
            id: CanonicalTrackID(value: "track_hotel_california"),
            title: "Hotel California (2013 Remaster)",
            artist: "Eagles",
            album: "Hotel California (2013 Remaster)",
            durationSeconds: 391,
            isExplicit: false,
            isrc: "USEE10001713",
            spotifyID: "sp_hotel_ca",
            appleID: nil,
            availability: [.spotify]
        ),
        
        // Ambiguous match - multiple versions exist
        CanonicalTrack(
            id: CanonicalTrackID(value: "track_stairway"),
            title: "Stairway to Heaven",
            artist: "Led Zeppelin",
            album: "Led Zeppelin IV",
            durationSeconds: 482,
            isExplicit: false,
            isrc: nil,
            spotifyID: "sp_stairway",
            appleID: nil,
            availability: [.spotify]
        ),
        
        // Track with featuring artist
        CanonicalTrack(
            id: CanonicalTrackID(value: "track_stay"),
            title: "Stay (with Justin Bieber)",
            artist: "The Kid LAROI feat. Justin Bieber",
            album: "F*ck Love 3: Over You",
            durationSeconds: 141,
            isExplicit: true,
            isrc: "USCG12101242",
            spotifyID: "sp_stay",
            appleID: nil,
            availability: [.spotify]
        ),
        
        // Track only on Spotify (no Apple match)
        CanonicalTrack(
            id: CanonicalTrackID(value: "track_exclusive"),
            title: "Spotify Exclusive Track",
            artist: "Indie Band",
            album: "Underground Album",
            durationSeconds: 215,
            isExplicit: false,
            isrc: nil,
            spotifyID: "sp_exclusive",
            appleID: nil,
            availability: [.spotify]
        ),
        
        // Live version
        CanonicalTrack(
            id: CanonicalTrackID(value: "track_comfortably_numb"),
            title: "Comfortably Numb (Live)",
            artist: "Pink Floyd",
            album: "Pulse",
            durationSeconds: 562,
            isExplicit: false,
            isrc: "GBAYE9400066",
            spotifyID: "sp_numb_live",
            appleID: nil,
            availability: [.spotify]
        )
    ]
    
    // MARK: - Apple Music Tracks
    
    static let appleTracks: [CanonicalTrack] = [
        // Perfect ISRC match with Spotify
        CanonicalTrack(
            id: CanonicalTrackID(value: "track_bohemian_rhapsody_apple"),
            title: "Bohemian Rhapsody",
            artist: "Queen",
            album: "A Night at the Opera",
            durationSeconds: 354,
            isExplicit: false,
            isrc: "GBUM71029604",  // Same ISRC as Spotify version
            spotifyID: nil,
            appleID: "am_bohemian",
            availability: [.appleMusic]
        ),
        
        // Fuzzy match candidate - album name differs
        CanonicalTrack(
            id: CanonicalTrackID(value: "track_hotel_california_apple"),
            title: "Hotel California",
            artist: "Eagles",
            album: "Hotel California",  // No remaster tag
            durationSeconds: 391,
            isExplicit: false,
            isrc: "USEE10001713",  // Same ISRC
            spotifyID: nil,
            appleID: "am_hotel_ca",
            availability: [.appleMusic]
        ),
        
        // Stairway - original version (will be ambiguous)
        CanonicalTrack(
            id: CanonicalTrackID(value: "track_stairway_original"),
            title: "Stairway to Heaven",
            artist: "Led Zeppelin",
            album: "Led Zeppelin IV",
            durationSeconds: 482,
            isExplicit: false,
            isrc: "USAT21700216",
            spotifyID: nil,
            appleID: "am_stairway_orig",
            availability: [.appleMusic]
        ),
        
        // Stairway - remastered version (also ambiguous)
        CanonicalTrack(
            id: CanonicalTrackID(value: "track_stairway_remaster"),
            title: "Stairway to Heaven - Remaster",
            artist: "Led Zeppelin",
            album: "Led Zeppelin IV (2014 Remaster)",
            durationSeconds: 483,  // 1 second difference
            isExplicit: false,
            isrc: "USAT21700217",
            spotifyID: nil,
            appleID: "am_stairway_rem",
            availability: [.appleMusic]
        ),
        
        // Featured artist match (normalized)
        CanonicalTrack(
            id: CanonicalTrackID(value: "track_stay_apple"),
            title: "Stay",
            artist: "The Kid LAROI & Justin Bieber",  // Different featuring format
            album: "F*ck Love 3: Over You",
            durationSeconds: 141,
            isExplicit: true,
            isrc: "USCG12101242",  // Same ISRC
            spotifyID: nil,
            appleID: "am_stay",
            availability: [.appleMusic]
        ),
        
        // Track only on Apple Music
        CanonicalTrack(
            id: CanonicalTrackID(value: "track_apple_exclusive"),
            title: "Apple Music Exclusive",
            artist: "Exclusive Artist",
            album: "Exclusive Album",
            durationSeconds: 198,
            isExplicit: false,
            isrc: nil,
            spotifyID: nil,
            appleID: "am_exclusive",
            availability: [.appleMusic]
        )
    ]
    
    // MARK: - Playlists
    
    static let spotifyPlaylists: [CanonicalPlaylist] = [
        CanonicalPlaylist(
            id: CanonicalPlaylistID(value: "playlist_rock_classics"),
            name: "Rock Classics",
            owner: "testuser",
            description: "Best rock songs of all time",
            trackIDs: [
                CanonicalTrackID(value: "track_bohemian_rhapsody"),
                CanonicalTrackID(value: "track_hotel_california"),
                CanonicalTrackID(value: "track_stairway"),
                CanonicalTrackID(value: "track_comfortably_numb")
            ],
            sourceSpotifyID: "sp_playlist_rock",
            sourceAppleID: nil
        ),
        
        CanonicalPlaylist(
            id: CanonicalPlaylistID(value: "playlist_workout"),
            name: "Workout Mix",
            owner: "testuser",
            description: "High energy tracks",
            trackIDs: [
                CanonicalTrackID(value: "track_stay")
            ],
            sourceSpotifyID: "sp_playlist_workout",
            sourceAppleID: nil
        )
    ]
    
    // MARK: - Helper Methods
    
    /// Get all tracks (Spotify + Apple Music)
    static var allTracks: [CanonicalTrack] {
        spotifyTracks + appleTracks
    }
    
    /// Get tracks that exist on both services (for testing sync)
    static var tracksOnBothServices: [CanonicalTrack] {
        var tracks = allTracks
        // Simulate tracks being on both services after sync
        tracks = tracks.map { track in
            var updated = track
            updated.availability = [.spotify, .appleMusic]
            return updated
        }
        return tracks
    }
    
    /// Create test database with sample data
    static func setupTestDatabase() async throws {
        let trackStore = TrackStoreImpl(provider: .inMemory())
        let playlistStore = PlaylistStoreImpl(provider: .inMemory())
        
        // Save all tracks
        for track in allTracks {
            try await trackStore.save(track)
        }
        
        // Save playlists
        for playlist in spotifyPlaylists {
            try await playlistStore.save(playlist)
        }
    }
    
    /// Expected matching results for validation
    static let expectedMatches: [String: String] = [
        // Spotify Track ID : Apple Track ID
        "sp_bohemian": "am_bohemian",        // ISRC match - high confidence
        "sp_hotel_ca": "am_hotel_ca",        // ISRC match - high confidence
        "sp_stay": "am_stay",                 // ISRC match + featuring artist normalized
        "sp_stairway": "ambiguous",           // Multiple candidates
        "sp_exclusive": "no_match",           // Spotify only
        "sp_numb_live": "no_match"            // No Apple equivalent
    ]
}
