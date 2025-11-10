import Foundation
import SwiftUI
import MergeCore

@MainActor
class AppState: ObservableObject {
    // MARK: - Published Properties
    
    @Published var selectedTab: Tab = .library
    @Published var tracks: [CanonicalTrack] = []
    @Published var playlists: [CanonicalPlaylist] = []
    @Published var syncDirection: MergeDirection = .spotifyToApple
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Services
    
    private let trackStore = TrackStoreImpl()
    private let playlistStore = PlaylistStoreImpl()
    private let importCoordinator = ImportCoordinator()
    private let syncCoordinator = SyncCoordinator()
    
    // MARK: - Initialization
    
    init() {
        Task {
            await loadLibrary()
        }
    }
    
    // MARK: - Library Management
    
    func loadLibrary() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            tracks = try await trackStore.fetchAll()
            playlists = try await playlistStore.fetchAll()
        } catch {
            errorMessage = "Failed to load library: \(error.localizedDescription)"
        }
    }
    
    func importFromSpotify() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            try await importCoordinator.importFromSpotify()
            await loadLibrary()
        } catch {
            errorMessage = "Spotify import failed: \(error.localizedDescription)"
        }
    }
    
    func importFromAppleMusic() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            try await importCoordinator.importFromAppleMusic()
            await loadLibrary()
        } catch {
            errorMessage = "Apple Music import failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Statistics
    
    var libraryStats: LibraryStats {
        LibraryStats(
            totalTracks: tracks.count,
            spotifyTracks: tracks.filter { $0.availability.contains(.spotify) }.count,
            appleTracks: tracks.filter { $0.availability.contains(.appleMusic) }.count,
            totalPlaylists: playlists.count
        )
    }
}

// MARK: - Supporting Types

enum Tab: String, CaseIterable {
    case library = "Library"
    case sync = "Sync"
    case matches = "Matches"
    case settings = "Settings"
    
    var icon: String {
        switch self {
        case .library: return "music.note.list"
        case .sync: return "arrow.triangle.2.circlepath"
        case .matches: return "link"
        case .settings: return "gearshape"
        }
    }
}

struct LibraryStats {
    let totalTracks: Int
    let spotifyTracks: Int
    let appleTracks: Int
    let totalPlaylists: Int
    
    var bothServices: Int {
        // This is a simplified calculation
        // In reality, we'd check for tracks in both services
        min(spotifyTracks, appleTracks)
    }
}
