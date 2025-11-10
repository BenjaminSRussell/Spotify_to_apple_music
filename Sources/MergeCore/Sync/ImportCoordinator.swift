import Foundation

/// Coordinates importing libraries from music services into the canonical database
public final class ImportCoordinator: Sendable {
    private let trackStore: TrackStore
    private let playlistStore: PlaylistStore
    private let spotifyAuth: SpotifyAuthService
    private let spotifyLibrary: SpotifyLibraryService
    private let appleAuth: AppleAuthService
    private let appleLibrary: AppleLibraryService

    public init(
        trackStore: TrackStore = TrackStoreImpl(),
        playlistStore: PlaylistStore = PlaylistStoreImpl(),
        spotifyAuth: SpotifyAuthService = SpotifyAuthServiceImpl(),
        spotifyLibrary: SpotifyLibraryService = SpotifyLibraryServiceImpl(),
        appleAuth: AppleAuthService = AppleAuthServiceImpl(),
        appleLibrary: AppleLibraryService = AppleLibraryServiceImpl()
    ) {
        self.trackStore = trackStore
        self.playlistStore = playlistStore
        self.spotifyAuth = spotifyAuth
        self.spotifyLibrary = spotifyLibrary
        self.appleAuth = appleAuth
        self.appleLibrary = appleLibrary
    }

    // MARK: - Spotify Import

    /// Import all saved tracks and playlists from Spotify
    public func importFromSpotify() async throws {
        Log.info("🎵 Starting Spotify import...")

        // Ensure authorization
        if !(await spotifyAuth.isAuthorized) {
            Log.info("Spotify authorization required")
            try await spotifyAuth.authorize()
        }

        // Fetch saved tracks
        Log.info("Fetching Spotify saved tracks...")
        let spotifyTracks = try await spotifyLibrary.fetchSavedTracks()
        Log.info("Fetched \(spotifyTracks.count) saved tracks from Spotify")

        // Normalize to canonical tracks
        let canonicalTracks = Normalizer.toCanonical(spotifyTracks: spotifyTracks)

        // Save to database
        Log.info("Saving \(canonicalTracks.count) tracks to database...")
        try await trackStore.saveAll(canonicalTracks)
        Log.info("✅ Saved \(canonicalTracks.count) Spotify tracks")

        // Fetch playlists
        Log.info("Fetching Spotify playlists...")
        let spotifyPlaylists = try await spotifyLibrary.fetchPlaylists()
        Log.info("Fetched \(spotifyPlaylists.count) playlists from Spotify")

        // Process each playlist
        for spotifyPlaylist in spotifyPlaylists {
            // Extract and save tracks from playlist
            let playlistTracks = Normalizer.extractTracksFromPlaylist(spotifyPlaylist: spotifyPlaylist)
            try await trackStore.saveAll(playlistTracks)

            // Convert and save playlist
            let canonicalPlaylist = Normalizer.toCanonical(spotifyPlaylist: spotifyPlaylist)
            try await playlistStore.save(canonicalPlaylist)

            Log.info("  ✅ Imported playlist: \(spotifyPlaylist.name) (\(playlistTracks.count) tracks)")
        }

        Log.info("✅ Spotify import complete!")
        Log.info("   Tracks: \(canonicalTracks.count)")
        Log.info("   Playlists: \(spotifyPlaylists.count)")
    }

    // MARK: - Apple Music Import

    /// Import all library songs and playlists from Apple Music
    public func importFromAppleMusic() async throws {
        Log.info("🍎 Starting Apple Music import...")

        // Ensure authorization
        if !(await appleAuth.isAuthorized) {
            Log.info("Apple Music authorization required")
            try await appleAuth.requestAuthorization()
        }

        // Fetch library songs
        Log.info("Fetching Apple Music library songs...")
        let appleTracks = try await appleLibrary.fetchLibrarySongs()
        Log.info("Fetched \(appleTracks.count) library songs from Apple Music")

        // Normalize to canonical tracks
        let canonicalTracks = Normalizer.toCanonical(appleTracks: appleTracks)

        // Save to database
        Log.info("Saving \(canonicalTracks.count) tracks to database...")
        try await trackStore.saveAll(canonicalTracks)
        Log.info("✅ Saved \(canonicalTracks.count) Apple Music tracks")

        // Fetch playlists
        Log.info("Fetching Apple Music playlists...")
        let applePlaylists = try await appleLibrary.fetchPlaylists()
        Log.info("Fetched \(applePlaylists.count) playlists from Apple Music")

        // Process each playlist
        for applePlaylist in applePlaylists {
            // Extract and save tracks from playlist
            let playlistTracks = Normalizer.extractTracksFromPlaylist(applePlaylist: applePlaylist)
            try await trackStore.saveAll(playlistTracks)

            // Convert and save playlist
            let canonicalPlaylist = Normalizer.toCanonical(applePlaylist: applePlaylist)
            try await playlistStore.save(canonicalPlaylist)

            Log.info("  ✅ Imported playlist: \(applePlaylist.name) (\(playlistTracks.count) tracks)")
        }

        Log.info("✅ Apple Music import complete!")
        Log.info("   Tracks: \(canonicalTracks.count)")
        Log.info("   Playlists: \(applePlaylists.count)")
    }

    // MARK: - Import Summary

    /// Get current database statistics
    public func getImportSummary() async throws -> ImportSummary {
        let tracks = try await trackStore.fetchAll()
        let playlists = try await playlistStore.fetchAll()

        let spotifyTracks = tracks.filter { $0.availability.contains(.spotify) }
        let appleTracks = tracks.filter { $0.availability.contains(.appleMusic) }
        let bothTracks = tracks.filter {
            $0.availability.contains(.spotify) && $0.availability.contains(.appleMusic)
        }

        return ImportSummary(
            totalTracks: tracks.count,
            spotifyTracks: spotifyTracks.count,
            appleTracks: appleTracks.count,
            matchedTracks: bothTracks.count,
            totalPlaylists: playlists.count
        )
    }
}

// MARK: - Import Summary

public struct ImportSummary: Sendable {
    public let totalTracks: Int
    public let spotifyTracks: Int
    public let appleTracks: Int
    public let matchedTracks: Int
    public let totalPlaylists: Int

    public var summary: String {
        """
        📊 Import Summary
        ─────────────────
        Total Tracks: \(totalTracks)
        Spotify Tracks: \(spotifyTracks)
        Apple Music Tracks: \(appleTracks)
        Already Matched: \(matchedTracks)
        Total Playlists: \(totalPlaylists)
        """
    }
}
